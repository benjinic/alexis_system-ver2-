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

  group('buildPrefillItem', () {
    final inventory = [fabric('a1', 'WHITE PIMA', 100)];

    test('prefills service, price, default usage and inventory fabric', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'jacket', 'fabricId': 'a1', 'fabric': 'WHITE PIMA'},
        services: services,
        inventory: inventory,
      );
      expect(item.service, 'Suit');
      expect(item.price, 5000);
      expect(item.quantity, 1);
      expect(item.fabricId, 'a1');
      expect(item.fabricName, 'WHITE PIMA');
      expect(item.fabricUsed, 3);
      expect(item.sendToWorkshop, isTrue);
    });

    test('does not compute cost or mark manual price (the POS dialog owns pricing)', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'jacket', 'fabricId': 'a1'},
        services: services,
        inventory: inventory,
      );
      expect(item.cost, 0);
      expect(item.manualUnitPrice, isFalse);
    });

    test('falls back to fabric name when fabricId is missing', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'shirt', 'fabric': ' white pima '},
        services: services,
        inventory: inventory,
      );
      expect(item.service, 'Shirt');
      expect(item.fabricId, 'a1');
    });

    test('leaves the service empty when nothing matches, and skips fabric', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'vest', 'fabricId': 'a1', 'fabric': 'WHITE PIMA'},
        services: services,
        inventory: inventory,
      );
      expect(item.service, '');
      expect(item.price, 0);
      expect(item.fabricId, isNull);
      expect(item.fabricUsed, 0);
    });

    test('a service with zero default fabric usage gets no fabric, like the POS dialog', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'trousers', 'fabricId': 'a1'},
        services: [svc('Pants', 1200)], // defaultFabricUsage = 0
        inventory: inventory,
      );
      expect(item.service, 'Pants');
      expect(item.fabricId, isNull);
      expect(item.fabricUsed, 0);
    });

    test('unknown fabric leaves fabric fields empty but keeps the service', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'jacket', 'fabricId': 'zzz', 'fabric': 'Unknown'},
        services: services,
        inventory: inventory,
      );
      expect(item.service, 'Suit');
      expect(item.fabricId, isNull);
      expect(item.fabricName, isNull);
    });
  });

  group('resolveChosenService', () {
    test('matches by serviceId first', () {
      final s = resolveChosenService({'serviceId': 'Shirt', 'serviceName': 'Suit'}, services);
      expect(s?.name, 'Shirt');
    });

    test('falls back to serviceName when id is missing or unmatched', () {
      expect(resolveChosenService({'serviceName': 'Pants'}, services)?.name, 'Pants');
      expect(resolveChosenService({'serviceId': 'zzz', 'serviceName': 'Pants'}, services)?.name,
          'Pants');
    });

    test('returns null when neither is set or matched', () {
      expect(resolveChosenService({}, services), isNull);
      expect(resolveChosenService({'serviceName': 'Unknown'}, services), isNull);
    });
  });

  group('buildPrefillItem honours a service chosen in Bespoke', () {
    final inventory = [fabric('a1', 'WHITE PIMA', 100)];

    test('uses the chosen service and its price over the guessed one', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {
          'type': 'jacket', // would normally guess Suit
          'serviceId': 'Shirt',
          'fabricId': 'a1',
        },
        services: services,
        inventory: inventory,
      );
      expect(item.service, 'Shirt');
      expect(item.price, 800);
      expect(item.fabricUsed, 2); // Shirt's default usage
    });

    test('uses the Bespoke-recorded fabric usage over the service default', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {
          'type': 'jacket',
          'serviceId': 'Suit',
          'fabricId': 'a1',
          'fabricUsage': 4.5,
        },
        services: services,
        inventory: inventory,
      );
      expect(item.fabricUsed, 4.5);
    });

    test('a zero or missing Bespoke usage falls back to the service default', () {
      final item = buildPrefillItem(
        id: '1',
        bespokeItem: {'type': 'jacket', 'serviceId': 'Suit', 'fabricId': 'a1', 'fabricUsage': 0},
        services: services,
        inventory: inventory,
      );
      expect(item.fabricUsed, 3); // Suit's default usage
    });
  });

  group('describeBespokeItem', () {
    final inventory = [fabric('a1', 'WHITE PIMA', 100)];

    test('shows garment, position, matched fabric and swatch', () {
      final text = describeBespokeItem(
        {'type': 'jacket', 'fabricId': 'a1', 'fabric': 'WHITE PIMA', 'fabricSwatch': 'BN0033'},
        index: 0,
        total: 3,
        inventory: inventory,
      );
      expect(text, contains('外套（1/3）'));
      expect(text, contains('布料：WHITE PIMA（樣板：BN0033）'));
      expect(text, contains('庫存已對應'));
    });

    test('warns when the fabric is not in inventory or not filled in', () {
      expect(
        describeBespokeItem({'type': 'shirt', 'fabric': 'Unknown'},
            index: 1, total: 2, inventory: inventory),
        contains('庫存找不到'),
      );
      expect(
        describeBespokeItem({'type': 'vest'}, index: 0, total: 1, inventory: inventory),
        contains('布料：未填寫'),
      );
    });
  });
}
