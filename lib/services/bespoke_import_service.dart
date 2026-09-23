// lib/services/bespoke_import_service.dart
//
// 由 Alexis Bespoke App 建立嘅訂製訂單（collection: bespoke_orders），
// 喺 POS 匯入並用 POS 最新單號建立正式訂單。
//
// 流程：POS 列出未匯入嘅訂製訂單 → 揀一張預填客人資料同備注 →
// 職員照 POS 原有流程加服務項目並儲存（單號由 allocateOrderId 分配）→
// 儲存成功後呢度回寫 posOrderId / posOrderNo，避免重複匯入。
//
// 只讀取 bespoke_orders，只回寫 posOrderId、posOrderNo、importedAt 三個欄位。

import 'package:cloud_firestore/cloud_firestore.dart';

class BespokeImportException implements Exception {
  BespokeImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 訂製訂單嘅精簡資料。
class BespokeOrderSummary {
  BespokeOrderSummary({
    required this.id,
    required this.clientName,
    required this.phone,
    this.customerId = '',
    required this.date,
    required this.dueDate,
    required this.deposit,
    required this.totalPrice,
    required this.items,
  });

  final String id;
  final String clientName;
  final String phone;

  /// Bespoke 建單時由客人名單揀選嘅 customers 文件 ID；手動輸入時為空。
  final String customerId;
  final DateTime? date;
  final DateTime? dueDate;
  final double deposit;
  final double totalPrice;
  final List<Map<String, dynamic>> items;

  factory BespokeOrderSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    final rawItems = m['items'];
    return BespokeOrderSummary(
      id: doc.id,
      clientName: (m['clientName'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      customerId: (m['customerId'] ?? '').toString(),
      date: _toDate(m['date']),
      dueDate: _toDate(m['dueDate']),
      deposit: _toDouble(m['deposit']),
      totalPrice: _toDouble(m['totalPrice']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [],
    );
  }

  /// 衣服類型簡述，例如「外套 · 褲子」。
  String get garmentLabels => items
      .map((i) => _garmentZh[i['type']] ?? (i['type'] ?? '').toString())
      .join(' · ');

  /// 帶入 POS 備注嘅文字：電話、各項目布料同設計規格。
  String toNotesText() {
    final lines = <String>['[Bespoke 訂製]'];
    if (phone.isNotEmpty) lines.add('電話：$phone');
    final typeTotals = <String, int>{};
    for (final item in items) {
      final ty = (item['type'] ?? '').toString();
      typeTotals[ty] = (typeTotals[ty] ?? 0) + 1;
    }
    final typeSeen = <String, int>{};
    for (final item in items) {
      final type = (item['type'] ?? '').toString();
      final seq = typeSeen[type] = (typeSeen[type] ?? 0) + 1;
      // 同類型多件（例如兩件外套）加序號，備注入面先分得清邊件係邊件。
      final buf = StringBuffer(
        '${_garmentZh[type] ?? type}${(typeTotals[type] ?? 0) > 1 ? ' $seq' : ''}',
      );
      final fabric = (item['fabric'] ?? '').toString();
      final swatch = (item['fabricSwatch'] ?? '').toString();
      if (fabric.isNotEmpty) {
        buf.write('｜布料：$fabric');
        if (swatch.isNotEmpty) buf.write('（樣板：$swatch）');
      }
      final design = item['design'];
      if (design is Map) {
        final labels = _designZh[type] ?? const {};
        final parts = design.entries
            .where((e) => e.value != null && e.value.toString().isNotEmpty)
            .map((e) => '${labels[e.key] ?? e.key}：${e.value}');
        if (parts.isNotEmpty) buf.write('｜${parts.join('、')}');
      }
      final other = (item['otherNotes'] ?? '').toString();
      if (other.isNotEmpty) buf.write('｜備注：$other');
      lines.add(buf.toString());
    }
    return lines.join('\n');
  }
}

class BespokeImportService {
  BespokeImportService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('bespoke_orders');

  /// 未匯入嘅訂製訂單（新到舊）。新訂單冇 posOrderId 欄位，所以喺畫面端過濾。
  Future<List<BespokeOrderSummary>> fetchPending({int limit = 100}) async {
    final snap = await _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .where((d) => (d.data()['posOrderId'] ?? '').toString().isEmpty)
        .map(BespokeOrderSummary.fromDoc)
        .toList();
  }

  /// POS 訂單建立成功後回寫。用 transaction 確保同一張訂製訂單唔會匯入兩次。
  Future<void> markImported(
    String bespokeOrderId, {
    required String posOrderId,
  }) async {
    final ref = _col.doc(bespokeOrderId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        throw BespokeImportException('找不到訂製訂單，可能已被刪除');
      }
      final existing = (doc.data()?['posOrderId'] ?? '').toString();
      if (existing.isNotEmpty) {
        throw BespokeImportException('此訂製訂單已匯入為 POS 訂單 $existing');
      }
      tx.update(ref, {
        'posOrderId': posOrderId,
        'posOrderNo': posOrderId, // POS 單號即訂單文件 ID
        'importedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

DateTime? _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

// 以下標籤同 Alexis Bespoke 嘅 tailor_design_options.dart 對應，
// 改款式選項時要兩邊同步；冇對應時會直接顯示欄位 key，唔會出錯。
const Map<String, String> _garmentZh = {
  'jacket': '外套',
  'trousers': '褲子',
  'vest': '背心',
  'shirt': '恤衫',
};

const Map<String, Map<String, String>> _designZh = {
  'jacket': {
    'fit': '剪裁',
    'construction': '做工',
    'lining': '里布',
    'sleeveStyle': '袖款',
    'pickStitch': '珠邊',
    'lapelStitch': '內襟珠線',
    'cuffVent': '袖口鈕',
    'cuffButtonStyle': '袖口鈕式',
    'waistPocket': '腰袋',
    'backVent': '後叉',
  },
  'trousers': {
    'pleatsCount': '褶',
    'pleatPosition': '摺位',
    'waistband': '褲頭',
    'waistLoop': '腰帶',
    'pocket': '袋',
    'backPocket': '後袋',
    'pocketFlap': '袋蓋',
    'hem': '褲腳',
  },
  'vest': {'style': '款式', 'back': '後背'},
  'shirt': {
    'collar': '領型',
    'placket': '門襟',
    'back': '背部款式',
    'cuff': '袖口款式',
    'fit': '版型',
  },
};
