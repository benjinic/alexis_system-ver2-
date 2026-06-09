import 'package:alexis_system/models/workshop_order.dart';
import 'package:alexis_system/models/workshop_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkshopOrder fabric status', () {
    test('defaults fabric status to false for old records', () {
      final order = WorkshopOrder.fromMap('workshop-1', {
        'orderId': '14039',
        'customer': 'Test Customer',
        'item': 'Suit',
        'status': WorkshopStatus.measuring.name,
        'priority': 'normal',
        'progress': 0,
      });

      expect(order.isFabricOrdered, isFalse);
    });

    test('reads and writes fabric ordered status', () {
      final order = WorkshopOrder.fromMap('workshop-1', {
        'orderId': '14039',
        'customer': 'Test Customer',
        'item': 'Suit',
        'status': WorkshopStatus.cutting.name,
        'priority': 'urgent',
        'progress': 25,
        'isFabricOrdered': true,
      });

      expect(order.isFabricOrdered, isTrue);
      expect(order.toJson()['isFabricOrdered'], isTrue);
      expect(order.copyWith(isFabricOrdered: false).isFabricOrdered, isFalse);
    });
  });
}
