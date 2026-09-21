// lib/components/bespoke_cart_mapping_dialog.dart
//
// 從 Bespoke 匯入時，將訂製訂單嘅每件衣服對應成 POS 購物車項目。
// 每列：揀 POS 服務、確認布料（自動由庫存對返）、用量、單價。
// 確認後回傳 OrderItem 列表，由 POS 頁加入購物車。

import 'package:flutter/material.dart';

import '../models/material_item.dart';
import '../models/order.dart';
import '../models/service_item.dart';
import '../services/bespoke_cart_mapper.dart';
import '../services/bespoke_import_service.dart';

const Map<String, String> _garmentZh = {
  'jacket': '外套',
  'trousers': '褲子',
  'vest': '背心',
  'shirt': '恤衫',
};

class BespokeCartMappingDialog extends StatefulWidget {
  const BespokeCartMappingDialog({
    super.key,
    required this.order,
    required this.services,
    required this.inventory,
  });

  final BespokeOrderSummary order;
  final List<ServiceItem> services;
  final List<MaterialItem> inventory;

  @override
  State<BespokeCartMappingDialog> createState() =>
      _BespokeCartMappingDialogState();
}

class _Row {
  _Row({
    required this.type,
    required this.fabricText,
    required this.fabric,
    required this.service,
  }) : usageCtrl = TextEditingController(),
       priceCtrl = TextEditingController();

  final String type;
  final String fabricText; // Bespoke 記低嘅布料文字
  final MaterialItem? fabric; // 由庫存對返嘅布料，對唔到為 null
  ServiceItem? service;
  bool include = true;
  bool priceEdited = false;
  final TextEditingController usageCtrl;
  final TextEditingController priceCtrl;

  void dispose() {
    usageCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _BespokeCartMappingDialogState extends State<BespokeCartMappingDialog> {
  late final List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.order.items.map((item) {
      final type = (item['type'] ?? '').toString();
      final fabricText = (item['fabric'] ?? '').toString();
      final row = _Row(
        type: type,
        fabricText: fabricText,
        fabric: findFabric(
          (item['fabricId'] ?? '').toString(),
          fabricText,
          widget.inventory,
        ),
        service: guessService(type, widget.services),
      );
      _applyServiceDefaults(row);
      return row;
    }).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// 揀咗服務就帶入預設用量同服務價；單價只喺職員未手動改過時先跟住變。
  void _applyServiceDefaults(_Row row) {
    final s = row.service;
    if (s == null) return;
    row.usageCtrl.text = _num(s.defaultFabricUsage);
    if (!row.priceEdited) row.priceCtrl.text = _num(s.price);
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  double get _cartTotal {
    var sum = 0.0;
    for (final r in _rows) {
      if (r.include && r.service != null) {
        sum += double.tryParse(r.priceCtrl.text.trim()) ?? r.service!.price;
      }
    }
    return sum;
  }

  void _confirm() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final items = <OrderItem>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final service = r.service;
      if (!r.include || service == null) continue;
      items.add(
        buildCartItem(
          id: '${stamp + i}',
          service: service,
          fabric: r.fabric,
          fabricUsage: double.tryParse(r.usageCtrl.text.trim()) ?? 0,
          unitPrice: double.tryParse(r.priceCtrl.text.trim()),
        ),
      );
    }
    Navigator.pop(context, items);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = widget.order.totalPrice;
    return AlertDialog(
      title: const Text('對應購物車項目'),
      content: SizedBox(
        width: 560,
        child: widget.services.isEmpty
            ? const Text('POS 沒有服務項目，請先在設定加入服務項目。')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '為「${widget.order.clientName}」的每件衣服選擇對應的 POS 服務。'
                      '單價預設為服務價，可自行修改。',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    for (final r in _rows) _buildRow(r, cs),
                    const Divider(),
                    Text(
                      '購物車合計 ${_num(_cartTotal)}'
                      '${total > 0 ? '　｜　訂製總價 ${_num(total)}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (total > 0 && (_cartTotal - total).abs() > 0.5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '與訂製總價不同，可修改單價或在購物車調整。',
                          style: TextStyle(color: cs.tertiary, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('略過（自己加）'),
        ),
        FilledButton(
          onPressed: widget.services.isEmpty ? null : _confirm,
          child: const Text('加入購物車'),
        ),
      ],
    );
  }

  Widget _buildRow(_Row r, ColorScheme cs) {
    final fabricLine = r.fabric != null
        ? '布料：${r.fabric!.name}（庫存，成本 ${_num(r.fabric!.costPerUnit)}/${r.fabric!.unit}）'
        : r.fabricText.isEmpty
        ? '布料：未填寫'
        : '布料：${r.fabricText}（庫存找不到，成本以 0 計，可在購物車編輯）';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: r.include,
                onChanged: (v) => setState(() => r.include = v ?? true),
              ),
              Text(
                _garmentZh[r.type] ?? r.type,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ServiceItem>(
                  isExpanded: true,
                  initialValue: r.service,
                  decoration: const InputDecoration(
                    labelText: 'POS 服務',
                    isDense: true,
                  ),
                  hint: const Text('請選擇對應的服務'),
                  items: widget.services
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: r.include
                      ? (s) => setState(() {
                          r.service = s;
                          _applyServiceDefaults(r);
                        })
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  fabricLine,
                  style: TextStyle(
                    fontSize: 12,
                    color: r.fabric == null && r.fabricText.isNotEmpty
                        ? cs.tertiary
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: r.usageCtrl,
                        enabled: r.include,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '布料用量 (m)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: r.priceCtrl,
                        enabled: r.include,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '單價',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() => r.priceEdited = true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
