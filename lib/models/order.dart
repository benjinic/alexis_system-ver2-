import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class Order {
  final String id;
  final String uniqueId;
  final String customerId;
  final String customerName;
  
  final List<OrderItem> items; // 記憶體中操作用，不存入 orders 集合
  final String itemSummary;    // 存入 orders 集合，用於列表顯示
  
  final double subtotal;
  final double discount;
  final double total;
  
  final double deposit;
  final double balancePayment;
  final String? balancePaymentMethod;
  final DateTime? balancePaidDate;
  final double balance;
  
  final double totalCost;
  final double totalProfit;
  final String status;
  final String paymentMethod;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // === 新 POS 系統欄位 ===
  final DateTime? date;         // 新 POS: 訂單日期，與 createdAt 相容
  final DateTime? deliveryDate; // 新 POS: 交貨日期

  Order({
    required this.id,
    required this.uniqueId,
    required this.customerId,
    required this.customerName,
    required this.items,
    this.itemSummary = '',
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.deposit,
    this.balancePayment = 0.0,
    this.balancePaymentMethod,
    this.balancePaidDate,
    required this.balance,
    required this.totalCost,
    required this.totalProfit,
    required this.status,
    required this.paymentMethod,
    this.createdAt,
    this.updatedAt,
    // 新 POS 欄位
    this.date,
    this.deliveryDate,
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
            print("Warning: Corrupted items JSON for order $id, skipping legacy items: $parseError");
            itemsList = [];
          }
        } else {
          itemsList = [];
        }
        orderItems = itemsList.map((item) {
          try {
            if (item is Map) return OrderItem.fromMap(item);
            if (item is String) return OrderItem.fromMap(jsonDecode(item));
            return OrderItem(id: '', orderId: id, service: 'Unknown', price: 0, quantity: 0);
          } catch (itemError) {
            print("Warning: Failed to parse individual item in order $id: $itemError");
            return OrderItem(id: '', orderId: id, service: 'Unknown', price: 0, quantity: 0);
          }
        }).toList();
      } catch (e) {
        print("Error parsing items for order $id: $e");
      }
    }

    return Order(
      id: id,
      uniqueId: map['uniqueId']?.toString() ?? '',
      customerId: map['customerId']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? '',
      items: orderItems,
      itemSummary: map['itemSummary']?.toString() ?? 
          (orderItems.isNotEmpty ? '${orderItems.length} items' : ''), 
      
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'customerId': customerId,
      'customerName': customerName,
      'itemSummary': itemSummary, // 只存摘要
      // 'items': items... // 不存 Items
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'deposit': deposit,
      'balancePayment': balancePayment,
      'balancePaymentMethod': balancePaymentMethod,
      'balancePaidDate': balancePaidDate,
      'balance': balance,
      'totalCost': totalCost,
      'totalProfit': totalProfit,
      'status': status,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
      // 新 POS 欄位
      'date': date,
      'deliveryDate': deliveryDate,
    };
  }
  
  Order copyWith({
    String? id,
    List<OrderItem>? items,
    String? itemSummary,
  }) {
    return Order(
      id: id ?? this.id,
      uniqueId: this.uniqueId,
      customerId: this.customerId,
      customerName: this.customerName,
      items: items ?? this.items,
      itemSummary: itemSummary ?? this.itemSummary,
      subtotal: this.subtotal,
      discount: this.discount,
      total: this.total,
      deposit: this.deposit,
      balancePayment: this.balancePayment,
      balancePaymentMethod: this.balancePaymentMethod,
      balancePaidDate: this.balancePaidDate,
      balance: this.balance,
      totalCost: this.totalCost,
      totalProfit: this.totalProfit,
      status: this.status,
      paymentMethod: this.paymentMethod,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
      date: this.date,
      deliveryDate: this.deliveryDate,
    );
  }
}

class OrderItem {
  final String id;
  final String orderId; // 新增：關聯到訂單 ID
  final String service;
  final double price;
  final int quantity;
  final String? fabricId;
  final String? fabricName;
  final double fabricUsed;
  final double cost;

  // === 新 POS 系統欄位 ===
  final String? serviceName;    // 新 POS: 服務名稱，與 service 重複但保留以相容
  final String? fabricCode;     // 新 POS: 布料代碼，與 fabricId 相容
  final double fabricCost;      // 新 POS: 布料單位成本
  final double fabricUsage;     // 新 POS: 布料用量

  OrderItem({
    required this.id,
    this.orderId = '', // 預設空，寫入時補上
    required this.service,
    required this.price,
    required this.quantity,
    this.fabricId,
    this.fabricName,
    this.fabricUsed = 0.0,
    this.cost = 0.0,
    // 新 POS 欄位
    this.serviceName,
    this.fabricCode,
    this.fabricCost = 0.0,
    this.fabricUsage = 0.0,
  });

  factory OrderItem.fromMap(Map<dynamic, dynamic> map) {
    // Try to get fabricUsed first, then fall back to fabricUsage
    final fabricUsedValue = Order._parseDouble(map['fabricUsed']);
    final fabricUsageValue = fabricUsedValue != 0.0 ? fabricUsedValue : Order._parseDouble(map['fabricUsage']);

    return OrderItem(
      id: map['id']?.toString() ?? '',
      orderId: map['orderId']?.toString() ?? '',
      service: map['service']?.toString() ?? map['serviceName']?.toString() ?? '',
      price: Order._parseDouble(map['price']),
      quantity: int.tryParse(map['quantity']?.toString() ?? '1') ?? 1,
      fabricId: map['fabricId']?.toString() ?? map['fabricCode']?.toString(),
      fabricName: map['fabricName']?.toString(),
      fabricUsed: fabricUsageValue,
      cost: Order._parseDouble(map['cost']),
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
      // 新 POS 欄位
      'serviceName': serviceName,
      'fabricCode': fabricCode,
      'fabricCost': fabricCost,
      'fabricUsage': fabricUsage,
    };
  }
}
