// lib/services/bespoke_cart_mapper.dart
//
// 將 Bespoke 訂製訂單嘅單項（外套／褲子／背心／恤衫）對應成 POS 購物車項目。
// 純函數、冇 UI 依賴，方便測試。
//
// 對應規則只係「預設建議」：服務由職員喺畫面確認，價錢同用量都可以改。

import '../models/material_item.dart';
import '../models/order.dart';
import '../models/service_item.dart';

/// 訂製項目類型 -> POS 服務名稱關鍵字（細楷比對，靠前嘅優先）。
const Map<String, List<String>> _serviceKeywords = {
  'jacket': ['jacket', 'blazer', '外套', '西裝外套', '上衣', 'suit', '西裝'],
  'trousers': ['trouser', 'pants', '褲'],
  'vest': ['vest', 'waistcoat', '背心'],
  'shirt': ['shirt', '恤', '襯'],
};

/// 按訂製項目類型猜最可能嘅 POS 服務；搵唔到返回 null，由職員自己揀。
ServiceItem? guessService(String garmentType, List<ServiceItem> services) {
  final keywords = _serviceKeywords[garmentType] ?? const [];
  for (final keyword in keywords) {
    for (final service in services) {
      if (service.name.toLowerCase().contains(keyword)) return service;
    }
  }
  return null;
}

/// 由庫存搵返訂製項目用嘅布料：先用 fabricId，再用名稱（不分大細楷）完全相同。
MaterialItem? findFabric(
  String fabricId,
  String fabricName,
  List<MaterialItem> inventory,
) {
  if (fabricId.isNotEmpty) {
    for (final m in inventory) {
      if (m.id == fabricId) return m;
    }
  }
  final name = fabricName.trim().toLowerCase();
  if (name.isNotEmpty) {
    for (final m in inventory) {
      if (m.name.trim().toLowerCase() == name) return m;
    }
  }
  return null;
}

/// 組出購物車項目，計法同 POS 嘅 OrderItemDialog 一致：
/// 成本 = 用量 × 布料單位成本；單價同服務價唔同就標記為手動單價。
OrderItem buildCartItem({
  required String id,
  required ServiceItem service,
  MaterialItem? fabric,
  required double fabricUsage,
  double? unitPrice,
  bool sendToWorkshop = true,
}) {
  final price = unitPrice ?? service.price;
  final usage = fabricUsage < 0 ? 0.0 : fabricUsage;
  return OrderItem(
    id: id,
    service: service.name,
    price: price < 0 ? 0 : price,
    quantity: 1,
    fabricId: fabric?.id,
    fabricName: fabric?.name,
    fabricUsed: usage,
    cost: fabric == null ? 0 : usage * fabric.costPerUnit,
    manualUnitPrice: (price - service.price).abs() > 0.001,
    sendToWorkshop: sendToWorkshop,
  );
}
