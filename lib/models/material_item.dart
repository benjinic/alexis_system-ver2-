class MaterialItem {
  final String id;
  final String name;
  final double costPerUnit;
  final String unit;
  final double stock;
  final double reorderLevel;
  final String? imageUrl;
  // 1. 新增分類欄位
  final String category; 

  MaterialItem({
    required this.id,
    required this.name,
    required this.costPerUnit,
    required this.unit,
    required this.stock,
    required this.reorderLevel,
    this.imageUrl,
    // 預設為 'Other' 以相容舊資料
    this.category = 'Other', 
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
      // 讀取分類，若無則設為 Other
      category: map['category'] ?? 'Other', 
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
      // 寫入分類
      'category': category, 
    };
  }
}
