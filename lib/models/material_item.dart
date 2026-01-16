class MaterialItem {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double costPerUnit;
  
  // === 新增欄位 ===
  final String? imageUrl;      // 圖片網址 (可選)
  final String description;    // 布料描述 (例如: "100% Cotton, 150cm width")
  final double stockLength;    // 庫存布料長度 (例如: 50.0 代表 50 米)
  final String code;           // 布料代碼 (用於新 POS 系統，預設為 id)

  MaterialItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    this.costPerUnit = 0.0,
    this.imageUrl,
    this.description = '',
    this.stockLength = 0.0,
    String? code,
  }) : code = code ?? id;

  factory MaterialItem.fromMap(String id, Map<dynamic, dynamic> map) {
    return MaterialItem(
      id: id,
      name: map['name'] ?? '',
      category: map['category'] ?? 'Fabric',
      unit: map['unit'] ?? 'meters',
      costPerUnit: (map['costPerUnit'] ?? 0).toDouble(),
      // 讀取新增的欄位
      imageUrl: map['imageUrl'],
      description: map['description'] ?? '',
      stockLength: (map['stockLength'] ?? 0).toDouble(),
      code: map['code'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'unit': unit,
      'costPerUnit': costPerUnit,
      // 寫入新增的欄位 (移除了 quantity, status, reorderPoint)
      'imageUrl': imageUrl,
      'description': description,
      'stockLength': stockLength,
      'code': code,
    };
  }

  MaterialItem copyWith({
    String? id,
    String? name,
    String? category,
    String? unit,
    double? costPerUnit,
    String? imageUrl,
    String? description,
    double? stockLength,
    String? code,
  }) {
    return MaterialItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      costPerUnit: costPerUnit ?? this.costPerUnit,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      stockLength: stockLength ?? this.stockLength,
      code: code ?? this.code,
    );
  }
}
