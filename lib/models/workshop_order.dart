import 'package:cloud_firestore/cloud_firestore.dart';
import 'workshop_status.dart';

class WorkshopOrder {
  final String id; // Firestore 文件 ID (自動生成)
  final String orderId; // 新增：訂單編號 (例如 14039)
  final String customer;
  final String item;
  final WorkshopStatus status;
  final String priority;
  final DateTime dueDate;
  final int progress;
  final String notes;
  final bool isFabricOrdered;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkshopOrder({
    required this.id,
    this.orderId = '', // 預設為空，相容舊資料
    required this.customer,
    required this.item,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.progress,
    this.notes = '',
    this.isFabricOrdered = false,
    this.createdAt,
    this.updatedAt,
  });

  // === 輔助函式：處理多種時間格式 ===
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  // Convert from Firebase DataSnapshot to object
  factory WorkshopOrder.fromMap(String id, Map<dynamic, dynamic> map) {
    return WorkshopOrder(
      id: id,
      orderId: map['orderId']?.toString() ?? '',
      customer: map['customer'] ?? '',
      item: map['item'] ?? '',
      status: map['status'] != null
          ? WorkshopStatus.values.firstWhere(
              (e) => e.name == map['status'],
              orElse: () => WorkshopStatus.measuring,
            )
          : WorkshopStatus.measuring,
      priority: map['priority'] ?? 'normal',
      dueDate: _parseDate(map['dueDate']),
      progress: map['progress']?.toInt() ?? 0,
      notes: map['notes'] ?? '',
      isFabricOrdered: map['isFabricOrdered'] == true,
      createdAt: _parseNullableDate(map['createdAt']),
      updatedAt: _parseNullableDate(map['updatedAt']),
    );
  }

  // Convert object to Map for writing to database
  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId, // 寫入資料庫
      'customer': customer,
      'item': item,
      'status': status.name,
      'priority': priority,
      'dueDate': dueDate.millisecondsSinceEpoch,
      'progress': progress,
      'notes': notes,
      'isFabricOrdered': isFabricOrdered,
      'createdAt':
          createdAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'updatedAt':
          updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    };
  }

  // === 自動判斷項目類型的 Getter ===
  // 邏輯：根據 item 名稱判斷項目類型
  String get itemType {
    final name = item.toLowerCase();
    if (name.contains('suit')) return 'SUIT';
    if (name.contains('jacket') || name.contains('blazer')) return 'JACKET';
    if (name.contains('trouser') || name.contains('pant')) return 'TROUSER';
    if (name.contains('shirt')) return 'SHIRT';
    if (name.contains('vest') || name.contains('waistcoat')) return 'VEST';
    if (name.contains('coat') || name.contains('overcoat')) return 'COAT';
    return 'OTHER';
  }

  // === 自動清除尾部 ID 的顯示名稱 ===
  // 範例：輸入 "VBC JACKET 2X5z..." -> 輸出 "VBC JACKET"
  String get displayName {
    // Regex 解釋：
    // \s+           : 匹配前面的空格
    // [a-zA-Z0-9]{20} : 匹配剛好 20 個英數字 (Firestore ID 的標準長度)
    // $             : 匹配字串結尾
    final regex = RegExp(r'\s+[a-zA-Z0-9]{20}$');

    // 如果字串結尾符合 ID 格式，就把它換成空字串
    return item.replaceAll(regex, '').trim();
  }

  // Create a copy with updated fields
  WorkshopOrder copyWith({
    String? id,
    String? orderId, // 新增參數
    String? customer,
    String? item,
    WorkshopStatus? status,
    String? priority,
    DateTime? dueDate,
    int? progress,
    String? notes,
    bool? isFabricOrdered,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkshopOrder(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      customer: customer ?? this.customer,
      item: item ?? this.item,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      progress: progress ?? this.progress,
      notes: notes ?? this.notes,
      isFabricOrdered: isFabricOrdered ?? this.isFabricOrdered,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
