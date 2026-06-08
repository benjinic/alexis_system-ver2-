import 'package:alexis_system/models/order.dart';
import 'package:alexis_system/models/service_item.dart';
import 'package:alexis_system/services/cost_calculation_service.dart';
import 'package:alexis_system/services/database_service_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CostCalculationService', () {
    test('uses configured service price unless item price is manual', () {
      final services = {
        'Suit': _service(name: 'Suit', price: 2800),
        'Shirt': _service(name: 'Shirt', price: 900),
      };

      final item = _item(service: 'Suit', price: 2500, quantity: 2);
      final manualItem = _item(
        service: 'Shirt',
        price: 1200,
        quantity: 1,
        manualUnitPrice: true,
      );

      expect(
        CostCalculationService.resolveUnitPrice(item, serviceByName: services),
        2800,
      );
      expect(
        CostCalculationService.resolveUnitPrice(
          manualItem,
          serviceByName: services,
        ),
        1200,
      );
      expect(
        CostCalculationService.calculateSubtotalFromItems([
          item,
          manualItem,
        ], serviceByName: services),
        6800,
      );
    });

    test('discounted total and balance never go below zero', () {
      expect(
        CostCalculationService.calculateDiscountedTotal(
          subtotal: 1000,
          discount: 250,
        ),
        750,
      );
      expect(
        CostCalculationService.calculateDiscountedTotal(
          subtotal: 1000,
          discount: 1200,
        ),
        0,
      );
      expect(
        CostCalculationService.calculateBalance(
          total: 3000,
          deposit: 1000,
          balancePayment: 500,
        ),
        1500,
      );
      expect(
        CostCalculationService.calculateBalance(
          total: 3000,
          deposit: 2000,
          balancePayment: 1200,
        ),
        0,
      );
    });

    test('outsourcing cost uses explicit per-unit service cost only', () {
      final services = {
        'Suit': _service(name: 'Suit', price: 2800, outsourcingCost: 700),
        'Vest': _service(name: 'Vest', price: 1100),
        'Pants': _service(name: 'Pants', price: 1200, outsourcingCost: -50),
      };

      expect(
        CostCalculationService.calculateOutsourcingCostFromItems([
          _item(service: 'Suit', price: 2800, quantity: 2),
          _item(service: 'Vest', price: 1100, quantity: 3),
          _item(service: 'Pants', price: 1200, quantity: 1),
        ], serviceByName: services),
        1400,
      );
    });

    test(
      'async calculations can use a fake service catalog data source',
      () async {
        final dataSource = _FakeServiceCatalogDataSource([
          _service(name: 'Suit', price: 3200, outsourcingCost: 900),
          _service(name: 'Shirt', price: 850, outsourcingCost: 200),
        ]);
        final items = [
          _item(service: 'Suit', price: 2800, quantity: 1),
          _item(service: 'Shirt', price: 800, quantity: 2),
        ];

        await expectLater(
          CostCalculationService.calculateSubtotalFromItemsAsync(
            items,
            dataSource,
          ),
          completion(4900),
        );
        await expectLater(
          CostCalculationService.calculateOutsourcingCostFromItemsAsync(
            items,
            dataSource,
          ),
          completion(1300),
        );
      },
    );

    test(
      'async order outsourcing keeps stored value when no items exist',
      () async {
        final dataSource = _FakeServiceCatalogDataSource([
          _service(name: 'Suit', price: 3200, outsourcingCost: 900),
        ]);
        final order = _order(items: const [], outsourcingCost: 450);

        await expectLater(
          CostCalculationService.resolveOutsourcingCostForOrderAsync(
            order,
            dataSource,
          ),
          completion(450),
        );
      },
    );

    test('syncOrderWithServicePrices recalculates totals and profit', () {
      final services = {
        'Suit': _service(name: 'Suit', price: 3000, outsourcingCost: 800),
        'Shirt': _service(name: 'Shirt', price: 900, outsourcingCost: 250),
      };
      final order = _order(
        items: [
          _item(service: 'Suit', price: 2500, quantity: 1),
          _item(service: 'Shirt', price: 900, quantity: 2),
        ],
        discount: 300,
        deposit: 1000,
        balancePayment: 500,
        materialCost: 600,
        fixedCost: 200,
      );

      final synced = CostCalculationService.syncOrderWithServicePrices(
        order,
        serviceByName: services,
      );

      expect(synced.items[0].price, 3000);
      expect(synced.subtotal, 4800);
      expect(synced.total, 4500);
      expect(synced.outsourcingCost, 1300);
      expect(synced.totalCost, 2100);
      expect(synced.totalProfit, 2400);
      expect(synced.balance, 3000);
      expect(synced.laborCost, 0);
    });

    test('orders without items preserve stored total when possible', () {
      final order = _order(
        items: const [],
        subtotal: 0,
        discount: 100,
        total: 2000,
        deposit: 500,
        balancePayment: 250,
        materialCost: 300,
        outsourcingCost: 400,
        fixedCost: 100,
      );

      final synced = CostCalculationService.syncOrderWithServicePrices(order);

      expect(synced.subtotal, 2100);
      expect(synced.total, 2000);
      expect(synced.outsourcingCost, 400);
      expect(synced.totalCost, 800);
      expect(synced.totalProfit, 1200);
      expect(synced.balance, 1250);
    });
  });
}

class _FakeServiceCatalogDataSource implements ServiceCatalogDataSource {
  _FakeServiceCatalogDataSource(this.services);

  final List<ServiceItem> services;

  @override
  Stream<List<ServiceItem>> getServicesStream() => Stream.value(services);
}

ServiceItem _service({
  required String name,
  required double price,
  double? outsourcingCost,
}) {
  return ServiceItem(
    id: name.toLowerCase(),
    name: name,
    price: price,
    defaultFabricUsage: 0,
    outsourcingCost: outsourcingCost,
  );
}

OrderItem _item({
  required String service,
  required double price,
  required int quantity,
  bool manualUnitPrice = false,
}) {
  return OrderItem(
    id: service.toLowerCase(),
    service: service,
    price: price,
    quantity: quantity,
    manualUnitPrice: manualUnitPrice,
  );
}

Order _order({
  required List<OrderItem> items,
  double subtotal = 0,
  double discount = 0,
  double total = 0,
  double deposit = 0,
  double balancePayment = 0,
  double materialCost = 0,
  double outsourcingCost = 0,
  double fixedCost = 0,
}) {
  return Order(
    id: 'order-1',
    uniqueId: 'A0001',
    customerId: 'customer-1',
    customerName: 'Test Customer',
    items: items,
    subtotal: subtotal,
    discount: discount,
    total: total,
    deposit: deposit,
    balancePayment: balancePayment,
    balance: 0,
    materialCost: materialCost,
    outsourcingCost: outsourcingCost,
    fixedCost: fixedCost,
    totalCost: 0,
    totalProfit: 0,
    status: 'pending',
    paymentMethod: 'Cash',
  );
}
