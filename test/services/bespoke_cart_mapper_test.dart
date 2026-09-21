import 'package:flutter_test/flutter_test.dart';
import 'package:alexis_system/models/material_item.dart';
import 'package:alexis_system/models/service_item.dart';
import 'package:alexis_system/services/bespoke_cart_mapper.dart';

ServiceItem svc(String name, double price, {double usage = 0}) => ServiceItem(
  id: name,
  name: name,
  price: price,
  defaultFabricUsage: usage,
);

MaterialItem fabric(String id, String name, double cost) => MaterialItem(
  id: id,
  name: name,
  costPerUnit: cost,
  unit: 'm',
  stock: 10,
  reorderLevel: 1,
);

void main() {
  final services = [svc('Suit', 5000, usage: 3), svc('Shirt', 800, usage: 2), svc('Pants', 1200, usage: 1.5)];

  group('guessService', () {
    test('maps garment types to matching POS services', () {
      expect(guessService('shirt', services)?.name, 'Shirt');
      expect(guessService('trousers', services)?.name, 'Pants');
    });

    test('jacket falls back to Suit when there is no jacket service', () {
      expect(guessService('jacket', services)?.name, 'Suit');
    });

    test('prefers an explicit jacket service and matches Chinese names', () {
      final list = [svc('西裝', 5000), svc('外套', 3000), svc('背心', 900)];
      expect(guessService('jacket', list)?.name, '外套');
      expect(guessService('vest', list)?.name, '背心');
    });

    test('returns null when nothing matches', () {
      expect(guessService('vest', services), isNull);
      expect(guessService('unknown', services), isNull);
    });
  });

  group('findFabric', () {
    final inventory = [fabric('a1', 'WHITE PIMA', 100), fabric('b2', 'Navy Wool', 250)];

    test('matches by id first', () {
      expect(findFabric('b2', 'something else', inventory)?.name, 'Navy Wool');
    });

    test('falls back to case-insensitive exact name', () {
      expect(findFabric('', ' white pima ', inventory)?.id, 'a1');
    });

    test('returns null for unknown id and name', () {
      expect(findFabric('zzz', 'nope', inventory), isNull);
      expect(findFabric('', '', inventory), isNull);
    });
  });

  group('buildCartItem', () {
    test('uses service price and computes fabric cost like the POS item dialog', () {
      final item = buildCartItem(
        id: '1',
        service: svc('Suit', 5000, usage: 3),
        fabric: fabric('a1', 'WHITE PIMA', 100),
        fabricUsage: 3,
      );
      expect(item.service, 'Suit');
      expect(item.price, 5000);
      expect(item.quantity, 1);
      expect(item.fabricId, 'a1');
      expect(item.fabricName, 'WHITE PIMA');
      expect(item.fabricUsed, 3);
      expect(item.cost, 300);
      expect(item.manualUnitPrice, isFalse);
      expect(item.sendToWorkshop, isTrue);
    });

    test('marks a different unit price as manual', () {
      final item = buildCartItem(
        id: '1',
        service: svc('Shirt', 800),
        fabricUsage: 2,
        unitPrice: 950,
      );
      expect(item.price, 950);
      expect(item.manualUnitPrice, isTrue);
    });

    test('without inventory fabric the cost is zero and fabric fields are empty', () {
      final item = buildCartItem(id: '1', service: svc('Pants', 1200), fabricUsage: 1.5);
      expect(item.cost, 0);
      expect(item.fabricId, isNull);
      expect(item.fabricName, isNull);
      expect(item.manualUnitPrice, isFalse);
    });

    test('negative usage or price is clamped to zero', () {
      final item = buildCartItem(
        id: '1',
        service: svc('Pants', 1200),
        fabric: fabric('a1', 'X', 100),
        fabricUsage: -2,
        unitPrice: -5,
      );
      expect(item.fabricUsed, 0);
      expect(item.cost, 0);
      expect(item.price, 0);
    });
  });
}
