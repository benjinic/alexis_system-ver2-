import 'package:alexis_system/services/fabric_order_status_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FabricOrderStatusSync', () {
    test('detects only items that require fabric', () {
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({
          'service': 'Alteration',
          'fabricUsed': 0,
          'fabricUsage': 0,
        }),
        isFalse,
      );
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({'fabricId': ' BN0033 '}),
        isTrue,
      );
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({'fabricCode': 'FC-001'}),
        isTrue,
      );
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({'fabricName': 'Wool'}),
        isTrue,
      );
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({'fabricUsed': 1.25}),
        isTrue,
      );
      expect(
        FabricOrderStatusSync.itemMapRequiresFabric({'fabricUsage': '2.5'}),
        isTrue,
      );
    });

    test('keeps order status false when no fabric item exists', () {
      expect(
        FabricOrderStatusSync.areAllRequiredItemsOrdered([
          {'service': 'Alteration', 'isFabricOrdered': true},
          {'service': 'Button Repair', 'fabricUsed': 0},
        ]),
        isFalse,
      );
    });

    test('aggregates order status from fabric-required items only', () {
      expect(
        FabricOrderStatusSync.areAllRequiredItemsOrdered([
          {'service': 'Alteration', 'isFabricOrdered': false},
          {'service': 'Suit', 'fabricName': 'Wool', 'isFabricOrdered': true},
          {'service': 'Shirt', 'fabricUsed': 2, 'isFabricOrdered': true},
        ]),
        isTrue,
      );
    });

    test('returns false if any fabric-required item is still pending', () {
      expect(
        FabricOrderStatusSync.areAllRequiredItemsOrdered([
          {'service': 'Suit', 'fabricName': 'Wool', 'isFabricOrdered': true},
          {'service': 'Shirt', 'fabricUsed': 2, 'isFabricOrdered': false},
        ]),
        isFalse,
      );
    });
  });
}
