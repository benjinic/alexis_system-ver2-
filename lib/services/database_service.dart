import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import '../models/order.dart';
import '../models/material_item.dart';
import '../models/workshop_order.dart';
import '../models/contact_log.dart';
import '../models/customer.dart';
import '../models/service_item.dart';
import 'database_service_interface.dart';
import 'fabric_order_status_sync.dart';

class StaffAccountException implements Exception {
  const StaffAccountException({this.code, required this.message});

  final String? code;
  final String message;

  @override
  String toString() => message;
}

class DatabaseService implements DatabaseServiceInterface {
  static const String _logName = 'DatabaseService';
  static final Uri _allocateOrderIdUri = Uri.parse(
    'https://us-central1-alexis-tailor-system-2025.cloudfunctions.net/allocateOrderId',
  );

  static final Uri _createStaffAccountUri = Uri.parse(
    'https://us-central1-alexis-tailor-system-2025.cloudfunctions.net/createStaffAccount',
  );

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: _logName,
      error: error,
      stackTrace: stackTrace,
    );
  }

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
  final CollectionReference _orderImagesRef = FirebaseFirestore.instance
      .collection('order_images');

  // === 1. Orders (訂單) ===

  Future<Map<String, String>> _functionAuthHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in before creating an order.');
    }

    final idToken = await user.getIdToken();
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken();
    } catch (error) {
      _log(
        'App Check token unavailable; continuing with Firebase Auth only.',
        error: error,
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Unable to get Firebase ID token.');
    }

    return {
      'Authorization': 'Bearer $idToken',
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'X-Firebase-AppCheck': appCheckToken,
      'Content-Type': 'application/json',
    };
  }

  // 建立員工帳號（Auth 使用者 + staff 名單）。由後端函式處理，client 不能自行註冊。
  // 失敗時拋出 StaffAccountException，code 對應後端回傳（例如 email-already-in-use）。
  Future<void> createStaffAccount({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      _createStaffAccountUri,
      headers: await _functionAuthHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) return;

    String? code;
    String? message;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      code = body['code']?.toString();
      message = body['error']?.toString();
    } catch (_) {}
    throw StaffAccountException(
      code: code,
      message: message ?? 'HTTP ${response.statusCode}',
    );
  }

  Future<String> _allocateOrderId() async {
    final response = await http.post(
      _allocateOrderIdUri,
      headers: await _functionAuthHeaders(),
      body: '{}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to allocate order ID (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final orderId = data['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) {
      throw Exception('Function did not return an order ID.');
    }

    return orderId;
  }

  Map<String, dynamic> _clientWritableOrderData(Order order) {
    final orderData = order.toJson();
    orderData.remove('items');
    orderData.remove('itemSummary');
    orderData.remove('fabricSummary');
    orderData.remove('materialCost');
    orderData.remove('outsourcingCost');
    orderData.remove('totalCost');
    orderData.remove('totalProfit');
    orderData.remove('isFabricOrdered');
    return orderData;
  }

  // 取得訂單列表 (只讀取主文件，不含詳細 Items，以節省流量)
  // Get orders stream with optional limit parameter (default: no limit for backward compatibility)
  // 取得訂單列表
  // 優化：增加 isIncompleteOnly 參數，讓 Dashboard 只需讀取未完成的訂單
  Stream<List<Order>> getOrdersStream({
    int? limit,
    bool isIncompleteOnly = false,
  }) {
    Query query;

    if (isIncompleteOnly) {
      // whereIn without orderBy avoids requiring a composite index
      query = _ordersRef.where('status', whereIn: ['pending', 'confirmed']);
    } else {
      query = _ordersRef.orderBy('createdAt', descending: true);
      if (limit != null) {
        query = query.limit(limit);
      }
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
    _log('DEBUG: Querying orders between $start and $end');

    return _ordersRef
        .orderBy('createdAt', descending: true)
        .where('createdAt', isGreaterThanOrEqualTo: start) // 起始時間
        .where('createdAt', isLessThanOrEqualTo: end) // 結束時間
        .snapshots()
        .map((snapshot) {
          // 除錯：回傳筆數
          _log('DEBUG: Found ${snapshot.docs.length} documents');

          return snapshot.docs.map((doc) {
            try {
              return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
            } catch (e) {
              // 捕捉單筆解析錯誤，避免整個串流中斷
              _log('DEBUG: Error parsing order ${doc.id}: $e', error: e);
              // 回傳一筆標記為錯誤的占位資料，方便在 UI 上辨識
              return Order(
                id: 'error-${doc.id}',
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
  Stream<List<Order>> getOrdersByBalanceDateStream(
    DateTime start,
    DateTime end,
  ) {
    _log('DEBUG: Querying orders by balancePaidDate between $start and $end');

    return _ordersRef
        .orderBy('balancePaidDate', descending: true)
        .where('balancePaidDate', isGreaterThanOrEqualTo: start)
        .where('balancePaidDate', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
          _log(
            'DEBUG: Found ${snapshot.docs.length} documents (balancePaidDate)',
          );

          return snapshot.docs.map((doc) {
            try {
              return Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>);
            } catch (e) {
              _log(
                'DEBUG: Error parsing order ${doc.id} in balance query: $e',
                error: e,
              );
              // 回傳空訂單避免當機 (僅供除錯)
              return Order(
                id: 'error-${doc.id}',
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
      _log('Error fetching orders once: $e', error: e);
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
      _log('Error fetching items for order $orderId: $e', error: e);
      return [];
    }
  }

  // 新增訂單 (寫入 orders + order_items；聚合欄位由 Cloud Functions 同步)
  Future<String> addOrder(Order order) async {
    final customId = await _allocateOrderId();
    final batch = _firestore.batch();

    batch.set(_ordersRef.doc(customId), _clientWritableOrderData(order));

    for (final item in order.items) {
      final itemRef = _orderItemsRef.doc();
      final itemData = item.toJson();
      itemData['orderId'] = customId;
      batch.set(itemRef, itemData);
    }

    await batch.commit();
    return customId;
  }

  // 更新訂單：client 只寫輸入欄位；成本/利潤/布料狀態由 Cloud Functions 同步。
  Future<void> updateOrder(Order order) async {
    try {
      final oldOrderDoc = await _ordersRef.doc(order.id).get();
      if (!oldOrderDoc.exists) {
        throw Exception("Order to update not found!");
      }

      WriteBatch batch = _firestore.batch();

      batch.update(_ordersRef.doc(order.id), _clientWritableOrderData(order));

      final oldItemsSnapshot = await _orderItemsRef
          .where('orderId', isEqualTo: order.id)
          .get();

      for (var doc in oldItemsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      for (var item in order.items) {
        DocumentReference itemRef = _orderItemsRef.doc();
        Map<String, dynamic> itemData = item.toJson();
        itemData['orderId'] = order.id;
        batch.set(itemRef, itemData);
      }

      await batch.commit();
    } catch (e, stackTrace) {
      _log('Error updating order: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // 只改訂單狀態，唔掂 order_items。
  // 唔好用 updateOrder：佢會刪晒再重寫 order_items，傳入無 items 嘅訂單會清空所有細項。
  Future<void> updateOrderStatus(String orderId, String status) async {
    await _ordersRef.doc(orderId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 保留舊呼叫點；實際同步改由 order_items trigger 聚合到 orders/workshop_orders。
  Future<void> updateOrderFabricStatus({
    required String orderId,
    required bool isFabricOrdered,
  }) async {
    await updateOrderFabricRequiredItemsStatus(
      orderId: orderId,
      isFabricOrdered: isFabricOrdered,
    );
  }

  // 批量更新同一訂單內所有需要布料的細項，並同步主訂單布料狀態。
  Future<void> updateOrderFabricRequiredItemsStatus({
    required String orderId,
    required bool isFabricOrdered,
  }) async {
    final orderItemsSnapshot = await _orderItemsRef
        .where('orderId', isEqualTo: orderId)
        .get();

    final batch = _firestore.batch();
    var hasFabricRequiredItems = false;

    for (final doc in orderItemsSnapshot.docs) {
      final item = doc.data() as Map<String, dynamic>;

      if (!FabricOrderStatusSync.itemMapRequiresFabric(item)) {
        continue;
      }

      hasFabricRequiredItems = true;
      batch.update(doc.reference, {
        'isFabricOrdered': isFabricOrdered,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (hasFabricRequiredItems) {
      await batch.commit();
    }
  }

  // 只更新訂單成本拆解中的 Material / Outsourcing，並同步重算總成本與利潤。
  Future<void> updateOrderCostBreakdown({
    required String orderId,
    required double materialCost,
    required double outsourcingCost,
  }) async {
    if (materialCost < 0 || outsourcingCost < 0) {
      throw Exception('Cost values cannot be negative.');
    }

    throw UnsupportedError(
      'Order cost aggregates are now recalculated by Cloud Functions.',
    );
  }

  // 更新單一訂單細項的訂料狀態，並同步主訂單聚合狀態。
  Future<void> updateOrderItemFabricStatus({
    required String orderId,
    required String itemId,
    required bool isFabricOrdered,
  }) async {
    final itemSnapshot = await _orderItemsRef
        .where('orderId', isEqualTo: orderId)
        .where('id', isEqualTo: itemId)
        .limit(1)
        .get();

    if (itemSnapshot.docs.isEmpty) {
      throw Exception('Order item not found for update');
    }

    await itemSnapshot.docs.first.reference.update({
      'isFabricOrdered': isFabricOrdered,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // The order/workshop aggregate flag is recalculated by Cloud Functions.
  }

  // Delete order and order_items; customer aggregates are recalculated by Cloud Functions.
  Future<void> deleteOrder(String orderId) async {
    try {
      final orderDoc = await _ordersRef.doc(orderId).get();
      if (!orderDoc.exists) return;

      WriteBatch batch = _firestore.batch();

      batch.delete(_ordersRef.doc(orderId));

      final itemsSnapshot = await _orderItemsRef
          .where('orderId', isEqualTo: orderId)
          .get();
      for (var doc in itemsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e, stackTrace) {
      _log('Error deleting order: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<Order>> getOrdersByCustomerId(String customerId) async {
    final snapshot = await _ordersRef
        .where('customerId', isEqualTo: customerId)
        .get();
    final orders = snapshot.docs
        .map(
          (doc) => Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>),
        )
        .toList();
    orders.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return orders;
  }

  Stream<List<Order>> getOrdersByCustomerIdStream(String customerId) {
    return _ordersRef
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snapshot) {
          final orders = snapshot.docs
              .map((doc) =>
                  Order.fromMap(doc.id, doc.data() as Map<dynamic, dynamic>))
              .toList();
          orders.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          return orders;
        });
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
    await _inventoryRef.doc(item.id).set(item.toJson());
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

  // 根據 ID 取得單一布料資訊 (供訂單詳情顯示圖片使用)
  Future<MaterialItem?> getMaterialById(String materialId) async {
    if (materialId.isEmpty) return null;
    try {
      final doc = await _inventoryRef.doc(materialId).get();
      if (doc.exists) {
        return MaterialItem.fromMap(
          doc.id,
          doc.data() as Map<dynamic, dynamic>,
        );
      }
    } catch (e) {
      _log('Error fetching material $materialId: $e', error: e);
    }
    return null;
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

  // 批量更新同一訂單下所有 workshop_orders 的布料狀態
  Future<void> updateWorkshopOrdersFabricStatus({
    required String orderId,
    required bool isFabricOrdered,
  }) async {
    // No-op: workshop fabric aggregate is synced by Cloud Functions from
    // order_items, keeping client writes out of aggregate fields.
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

  Future<List<Customer>> getCustomersOnce() async {
    final snapshot = await _customersRef.orderBy('name').get();
    return snapshot.docs
        .map(
          (doc) => Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>),
        )
        .toList();
  }

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

  Future<void> incrementCustomerStats({
    required String customerId,
    required double totalAmount,
  }) async {
    if (customerId.isEmpty) return;
    await _customersRef.doc(customerId).update({
      'totalSpent': FieldValue.increment(totalAmount),
      'orders': FieldValue.increment(1),
    });
  }

  // === 4b. Customer Stream Aliases (新 POS 系統相容層) ===
  /// Alias for getCustomersStream - used by new POS implementation
  Stream<List<Customer>> customersStream() {
    return getCustomersStream();
  }

  // === 4c. Contact Logs ===

  Stream<List<ContactLog>> getContactLogsStream(String customerId) {
    return _customersRef
        .doc(customerId)
        .collection('contact_logs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ContactLog.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  Future<void> addContactLog(String customerId, ContactLog log) async {
    await _customersRef
        .doc(customerId)
        .collection('contact_logs')
        .add(log.toFirestore());
    if (log.followUpDate != null) {
      await _customersRef.doc(customerId).update({
        'nextFollowUp': log.followUpDate,
      });
    }
  }

  Future<void> deleteContactLog(String customerId, String logId) async {
    await _customersRef
        .doc(customerId)
        .collection('contact_logs')
        .doc(logId)
        .delete();
  }

  Future<void> clearFollowUp(String customerId) async {
    await _customersRef.doc(customerId).update({'nextFollowUp': null});
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
    throw UnsupportedError('Order counter is managed by Cloud Functions.');
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
  Future<String> addService(ServiceItem service) async {
    final docRef = await _servicesRef.add({
      'name': service.name,
      'price': service.price,
      'defaultFabricUsage': service.defaultFabricUsage,
      'durationDays': service.durationDays,
      'outsourcingCost': service.outsourcingCost,
    });
    return docRef.id;
  }

  // 依文件 ID 讀取單一服務項目
  Future<ServiceItem?> getServiceById(String serviceId) async {
    if (serviceId.trim().isEmpty) return null;

    final doc = await _servicesRef.doc(serviceId).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }

    final data = doc.data() as Map<String, dynamic>;
    return ServiceItem.fromMap({...data, 'id': doc.id});
  }

  // 更新服務項目
  Future<void> updateService(ServiceItem service) async {
    if (service.id.trim().isEmpty) {
      throw Exception('Service document ID is missing. Update aborted.');
    }

    await _servicesRef.doc(service.id).update({
      'name': service.name,
      'price': service.price,
      'defaultFabricUsage': service.defaultFabricUsage,
      'durationDays': service.durationDays,
      'outsourcingCost': service.outsourcingCost,
    });
  }

  // Fill missing outsourcing costs with known defaults.
  // Do not overwrite user-managed values.
  Future<void> ensureMinimumServiceOutsourcingCosts({
    required Map<String, double> minimumCostByService,
  }) async {
    if (minimumCostByService.isEmpty) return;

    for (final entry in minimumCostByService.entries) {
      final serviceName = entry.key;
      final minimumCost = entry.value;
      final normalizedName = serviceName.trim().toLowerCase();
      if (normalizedName.isEmpty || minimumCost < 0) {
        continue;
      }

      final snapshot = await _servicesRef
          .where('name', isEqualTo: serviceName)
          .limit(10)
          .get();

      if (snapshot.docs.isEmpty) {
        final fallbackSnapshot = await _servicesRef.limit(200).get();
        final normalizedDocs = fallbackSnapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final rawName = data['name']?.toString().trim().toLowerCase() ?? '';
          return rawName == normalizedName;
        }).toList();

        for (final doc in normalizedDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final hasValue = data['outsourcingCost'] != null;
          if (!hasValue) {
            await doc.reference.update({'outsourcingCost': minimumCost});
          }
        }
        continue;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final hasValue = data['outsourcingCost'] != null;
        if (!hasValue) {
          await doc.reference.update({'outsourcingCost': minimumCost});
        }
      }
    }
  }

  // Backward-compatible wrapper for single-service callers.
  Future<void> ensureMinimumServiceOutsourcingCost({
    required String serviceName,
    required double minimumCost,
  }) {
    return ensureMinimumServiceOutsourcingCosts(
      minimumCostByService: {serviceName: minimumCost},
    );
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

  // 第一次打開時只讀取 Firebase 既有 service 資料，不再寫入本地硬編碼預設值。
  Future<void> seedDefaultServices() async {
    final snapshot = await _servicesRef.limit(1).get();
    if (snapshot.docs.isEmpty) {
      _log(
        'Services collection is empty. Waiting for Firebase service data instead of seeding local defaults.',
      );
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
      _log('Seeding default measurement fields...');
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

  // === Data Cleanup: 清除孤立資料 ===

  /// 掃描並清除系統內無用的孤立資料。
  /// 回傳各類別清除數量的摘要 Map。
  Future<Map<String, int>> cleanupOrphanedData() async {
    int deletedOrderItems = 0;
    int deletedWorkshopOrders = 0;

    // 1. 取得所有有效的訂單 ID
    final ordersSnapshot = await _ordersRef.get();
    final validOrderIds = ordersSnapshot.docs.map((d) => d.id).toSet();

    // 2. 清除無對應訂單的 order_items
    // Firestore whereNotIn 限制每次最多 10 個值，需分批處理
    final orderItemsSnapshot = await _orderItemsRef.get();
    final WriteBatch itemBatch = _firestore.batch();
    int itemBatchCount = 0;

    for (final doc in orderItemsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String orderId = (data['orderId'] ?? '').toString();
      if (orderId.isEmpty || !validOrderIds.contains(orderId)) {
        itemBatch.delete(doc.reference);
        deletedOrderItems++;
        itemBatchCount++;
        // Firestore batch 最多 500 次操作，這裡保守限制 400
        if (itemBatchCount >= 400) break;
      }
    }
    if (deletedOrderItems > 0) {
      await itemBatch.commit();
    }

    // 3. 清除無對應訂單的 workshop_orders
    final workshopSnapshot = await _workshopRef.get();
    final WriteBatch wsBatch = _firestore.batch();
    int wsBatchCount = 0;

    for (final doc in workshopSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String orderId = (data['orderId'] ?? '').toString();
      // workshop_orders 的 orderId 欄位存的是訂單號 (e.g. "14039")
      // 若 orderId 非空且在 validOrderIds 中找不到，則視為孤立
      if (orderId.isNotEmpty && !validOrderIds.contains(orderId)) {
        wsBatch.delete(doc.reference);
        deletedWorkshopOrders++;
        wsBatchCount++;
        if (wsBatchCount >= 400) break;
      }
    }
    if (deletedWorkshopOrders > 0) {
      await wsBatch.commit();
    }

    _log(
      'Cleanup done: $deletedOrderItems orphaned order_items, '
      '$deletedWorkshopOrders orphaned workshop_orders deleted.',
    );

    return {
      'orderItems': deletedOrderItems,
      'workshopOrders': deletedWorkshopOrders,
    };
  }

  // === Order Images ===

  Stream<List<Map<String, dynamic>>> getOrderImagesStream(String orderId) {
    return _orderImagesRef
        .where('orderId', isEqualTo: orderId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => {
                  'docId': doc.id,
                  ...doc.data() as Map<String, dynamic>,
                },
              )
              .toList(),
        );
  }

  Future<String> addOrderImage({
    required String orderId,
    required String imageUrl,
    required String fileName,
  }) async {
    final doc = await _orderImagesRef.add({
      'orderId': orderId,
      'imageUrl': imageUrl,
      'fileName': fileName,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> deleteOrderImage({
    required String docId,
    required String storageUrl,
  }) async {
    await _orderImagesRef.doc(docId).delete();
    try {
      final ref = FirebaseStorage.instance.refFromURL(storageUrl);
      await ref.delete();
    } catch (e) {
      _log('Warning: Could not delete storage file: $e', error: e);
    }
  }
}
