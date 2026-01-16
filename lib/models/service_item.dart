class ServiceItem {
  final String id;
  final String name;
  final double price;
  final double defaultFabricUsage;
  final int durationDays; // Manufacturing duration in days
  final double markupMultiplier; // e.g. Suit: 3.0, Shirt: 2.5
  final bool allowModifiers; // Whether to allow modifier selections

  ServiceItem({
    required this.id,
    required this.name,
    required this.price,
    required this.defaultFabricUsage,
    this.durationDays = 7, // Default 7 days
    this.markupMultiplier = 2.5, // Default value
    this.allowModifiers = false,
  });

  // Convert from Firestore map
  factory ServiceItem.fromMap(Map<String, dynamic> map) {
    return ServiceItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      defaultFabricUsage: (map['defaultFabricUsage'] ?? 0.0).toDouble(),
      durationDays: (map['durationDays'] ?? 7).toInt(),
      markupMultiplier: (map['markupMultiplier'] ?? 2.5).toDouble(),
      allowModifiers: map['allowModifiers'] ?? false,
    );
  }

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'defaultFabricUsage': defaultFabricUsage,
      'durationDays': durationDays,
      'markupMultiplier': markupMultiplier,
      'allowModifiers': allowModifiers,
    };
  }

  // Create a copy with modifications
  ServiceItem copyWith({
    String? id,
    String? name,
    double? price,
    double? defaultFabricUsage,
    int? durationDays,
    double? markupMultiplier,
    bool? allowModifiers,
  }) {
    return ServiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      defaultFabricUsage: defaultFabricUsage ?? this.defaultFabricUsage,
      durationDays: durationDays ?? this.durationDays,
      markupMultiplier: markupMultiplier ?? this.markupMultiplier,
      allowModifiers: allowModifiers ?? this.allowModifiers,
    );
  }
}
