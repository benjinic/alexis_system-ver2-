import 'package:flutter_test/flutter_test.dart';
import 'package:alexis_system/services/bespoke_import_service.dart';

void main() {
  BespokeOrderSummary summary({
    String phone = '91234567',
    List<Map<String, dynamic>> items = const [],
  }) {
    return BespokeOrderSummary(
      id: 'b1',
      clientName: '陳大文',
      phone: phone,
      date: null,
      dueDate: null,
      deposit: 500,
      totalPrice: 8000,
      items: items,
    );
  }

  test('notes text lists phone, fabric and design with Chinese labels', () {
    final text = summary(
      items: [
        {
          'type': 'jacket',
          'fabric': 'WHITE PIMA',
          'fabricSwatch': 'BN0033',
          'design': {'fit': '貼身', 'construction': '全襯'},
          'otherNotes': '袖長略短',
        },
        {
          'type': 'trousers',
          'design': {'hem': '直腳'},
        },
      ],
    ).toNotesText();

    expect(text, contains('[Bespoke 訂製]'));
    expect(text, contains('電話：91234567'));
    expect(text, contains('外套｜布料：WHITE PIMA（樣板：BN0033）'));
    expect(text, contains('剪裁：貼身'));
    expect(text, contains('做工：全襯'));
    expect(text, contains('備注：袖長略短'));
    expect(text, contains('褲子｜褲腳：直腳'));
  });

  test('unknown design keys fall back to the raw key and empty phone is omitted', () {
    final text = summary(
      phone: '',
      items: [
        {
          'type': 'jacket',
          'design': {'newField': 'X', 'fit': ''},
        },
      ],
    ).toNotesText();

    expect(text, isNot(contains('電話')));
    expect(text, contains('newField：X'));
    expect(text, isNot(contains('剪裁')));
  });

  test('garment labels join item types', () {
    final s = summary(
      items: [
        {'type': 'jacket'},
        {'type': 'shirt'},
      ],
    );
    expect(s.garmentLabels, '外套 · 恤衫');
  });
}
