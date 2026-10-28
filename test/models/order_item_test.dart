import 'package:alexis_system/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderItem docId', () {
    final item = OrderItem(
      docId: 'abc123',
      id: '1589414400000',
      service: 'SHIRT',
      price: 450,
      quantity: 1,
    );

    test('is kept through copyWith so edits can update the same document', () {
      expect(item.copyWith(price: 500).docId, 'abc123');
    });

    test('is not written to Firestore (rules reject unknown fields)', () {
      expect(item.toJson().containsKey('docId'), isFalse);
    });

    test('is empty for items read from map data', () {
      expect(OrderItem.fromMap(item.toJson()).docId, isNull);
    });
  });
}
