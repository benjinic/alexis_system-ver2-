// lib/services/bespoke_cart_mapper.dart
//
// 從 Bespoke 匯入時，將訂製訂單嘅單項（外套／褲子／背心／恤衫）
// 轉成 POS「新增項目」視窗嘅預填值。純函數、冇 UI 依賴，方便測試。
//
// 呢度只做「預填建議」，唔計價、唔算成本：
// 價錢、成本、用量嘅計算全部由 OrderItemDialog 負責，POS 改計價邏輯時會自動跟住變。

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

const Map<String, String> _garmentZh = {
  'jacket': '外套',
  'trousers': '褲子',
  'vest': '背心',
  'shirt': '恤衫',
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

/// 組出傳畀 OrderItemDialog(existingItem:, asNewItem: true) 嘅預填項目。
///
/// - 服務：猜到就預填，猜唔到 service 留空，職員喺視窗自己揀。
/// - 布料：只喺猜到服務、服務預設用量 > 0 而且庫存搵到布料時預填
///   （同 OrderItemDialog 一致：預設用量 0 嘅服務唔用布料）。
/// - 單價：預設為服務價，之後喺視窗改；未揀服務時為 0。
/// - 數量 1、預設送工房。
OrderItem buildPrefillItem({
  required String id,
  required Map<String, dynamic> bespokeItem,
  required List<ServiceItem> services,
  required List<MaterialItem> inventory,
}) {
  final type = (bespokeItem['type'] ?? '').toString();
  final service = guessService(type, services);
  final usesFabric = service != null && service.defaultFabricUsage > 0;
  final fabric = usesFabric
      ? findFabric(
          (bespokeItem['fabricId'] ?? '').toString(),
          (bespokeItem['fabric'] ?? '').toString(),
          inventory,
        )
      : null;

  return OrderItem(
    id: id,
    service: service?.name ?? '',
    price: service?.price ?? 0,
    quantity: 1,
    fabricId: fabric?.id,
    fabricName: fabric?.name,
    fabricUsed: usesFabric ? service.defaultFabricUsage : 0,
  );
}

/// 視窗頂部嘅提示文字，等職員知道而家處理緊訂製訂單嘅邊一件。
String describeBespokeItem(
  Map<String, dynamic> bespokeItem, {
  required int index,
  required int total,
  required List<MaterialItem> inventory,
}) {
  final type = (bespokeItem['type'] ?? '').toString();
  final fabricText = (bespokeItem['fabric'] ?? '').toString();
  final swatch = (bespokeItem['fabricSwatch'] ?? '').toString();
  final matched = findFabric(
    (bespokeItem['fabricId'] ?? '').toString(),
    fabricText,
    inventory,
  );

  final lines = <String>[
    '匯入自 Bespoke：${_garmentZh[type] ?? type}（${index + 1}/$total）',
  ];
  if (fabricText.isEmpty) {
    lines.add('布料：未填寫');
  } else {
    final note = matched != null ? '庫存已對應' : '庫存找不到，請自行選擇';
    lines.add('布料：$fabricText${swatch.isEmpty ? '' : '（樣板：$swatch）'}　$note');
  }
  return lines.join('\n');
}
