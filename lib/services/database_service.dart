import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import '../models/order.dart';
import '../models/material_item.dart';
import '../models/workshop_order.dart';
import '../models/customer.dart';
import '../models/service_item.dart';
import 'database_service_interface.dart';

class DatabaseService implements DatabaseServiceInterface {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionReference _ordersRef = FirebaseFirestore.instance.collection(
    'orders',
  );
  final CollectionReference _orderItemsRef = FirebaseFirestore.instance
      .collection('order_items');
  final CollectionReference _inventoryRef = FirebaseFirestore.instance
      .collection('inventory');
  final CollectionReference _workshopRef = FirebaseFirestore.instance
      .collection('workshop_orders');
  final CollectionReference _customersRef = FirebaseFirestore.instance
      .collection('customers');
  final CollectionReference _servicesRef = FirebaseFirestore.instance
      .collection('services');

  // === 1. Orders (訂單) ===

  // 取得訂單列表 (只讀取主文件，不含詳細 Items，以節省流量)
  // Get orders stream with optional limit parameter (default: no limit for backward compatibility)
  // 取得訂單列表
  // 優化：增加 isIncompleteOnly 參數，讓 Dashboard 只需讀取未完成的訂單
  Stream<List<Order>> getOrdersStream({
    int? limit,
    bool isIncompleteOnly = false,
  }) {
    Query query = _ordersRef.orderBy('createdAt', descending: true);

    if (isIncompleteOnly) {
      // 只查詢 'pending' 或 'confirmed' 的訂單 (未完成)
      // 注意：這可能需要在 Firebase Console 建立複合索引 (status + createdAt)
      query = query.where('status', whereIn: ['pending', 'confirmed']);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
      }).toList();
    });
  }

  // 新增：取得最近 N 筆訂單 (專門給 Dashboard 列表使用，節省流量)
  Stream<List<Order>> getRecentOrdersStream({int limit = 5}) {
    return _ordersRef
        .orderBy('createdAt', descending: true)
        .limit(limit) // 關鍵：只抓取 limit 筆數
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
          }).toList();
        });
  }

  // 新增：取得特定時間範圍的訂單 (專門給 Dashboard 營收卡片使用)
  Stream<List<Order>> getOrdersByDateRangeStream(DateTime start, DateTime end) {
    // 除錯：列出查詢範圍
    // ignore: avoid_print
    print('DEBUG: Querying orders between ' + start.toString() + ' and ' + end.toString());

    return _ordersRef
        .orderBy('createdAt', descending: true)
        .where('createdAt', isGreaterThanOrEqualTo: start) // 起始時間
        .where('createdAt', isLessThanOrEqualTo: end) // 結束時間
        .snapshots()
        .map((snapshot) {
          // 除錯：回傳筆數
          // ignore: avoid_print
          print('DEBUG: Found ' + snapshot.docs.length.toString() + ' documents');

          return snapshot.docs.map((doc) {
            try {
              return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
            } catch (e) {
              // 捕捉單筆解析錯誤，避免整個串流中斷
              // ignore: avoid_print
              print('DEBUG: Error parsing order ' + doc.id + ': ' + e.toString());
              // 回傳一筆標記為錯誤的占位資料，方便在 UI 上辨識
              return Order(
                id: 'error-' + doc.id,
                uniqueId: '',
                customerId: '',
                customerName: 'Error Data',
                items: const [],
                itemSummary: '',
                subtotal: 0,
                discount: 0,
                total: 0,
                deposit: 0,
                balancePayment: 0,
                balance: 0,
                totalCost: 0,
                totalProfit: 0,
                status: 'error',
                paymentMethod: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
            }
          }).toList();
        });
  }

  // === 新增：取得特定「尾款付款日期」範圍的訂單 (計算現金流用) ===
  // 注意：`where(balancePaidDate)` 與 `orderBy(balancePaidDate)` 可能需要在 Firestore 建立複合索引。
  Stream<List<Order>> getOrdersByBalanceDateStream(DateTime start, DateTime end) {
    // ignore: avoid_print
    print('DEBUG: Querying orders by balancePaidDate between ' + start.toString() + ' and ' + end.toString());

    return _ordersRef
        .orderBy('balancePaidDate', descending: true)
        .where('balancePaidDate', isGreaterThanOrEqualTo: start)
        .where('balancePaidDate', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
          // ignore: avoid_print
          print('DEBUG: Found ' + snapshot.docs.length.toString() + ' documents (balancePaidDate)');

          return snapshot.docs.map((doc) {
            try {
              return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
            } catch (e) {
              // ignore: avoid_print
              print('DEBUG: Error parsing order ' + doc.id + ' in balance query: ' + e.toString());
              // 回傳空訂單避免當機 (僅供除錯)
              return Order(
                id: 'error-' + doc.id,
                uniqueId: '',
                customerId: '',
                customerName: 'Error',
                items: const [],
                itemSummary: '',
                subtotal: 0,
                discount: 0,
                total: 0,
                deposit: 0,
                balancePayment: 0,
                balance: 0,
                totalCost: 0,
                totalProfit: 0,
                status: 'error',
                paymentMethod: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
            }
          }).toList();
        });
  }

  // 優化：只讀取最近的 N 筆訂單 (一次性讀取，不監聽)
  // 適用於 Dashboard 統計數據、快速加載場景
  Future<List<Order>> getOrdersOnce({int limit = 100}) async {
    try {
      final snapshot = await _ordersRef
          .orderBy('createdAt', descending: true) // 按時間倒序
          .limit(limit) // 限制數量，大幅提升速度
          .get();

      return snapshot.docs.map((doc) {
        return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
      }).toList();
    } catch (e) {
      print('Error fetching orders once: $e');
      return [];
    }
  }

  // 修改：從 order_items 集合查詢特定訂單的項目
  Future<List<OrderItem>> getOrderItems(String orderId) async {
    try {
      final snapshot = await _orderItemsRef
          .where('orderId', isEqualTo: orderId)
          .get();

      return snapshot.docs.map((doc) {
        return OrderItem.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      print("Error fetching items for order $orderId: $e");
      return [];
    }
  }

  // 新增訂單 (寫入 orders + 寫入 order_items + 更新 customers)
  Future<String> addOrder(Order order) async {
    final counterRef = _firestore.collection('settings').doc('order_counter');

    DocumentReference? customerRef;
    if (order.customerId.isNotEmpty) {
      customerRef = _customersRef.doc(order.customerId);
    }

    return await _firestore.runTransaction((transaction) async {
      // === 1. 讀取階段 ===
      DocumentSnapshot counterSnapshot;
      try {
        counterSnapshot = await transaction.get(counterRef);
      } catch (e) {
        print("Notice: Counter read failed, using default.");
        throw e;
      }

      DocumentSnapshot? customerSnapshot;
      if (customerRef != null) {
        try {
          customerSnapshot = await transaction.get(customerRef);
        } catch (e) {
          print("Warning: Failed to read customer data: $e");
        }
      }

      // === 2. 邏輯計算 ===
      int nextId = 14038;
      if (counterSnapshot.exists) {
        final data = counterSnapshot.data() as Map<String, dynamic>;
        int currentId = data['current_id'] ?? 14037;
        nextId = currentId + 1;
      }

      int? newCustomerOrders;
      double? newCustomerTotal;

      if (customerSnapshot != null && customerSnapshot.exists) {
        final customerData = customerSnapshot.data() as Map<String, dynamic>;
        int currentOrders = (customerData['orders'] is int)
            ? customerData['orders']
            : 0;

        double currentTotal = 0.0;
        if (customerData['totalSpent'] is num) {
          currentTotal = (customerData['totalSpent'] as num).toDouble();
        } else if (customerData['totalSpent'] is String) {
          currentTotal =
              double.tryParse(customerData['totalSpent'] as String) ?? 0.0;
        }

        newCustomerOrders = currentOrders + 1;
        newCustomerTotal = currentTotal + order.total;
      }

      String summary = order.items.map((i) => i.service).join(', ');
      if (summary.length > 50) summary = '${summary.substring(0, 47)}...';

      // === 3. 寫入階段 ===

      // A. 更新計數器
      transaction.set(counterRef, {'current_id': nextId});

      // B. 寫入主訂單 (orders)
      String customId = nextId.toString(); // 這是本次產生的 Order ID
      final newOrderRef = _ordersRef.doc(customId);

      Map<String, dynamic> orderData = order.toJson();
      orderData['itemSummary'] = summary;
      orderData.remove('items'); // 移除 items 陣列

      transaction.set(newOrderRef, orderData);

      // C. 寫入訂單項目 (order_items)
      for (var item in order.items) {
        DocumentReference itemRef = _orderItemsRef.doc(); // 自動產生 ID

        // 重要：補上 orderId，這樣才能關聯回去
        Map<String, dynamic> itemData = item.toJson();
        itemData['orderId'] = customId;

        transaction.set(itemRef, itemData);
      }

      // D. 更新客戶
      if (customerRef != null && newCustomerOrders != null) {
        transaction.update(customerRef, {
          'orders': newCustomerOrders,
          'totalSpent': newCustomerTotal,
        });
      }

      return customId;
    });
  }

  // 更新訂單 (主要更新主文件狀態)
  // 更新訂單 (完整版：同步更新細項、主檔與客戶消費額)
  Future<void> updateOrder(Order order) async {
    try {
      // 1. 先讀取舊訂單資料 (為了計算金額差額)
      final oldOrderDoc = await _ordersRef.doc(order.id).get();
      if (!oldOrderDoc.exists) {
        throw Exception("Order to update not found!");
      }

      final oldOrderData = oldOrderDoc.data() as Map<String, dynamic>;

      // 確保數值安全轉換
      double oldTotal = (oldOrderData['total'] is num)
          ? (oldOrderData['total'] as num).toDouble()
          : double.tryParse(oldOrderData['total'].toString()) ?? 0.0;

      // 計算差額 (新金額 - 舊金額)
      // 例如：原本 1000，改成 1200 -> 差額 +200
      // 例如：原本 1000，改成 800  -> 差額 -200
      double diff = order.total - oldTotal;

      // 2. 開始批次寫入 (Batch) - 確保所有變更同時生效
      WriteBatch batch = _firestore.batch();

      // A. 更新主訂單 (Orders Collection)
      Map<String, dynamic> orderData = order.toJson();

      // 重新生成商品摘要 (例如 "Suit, Shirt...")
      String summary = order.items.map((i) => i.service).join(', ');
      if (summary.length > 50) summary = '${summary.substring(0, 47)}...';
      orderData['itemSummary'] = summary;

      // 移除 items 陣列 (因為主檔不存細項，這是正規化設計)
      orderData.remove('items');

      batch.update(_ordersRef.doc(order.id), orderData);

      // B. 更新客戶累積消費 (Customers Collection)
      // 只有當金額有變動，且有關聯客戶時才更新
      if (diff != 0 && order.customerId.isNotEmpty) {
        batch.update(_customersRef.doc(order.customerId), {
          'totalSpent': FieldValue.increment(diff),
        });
      }

      // C. 重建訂單細項 (Order Items Collection)
      // 策略：先查詢並刪除所有舊的，再寫入新的。這比「比對差異」更安全且簡單。

      // C-1. 找出舊的細項
      final oldItemsSnapshot = await _orderItemsRef
          .where('orderId', isEqualTo: order.id)
          .get();

      // C-2. 全部刪除
      for (var doc in oldItemsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // C-3. 寫入新的細項
      for (var item in order.items) {
        DocumentReference itemRef = _orderItemsRef.doc(); // 自動產生新 ID
        Map<String, dynamic> itemData = item.toJson();
        itemData['orderId'] = order.id; // 綁定訂單 ID
        batch.set(itemRef, itemData);
      }

      // 3. 提交所有變更
      await batch.commit();
    } catch (e) {
      print("Error updating order: $e");
      throw e; // 拋出錯誤讓 UI 層顯示 SnackBar
    }
  }

  // Optimized delete order: updates customer stats and cleans up items atomically
  Future<void> deleteOrder(String orderId) async {
    try {
      // 1. Fetch order data to know customer ID and order total
      final orderDoc = await _ordersRef.doc(orderId).get();
      if (!orderDoc.exists) return;

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final String customerId = orderData['customerId'] ?? '';
      // Safe type conversion for total amount
      final double totalAmount = (orderData['total'] is num)
          ? (orderData['total'] as num).toDouble()
          : double.tryParse(orderData['total'].toString()) ?? 0.0;

      // Use batch for atomic transaction: all succeed or all fail
      WriteBatch batch = _firestore.batch();

      // 2. Update customer stats (decrement orders count and total spent)
      if (customerId.isNotEmpty) {
        final customerRef = _customersRef.doc(customerId);
        batch.update(customerRef, {
          'orders': FieldValue.increment(-1), // Decrement order count
          'totalSpent': FieldValue.increment(
            -totalAmount,
          ), // Subtract order amount
        });
      }

      // 3. Delete main order document
      batch.delete(_ordersRef.doc(orderId));

      // 4. Delete associated order items
      final itemsSnapshot = await _orderItemsRef
          .where('orderId', isEqualTo: orderId)
          .get();
      for (var doc in itemsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 5. Commit all changes atomically
      await batch.commit();
    } catch (e) {
      print("Error deleting order: $e");
      throw e; // Re-throw for UI layer error handling
    }
  }

  Future<List<Order>> getOrdersByCustomerId(String customerId) async {
    final snapshot = await _ordersRef
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map(
          (doc) => Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>),
        )
        .toList();
  }

  // === 2. Inventory (庫存/布料) ===

  // 取得布料列表 (Stream)
  Stream<List<MaterialItem>> getInventoryStream() {
    return _inventoryRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return MaterialItem.fromMap(
          doc.id,
          doc.data() as Map<dynamic, dynamic>,
        );
      }).toList();
    });
  }

  // 新增布料
  Future<void> addMaterial(MaterialItem item) async {
    await _inventoryRef.add(item.toJson());
  }

  // 更新布料
  Future<void> updateMaterial(MaterialItem item) async {
    await _inventoryRef.doc(item.id).update(item.toJson());
  }

  // 刪除布料
  Future<void> deleteMaterial(String itemId) async {
    await _inventoryRef.doc(itemId).delete();
  }

  // 取得所有布料列表 (Future - 一次性取得)
  Future<List<MaterialItem>> getInventory() async {
    final snapshot = await _inventoryRef.get();
    return snapshot.docs.map((doc) {
      return MaterialItem.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
    }).toList();
  }

  // === 2b. Inventory Stream Aliases (新 POS 系統相容層) ===
  /// Alias for getInventoryStream - used by new POS implementation
  Stream<List<MaterialItem>> materialsStream() {
    return getInventoryStream();
  }

  // === 3. Workshop Orders (工場單) ===

  // 優化：增加 isOnGoingOnly 參數
  Stream<List<WorkshopOrder>> getWorkshopOrdersStream({
    bool isOnGoingOnly = false,
  }) {
    Query query = _workshopRef.orderBy('createdAt', descending: true);

    if (isOnGoingOnly) {
      // 只查詢生產中的階段 (排除 completed 和 archived)
      // 注意：這可能需要在 Firebase Console 建立複合索引 (status + createdAt)
      query = query.where(
        'status',
        whereIn: ['measuring', 'cutting', 'sewing', 'finishing'],
      );
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return WorkshopOrder.fromMap(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }).toList();
    });
  }

  Future<void> addWorkshopOrder(WorkshopOrder order) async {
    await _workshopRef.add(order.toJson());
  }

  Future<void> updateWorkshopOrderStatus(String id, String status) async {
    await _workshopRef.doc(id).update({'status': status});
  }

  Future<void> updateWorkshopOrder(WorkshopOrder order) async {
    // 確保 ID 不為空
    if (order.id.isEmpty) throw Exception('Order ID is missing');

    await _workshopRef.doc(order.id).update(order.toJson());
  }

  // === 3b. Method Aliases (新 POS 系統相容層) ===
  /// Alias for addOrder - used by new POS implementation
  Future<String> createOrder(Order order) async {
    return addOrder(order);
  }

  /// Alias for addWorkshopOrder - used by new POS implementation
  Future<void> createWorkshopOrder(WorkshopOrder order) async {
    return addWorkshopOrder(order);
  }

  // === 4. Customers (客戶) ===

  Stream<List<Customer>> getCustomersStream() {
    return _customersRef.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }

  // 單一客戶即時串流：保持顯示頁面與最新資料同步
  Stream<Customer?> getCustomerStream(String customerId) {
    return _customersRef.doc(customerId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    });
  }

  // === 新增：取得消費最高的客戶 (Top 10 優化版) ===
  // 直接從資料庫排序讀取，不需要下載訂單來計算，速度極快
  Stream<List<Customer>> getTopCustomersStream({int limit = 10}) {
    return _customersRef
        .orderBy('totalSpent', descending: true) // 依累積消費金額排序 (Lifetime Value)
        .limit(limit) // 只抓取前 10 筆
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }

  // === 新增：根據一組 ID 取得特定客戶列表 (用於 Top 10 顯示) ===
  Stream<List<Customer>> getCustomersByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value([]);
    
    // Firestore whereIn 最多支援 10 個元素，剛好符合 Top 10 需求
    // 如果 id 超過 10 個，這裡只取前 10 個以避免報錯
    final targetIds = ids.length > 10 ? ids.sublist(0, 10) : ids;

    return _customersRef
        .where(FieldPath.documentId, whereIn: targetIds)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }

  Future<String> addCustomer(Customer customer) async {
    final docRef = await _customersRef.add(customer.toJson());
    return docRef.id;
  }

  Future<void> updateCustomer(Customer customer) async {
    await _customersRef.doc(customer.id).update(customer.toJson());
  }

  // === 4b. Customer Stream Aliases (新 POS 系統相容層) ===
  /// Alias for getCustomersStream - used by new POS implementation
  Stream<List<Customer>> customersStream() {
    return getCustomersStream();
  }

  // === 5. Settings (系統設定) ===

  // 取得下一個訂單號碼 (Stream)
  Stream<int> getNextOrderIdStream() {
    return _firestore
        .collection('settings')
        .doc('order_counter')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return 14038; // 預設起始編號
          }
          final data = snapshot.data() as Map<String, dynamic>;
          return data['current_id'] as int? ?? 14038;
        });
  }

  // 設定下一個訂單號碼
  Future<void> setNextOrderNumber(int newId) async {
    await _firestore.collection('settings').doc('order_counter').set({
      'current_id': newId,
    }, SetOptions(merge: true));
  }

  // === 6. Services (服務項目) ===

  // 取得所有服務項目 (Stream)
  @override
  Stream<List<ServiceItem>> getServicesStream() {
    return _servicesRef.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ServiceItem.fromMap({...data, 'id': doc.id});
      }).toList();
    });
  }

  // 新增服務項目
  Future<void> addService(ServiceItem service) async {
    await _servicesRef.add({
      'name': service.name,
      'price': service.price,
      'defaultFabricUsage': service.defaultFabricUsage,
      'durationDays': service.durationDays,
    });
  }

  // 更新服務項目
  Future<void> updateService(ServiceItem service) async {
    await _servicesRef.doc(service.id).update({
      'name': service.name,
      'price': service.price,
      'defaultFabricUsage': service.defaultFabricUsage,
      'durationDays': service.durationDays,
    });
  }

  // === 6b. Service Stream Aliases (新 POS 系統相容層) ===
  /// Alias for getServicesStream - used by new POS implementation
  Stream<List<ServiceItem>> servicesStream() {
    return getServicesStream();
  }

  // 刪除服務項目
  Future<void> deleteService(String serviceId) async {
    await _servicesRef.doc(serviceId).delete();
  }

  // 確保有預設服務資料 (第一次打開時)
  // Check if default services need to be initialized (seed if empty)
  Future<void> seedDefaultServices() async {
    final snapshot = await _servicesRef.limit(1).get();
    if (snapshot.docs.isEmpty) {
      print("Seeding default services...");
      final defaults = [
        // Set default manufacturing days based on service type
        {
          'name': '3-Piece Suit',
          'price': 1200.0,
          'defaultFabricUsage': 3.5,
          'durationDays': 21,
        },
        {
          'name': '2-Piece Suit',
          'price': 850.0,
          'defaultFabricUsage': 3.0,
          'durationDays': 21,
        },
        {
          'name': 'Blazer',
          'price': 450.0,
          'defaultFabricUsage': 2.0,
          'durationDays': 21,
        }, // Jacket
        {
          'name': 'Trousers',
          'price': 250.0,
          'defaultFabricUsage': 1.5,
          'durationDays': 15,
        },
        {
          'name': 'Shirt',
          'price': 180.0,
          'defaultFabricUsage': 1.5,
          'durationDays': 10,
        },
        {
          'name': 'Wedding Dress',
          'price': 2500.0,
          'defaultFabricUsage': 5.0,
          'durationDays': 30,
        },
        {
          'name': 'Alterations',
          'price': 50.0,
          'defaultFabricUsage': 0.0,
          'durationDays': 5,
        }, // Other
      ];

      for (var item in defaults) {
        await _servicesRef.add(item);
      }
    }
  }

  // === 7. Measurement Fields Config (體型數據欄位設定) ===

  // 取得體型數據欄位設定 (Stream)
  Stream<List<String>> getMeasurementFieldsStream() {
    return _firestore
        .collection('settings')
        .doc('measurements')
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data() as Map<String, dynamic>;
            // 轉為 List<String>
            return List<String>.from(data['fields'] ?? []);
          }
          return <String>[]; // 若無設定回傳空列表
        });
  }

  // 更新體型數據欄位 (覆蓋寫入)
  Future<void> updateMeasurementFields(List<String> fields) async {
    await _firestore.collection('settings').doc('measurements').set({
      'fields': fields,
    });
  }

  // 初始化預設體型欄位 (如果資料庫是空的)
  Future<void> seedMeasurementFields() async {
    final doc = await _firestore
        .collection('settings')
        .doc('measurements')
        .get();
    if (!doc.exists) {
      print("Seeding default measurement fields...");
      final defaultFields = [
        'Neck',
        'Shoulder',
        'Chest',
        'Waist',
        'Hips',
        'Sleeve',
        'Jacket Length',
        'Pant Waist',
        'Inseam',
        'Thigh',
        'Cuff',
      ];
      await updateMeasurementFields(defaultFields);
    }
  }
}
