class Customer {
  final String id;
  final String name;
  final String email;
  final String phone;
  final int orders;
  final double totalSpent; // 1. 修改：改為 double 以符合資料庫的數字格式
  final DateTime? createdAt;
  final DateTime? nextFollowUp;
  final Map<String, String>
  measurements; // 新增：體型數據 (例如: {'Shoulder': '45', 'Chest': '100'})

  Customer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.orders,
    required this.totalSpent,
    this.createdAt,
    this.nextFollowUp,
    this.measurements = const {}, // 預設為空
  });

  String get tier {
    if (totalSpent >= 50000) return 'vip';
    if (totalSpent >= 10000) return 'regular';
    return 'new';
  }

  // 2. 增加：安全的轉換邏輯
  factory Customer.fromFirestore(String id, Map<String, dynamic> data) {
    double parsedTotalSpent = 0.0;

    try {
      final value = data['totalSpent'];
      if (value is num) {
        // 如果是數字 (int 或 double)，直接轉換
        parsedTotalSpent = value.toDouble();
      } else if (value is String) {
        // 如果是文字，嘗試解析
        parsedTotalSpent = double.tryParse(value) ?? 0.0;
      }
    } catch (e) {
      parsedTotalSpent = 0.0;
    }

    // 3. 檢查是否為 NaN (防止計算錯誤導致的非數值)
    if (parsedTotalSpent.isNaN) {
      parsedTotalSpent = 0.0;
    }

    // 處理 measurements 欄位
    Map<String, String> parsedMeasurements = {};
    if (data['measurements'] != null) {
      // 確保將所有值轉為 String，避免型別錯誤
      final map = data['measurements'] as Map<dynamic, dynamic>;
      map.forEach((key, value) {
        parsedMeasurements[key.toString()] = value.toString();
      });
    }

    DateTime? nextFollowUp;
    try {
      if (data['nextFollowUp'] != null) {
        nextFollowUp = (data['nextFollowUp'] as dynamic).toDate();
      }
    } catch (_) {}

    return Customer(
      id: id,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      orders: (data['orders'] is int) ? data['orders'] : 0,
      totalSpent: parsedTotalSpent, // 使用安全轉換後的值
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
      nextFollowUp: nextFollowUp,
      measurements: parsedMeasurements,
    );
  }

  // 兼容舊方法
  factory Customer.fromMap(String id, Map<dynamic, dynamic> map) {
    return Customer.fromFirestore(id, Map<String, dynamic>.from(map));
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'orders': orders,
      'totalSpent': totalSpent,
      'createdAt': createdAt,
      'measurements': measurements,
      if (nextFollowUp != null) 'nextFollowUp': nextFollowUp,
    };
  }

  Map<String, dynamic> toJson() => toFirestore();

  Customer copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    int? orders,
    double? totalSpent,
    DateTime? createdAt,
    DateTime? nextFollowUp,
    Map<String, String>? measurements,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      orders: orders ?? this.orders,
      totalSpent: totalSpent ?? this.totalSpent,
      createdAt: createdAt ?? this.createdAt,
      nextFollowUp: nextFollowUp ?? this.nextFollowUp,
      measurements: measurements ?? this.measurements,
    );
  }
}
