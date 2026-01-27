class MaterialItem {
  final String id;
  final String name;
  final double costPerUnit; // 成本價
  final String unit;
  final double stock;
  final double reorderLevel;
  final String? imageUrl;
  final String category;
  
  // === 1. 新增欄位 ===
  final double retailPrice; // 零售價
  final bool isOnline;      // 是否上架 (Online Status)

  MaterialItem({
    required this.id,
    required this.name,
    required this.costPerUnit,
    required this.unit,
    required this.stock,
    required this.reorderLevel,
    this.imageUrl,
    this.category = 'Other',
    // === 2. 初始化預設值 ===
    this.retailPrice = 0.0,
    this.isOnline = false, 
  });

  factory MaterialItem.fromMap(String id, Map<dynamic, dynamic> map) {
    return MaterialItem(
      id: id,
      name: map['name'] ?? '',
      costPerUnit: (map['costPerUnit'] ?? 0).toDouble(),
      unit: map['unit'] ?? 'm',
      stock: (map['stock'] ?? 0).toDouble(),
      reorderLevel: (map['reorderLevel'] ?? 0).toDouble(),
      imageUrl: map['imageUrl'],
      category: map['category'] ?? 'Other',
      // === 3. 讀取新欄位 ===
      retailPrice: (map['retailPrice'] ?? 0).toDouble(),
      isOnline: map['isOnline'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'costPerUnit': costPerUnit,
      'unit': unit,
      'stock': stock,
      'reorderLevel': reorderLevel,
      'imageUrl': imageUrl,
      'category': category,
      // === 4. 寫入新欄位 ===
      'retailPrice': retailPrice,
      'isOnline': isOnline,
    };
  }
}