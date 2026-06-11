class FabricOrderStatusSync {
  const FabricOrderStatusSync._();

  static bool itemMapRequiresFabric(Map<dynamic, dynamic> item) {
    final fabricId = item['fabricId']?.toString().trim() ?? '';
    final fabricCode = item['fabricCode']?.toString().trim() ?? '';
    final fabricName = item['fabricName']?.toString().trim() ?? '';
    final fabricUsed = _parseDouble(item['fabricUsed']);
    final fabricUsage = _parseDouble(item['fabricUsage']);

    return fabricId.isNotEmpty ||
        fabricCode.isNotEmpty ||
        fabricName.isNotEmpty ||
        fabricUsed > 0 ||
        fabricUsage > 0;
  }

  static bool areAllRequiredItemsOrdered(
    Iterable<Map<dynamic, dynamic>> itemMaps,
  ) {
    var hasRequiredItems = false;

    for (final item in itemMaps) {
      if (!itemMapRequiresFabric(item)) {
        continue;
      }

      hasRequiredItems = true;
      if (item['isFabricOrdered'] != true) {
        return false;
      }
    }

    return hasRequiredItems;
  }

  static double _parseDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}
