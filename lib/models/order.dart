import 'dart:convert';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';

class Order {
  final String id;
  final String uniqueId;
  final String customerId;
  final String customerName;

  final List<OrderItem> items; // 記憶體中操作用，不存入 orders 集合
  final String itemSummary; // 存入 orders 集合，用於列表顯示
  final String fabricSummary; // 存入 orders 集合，布料名稱摘要，用於搜尋

  final double subtotal;
  final double discount;
  final double total;

  final double deposit;
  final double balancePayment;
  final String? balancePaymentMethod;
  final DateTime? balancePaidDate;
  final double balance;
  final List<BalancePayment> payments;

  final double materialCost;
  final double laborCost;
  final double outsourcingCost;
  final double fixedCost;
  final double totalCost;
  final double totalProfit;
  final String status;
  final String paymentMethod;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // === 新 POS 系統欄位 ===
  final DateTime? date; // 新 POS: 訂單日期，與 createdAt 相容
  final DateTime? deliveryDate; // 新 POS: 交貨日期
  final bool isFabricOrdered; // 是否已訂購布料
  final String notes; // 訂單備注

  Order({
    required this.id,
    required this.uniqueId,
    required this.customerId,
    required this.customerName,
    required this.items,
    this.itemSummary = '',
    this.fabricSummary = '',
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.deposit,
    this.balancePayment = 0.0,
    this.balancePaymentMethod,
    this.balancePaidDate,
    required this.balance,
    this.payments = const [],
    this.materialCost = 0.0,
    this.laborCost = 0.0,
    this.outsourcingCost = 0.0,
    this.fixedCost = 0.0,
    required this.totalCost,
    required this.totalProfit,
    required this.status,
    required this.paymentMethod,
    this.createdAt,
    this.updatedAt,
    // 新 POS 欄位
    this.date,
    this.deliveryDate,
    this.isFabricOrdered = false,
    this.notes = '',
  });

  bool get isFullyPaid => balance <= 0;

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  factory Order.fromMap(String id, Map<dynamic, dynamic> map) {
    List<OrderItem> orderItems = [];
    // 這裡只嘗試讀取 legacy data，新架構下 items 會從另一個 collection 讀取
    if (map['items'] != null) {
      try {
        List<dynamic> itemsList;
        if (map['items'] is List) {
          itemsList = map['items'];
        } else if (map['items'] is String) {
          // 嘗試解析 JSON 字符串，但如果格式錯誤就跳過
          try {
            final decoded = jsonDecode(map['items']);
            itemsList = (decoded is List) ? decoded : [];
          } catch (parseError) {
            developer.log(
              'Warning: Corrupted items JSON for order $id, skipping legacy items: $parseError',
              name: 'Order',
              error: parseError,
            );
            itemsList = [];
          }
        } else {
          itemsList = [];
        }
        orderItems = itemsList.map((item) {
          try {
            if (item is Map) return OrderItem.fromMap(item);
            if (item is String) return OrderItem.fromMap(jsonDecode(item));
            return OrderItem(
              id: '',
              orderId: id,
              service: 'Unknown',
              price: 0,
              quantity: 0,
            );
          } catch (itemError) {
            developer.log(
              'Warning: Failed to parse individual item in order $id: $itemError',
              name: 'Order',
              error: itemError,
            );
            return OrderItem(
              id: '',
              orderId: id,
              service: 'Unknown',
              price: 0,
              quantity: 0,
            );
          }
        }).toList();
      } catch (e) {
        developer.log(
          'Error parsing items for order $id: $e',
          name: 'Order',
          error: e,
        );
      }
    }

    return Order(
      id: id,
      uniqueId: map['uniqueId']?.toString() ?? '',
      customerId: map['customerId']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? '',
      items: orderItems,
      itemSummary:
          map['itemSummary']?.toString() ??
          (orderItems.isNotEmpty ? '${orderItems.length} items' : ''),
      fabricSummary: map['fabricSummary']?.toString() ?? '',

      subtotal: _parseDouble(map['subtotal']),
      discount: _parseDouble(map['discount']),
      total: _parseDouble(map['total']),
      deposit: _parseDouble(map['deposit']),
      balancePayment: _parseDouble(map['balancePayment']),
      balancePaymentMethod: map['balancePaymentMethod']?.toString(),
      balancePaidDate: map['balancePaidDate'] != null
          ? (map['balancePaidDate'] is Timestamp
                ? (map['balancePaidDate'] as Timestamp).toDate()
                : DateTime.tryParse(map['balancePaidDate'].toString()))
          : null,
      balance: _parseDouble(map['balance']),
      payments: (() {
        final raw = map['payments'];
        if (raw is List && raw.isNotEmpty) {
          return raw
              .map((p) => BalancePayment.fromMap(p as Map))
              .toList();
        }
        // Backward compat: migrate old single-payment fields into list
        final legacyAmt = _parseDouble(map['balancePayment']);
        if (legacyAmt > 0) {
          DateTime legacyDate = DateTime.now();
          if (map['balancePaidDate'] is Timestamp) {
            legacyDate = (map['balancePaidDate'] as Timestamp).toDate();
          } else if (map['balancePaidDate'] != null) {
            legacyDate =
                DateTime.tryParse(map['balancePaidDate'].toString()) ??
                    DateTime.now();
          }
          return [
            BalancePayment(
              amount: legacyAmt,
              method: map['balancePaymentMethod']?.toString() ?? 'Cash',
              paidAt: legacyDate,
            ),
          ];
        }
        return <BalancePayment>[];
      })(),
      materialCost: _parseDouble(map['materialCost']),
      laborCost: _parseDouble(map['laborCost']),
      outsourcingCost: _parseDouble(map['outsourcingCost']),
      fixedCost: _parseDouble(map['fixedCost']),
      totalCost: _parseDouble(map['totalCost']),
      totalProfit: _parseDouble(map['totalProfit']),
      status: map['status']?.toString() ?? 'pending',
      paymentMethod: map['paymentMethod']?.toString() ?? 'Cash',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is Timestamp
                ? (map['createdAt'] as Timestamp).toDate()
                : DateTime.tryParse(map['createdAt'].toString()))
          : null,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is Timestamp
                ? (map['updatedAt'] as Timestamp).toDate()
                : DateTime.tryParse(map['updatedAt'].toString()))
          : null,
      // 新 POS 欄位
      date: map['date'] != null
          ? (map['date'] is Timestamp
                ? (map['date'] as Timestamp).toDate()
                : DateTime.tryParse(map['date'].toString()))
          : null,
      deliveryDate: map['deliveryDate'] != null
          ? (map['deliveryDate'] is Timestamp
                ? (map['deliveryDate'] as Timestamp).toDate()
                : DateTime.tryParse(map['deliveryDate'].toString()))
          : null,
      isFabricOrdered: map['isFabricOrdered'] == true,
      notes: map['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'customerId': customerId,
      'customerName': customerName,
      'itemSummary': itemSummary, // 只存摘要
      'fabricSummary': fabricSummary,
      // 'items': items... // 不存 Items
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'deposit': deposit,
      'balancePayment': balancePayment,
      'balancePaymentMethod': balancePaymentMethod,
      'balancePaidDate': balancePaidDate,
      'balance': balance,
      'payments': payments.map((p) => p.toJson()).toList(),
      'materialCost': materialCost,
      'laborCost': laborCost,
      'outsourcingCost': outsourcingCost,
      'fixedCost': fixedCost,
      'totalCost': totalCost,
      'totalProfit': totalProfit,
      'status': status,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
      // 新 POS 欄位
      'date': date,
      'deliveryDate': deliveryDate,
      'isFabricOrdered': isFabricOrdered,
      'notes': notes,
    };
  }

  Order copyWith({
    String? id,
    List<OrderItem>? items,
    String? itemSummary,
    String? fabricSummary,
    double? subtotal,
    double? discount,
    double? total,
    double? deposit,
    double? balancePayment,
    String? balancePaymentMethod,
    DateTime? balancePaidDate,
    double? balance,
    List<BalancePayment>? payments,
    double? materialCost,
    double? laborCost,
    double? outsourcingCost,
    double? fixedCost,
    double? totalCost,
    double? totalProfit,
    String? status,
    String? paymentMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? date,
    DateTime? deliveryDate,
    bool? isFabricOrdered,
    String? notes,
  }) {
    return Order(
      id: id ?? this.id,
      uniqueId: uniqueId,
      customerId: customerId,
      customerName: customerName,
      items: items ?? this.items,
      itemSummary: itemSummary ?? this.itemSummary,
      fabricSummary: fabricSummary ?? this.fabricSummary,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      deposit: deposit ?? this.deposit,
      balancePayment: balancePayment ?? this.balancePayment,
      balancePaymentMethod: balancePaymentMethod ?? this.balancePaymentMethod,
      balancePaidDate: balancePaidDate ?? this.balancePaidDate,
      balance: balance ?? this.balance,
      payments: payments ?? this.payments,
      materialCost: materialCost ?? this.materialCost,
      laborCost: laborCost ?? this.laborCost,
      outsourcingCost: outsourcingCost ?? this.outsourcingCost,
      fixedCost: fixedCost ?? this.fixedCost,
      totalCost: totalCost ?? this.totalCost,
      totalProfit: totalProfit ?? this.totalProfit,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      date: date ?? this.date,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      isFabricOrdered: isFabricOrdered ?? this.isFabricOrdered,
      notes: notes ?? this.notes,
    );
  }
}

class OrderItem {
  // order_items 文件 ID，只喺本地用嚟對返原本嘅文件，唔寫入資料庫。
  final String? docId;
  final String id;
  final String orderId; // 新增：關聯到訂單 ID
  final String service;
  final double price;
  final int quantity;
  final String? fabricId;
  final String? fabricName;
  final double fabricUsed;
  final double cost; // 每件布料成本
  // 落單時記低嘅每件外判成本；舊資料冇記錄就係 null，計成本時改用 services 設定。
  final double? outsourcingCost;
  final bool isFabricOrdered;
  final bool manualUnitPrice;
  final bool sendToWorkshop; // UI-only: controls workshop order creation on save

  // === 新 POS 系統欄位 ===
  final String? serviceName; // 新 POS: 服務名稱，與 service 重複但保留以相容
  final String? fabricCode; // 新 POS: 布料代碼，與 fabricId 相容
  final double fabricCost; // 新 POS: 布料單位成本
  final double fabricUsage; // 新 POS: 布料用量

  OrderItem({
    this.docId,
    required this.id,
    this.orderId = '', // 預設空，寫入時補上
    required this.service,
    required this.price,
    required this.quantity,
    this.fabricId,
    this.fabricName,
    this.fabricUsed = 0.0,
    this.cost = 0.0,
    this.outsourcingCost,
    this.isFabricOrdered = false,
    this.manualUnitPrice = false,
    this.sendToWorkshop = true,
    // 新 POS 欄位
    this.serviceName,
    this.fabricCode,
    this.fabricCost = 0.0,
    this.fabricUsage = 0.0,
  });

  factory OrderItem.fromMap(Map<dynamic, dynamic> map) {
    // Try to get fabricUsed first, then fall back to fabricUsage
    final fabricUsedValue = Order._parseDouble(map['fabricUsed']);
    final fabricUsageValue = fabricUsedValue != 0.0
        ? fabricUsedValue
        : Order._parseDouble(map['fabricUsage']);

    return OrderItem(
      id: map['id']?.toString() ?? '',
      orderId: map['orderId']?.toString() ?? '',
      service:
          map['service']?.toString() ?? map['serviceName']?.toString() ?? '',
      price: Order._parseDouble(map['price']),
      quantity: int.tryParse(map['quantity']?.toString() ?? '1') ?? 1,
      fabricId: map['fabricId']?.toString() ?? map['fabricCode']?.toString(),
      fabricName: map['fabricName']?.toString(),
      fabricUsed: fabricUsageValue,
      cost: Order._parseDouble(map['cost']),
      outsourcingCost: map['outsourcingCost'] == null
          ? null
          : Order._parseDouble(map['outsourcingCost']),
      isFabricOrdered: map['isFabricOrdered'] == true,
      manualUnitPrice: map['manualUnitPrice'] == true,
      sendToWorkshop: false, // existing items: don't re-create workshop orders
      // 新 POS 欄位
      serviceName: map['serviceName']?.toString(),
      fabricCode: map['fabricCode']?.toString(),
      fabricCost: Order._parseDouble(map['fabricCost']),
      fabricUsage: fabricUsageValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId, // 存入 orderId
      'service': service,
      'price': price,
      'quantity': quantity,
      'fabricId': fabricId,
      'fabricName': fabricName,
      'fabricUsed': fabricUsed,
      'cost': cost,
      'outsourcingCost': outsourcingCost,
      'isFabricOrdered': isFabricOrdered,
      'manualUnitPrice': manualUnitPrice,
      // sendToWorkshop is UI-only, not persisted to Firestore
      // 新 POS 欄位
      'serviceName': serviceName,
      'fabricCode': fabricCode,
      'fabricCost': fabricCost,
      'fabricUsage': fabricUsage,
    };
  }

  OrderItem copyWith({
    String? docId,
    String? id,
    String? orderId,
    String? service,
    double? price,
    int? quantity,
    String? fabricId,
    String? fabricName,
    double? fabricUsed,
    double? cost,
    double? outsourcingCost,
    bool? isFabricOrdered,
    bool? manualUnitPrice,
    bool? sendToWorkshop,
    String? serviceName,
    String? fabricCode,
    double? fabricCost,
    double? fabricUsage,
  }) {
    return OrderItem(
      docId: docId ?? this.docId,
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      service: service ?? this.service,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      fabricId: fabricId ?? this.fabricId,
      fabricName: fabricName ?? this.fabricName,
      fabricUsed: fabricUsed ?? this.fabricUsed,
      cost: cost ?? this.cost,
      outsourcingCost: outsourcingCost ?? this.outsourcingCost,
      isFabricOrdered: isFabricOrdered ?? this.isFabricOrdered,
      manualUnitPrice: manualUnitPrice ?? this.manualUnitPrice,
      sendToWorkshop: sendToWorkshop ?? this.sendToWorkshop,
      serviceName: serviceName ?? this.serviceName,
      fabricCode: fabricCode ?? this.fabricCode,
      fabricCost: fabricCost ?? this.fabricCost,
      fabricUsage: fabricUsage ?? this.fabricUsage,
    );
  }
}

class BalancePayment {
  final double amount;
  final String method;
  final DateTime paidAt;

  const BalancePayment({
    required this.amount,
    required this.method,
    required this.paidAt,
  });

  factory BalancePayment.fromMap(Map<dynamic, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    if (map['paidAt'] is Timestamp) {
      parsedDate = (map['paidAt'] as Timestamp).toDate();
    } else if (map['paidAt'] != null) {
      parsedDate =
          DateTime.tryParse(map['paidAt'].toString()) ?? DateTime.now();
    }
    return BalancePayment(
      amount: Order._parseDouble(map['amount']),
      method: map['method']?.toString() ?? 'Cash',
      paidAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'method': method,
        'paidAt': paidAt,
      };
}
