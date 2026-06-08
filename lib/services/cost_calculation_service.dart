import '../models/order.dart';
import '../models/service_item.dart';
import 'database_service_interface.dart';

class CostCalculationService {
  static double _resolveUnitPrice(
    OrderItem item,
    Map<String, ServiceItem> serviceByName,
  ) {
    if (item.manualUnitPrice) {
      return item.price;
    }

    final servicePrice = serviceByName[item.service]?.price;
    if (servicePrice != null && servicePrice > 0) {
      return servicePrice;
    }
    return item.price;
  }

  static double resolveUnitPrice(
    OrderItem item, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    return _resolveUnitPrice(item, serviceByName);
  }

  static List<OrderItem> syncItemsWithServicePrices(
    List<OrderItem> items, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    return items
        .map(
          (item) =>
              item.copyWith(price: _resolveUnitPrice(item, serviceByName)),
        )
        .toList();
  }

  static double calculateSubtotalFromItems(
    List<OrderItem> items, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    return items.fold<double>(
      0,
      (sum, item) =>
          sum + (_resolveUnitPrice(item, serviceByName) * item.quantity),
    );
  }

  static Future<double> calculateSubtotalFromItemsAsync(
    List<OrderItem> items,
    ServiceCatalogDataSource dataSource,
  ) async {
    if (items.isEmpty) return 0;
    final services = await dataSource.getServicesStream().first;
    final serviceByName = {
      for (final service in services) service.name: service,
    };
    return calculateSubtotalFromItems(items, serviceByName: serviceByName);
  }

  static double calculateDiscountedTotal({
    required double subtotal,
    required double discount,
  }) {
    final total = subtotal - discount;
    return total > 0 ? total : 0;
  }

  static double calculateBalance({
    required double total,
    required double deposit,
    required double balancePayment,
  }) {
    final balance = total - (deposit + balancePayment);
    return balance > 0 ? balance : 0;
  }

  static Order syncOrderWithServicePrices(
    Order order, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    final syncedItems = syncItemsWithServicePrices(
      order.items,
      serviceByName: serviceByName,
    );
    final hasOrderItems = syncedItems.isNotEmpty;
    final subtotal = hasOrderItems
        ? calculateSubtotalFromItems(syncedItems, serviceByName: serviceByName)
        : (order.subtotal > 0
              ? order.subtotal
              : (order.total + order.discount));
    final total = hasOrderItems
        ? calculateDiscountedTotal(subtotal: subtotal, discount: order.discount)
        : (order.total > 0
              ? order.total
              : calculateDiscountedTotal(
                  subtotal: subtotal,
                  discount: order.discount,
                ));
    final recalculatedOutsourcingCost = calculateOutsourcingCostFromItems(
      syncedItems,
      serviceByName: serviceByName,
    );
    final hasExplicitOutsourcingConfig = syncedItems.any(
      (item) => serviceByName[item.service]?.outsourcingCost != null,
    );
    final outsourcingCost = hasExplicitOutsourcingConfig
        ? recalculatedOutsourcingCost
        : order.outsourcingCost;
    final totalCost = calculateTotalCost(
      materialCost: order.materialCost,
      outsourcingCost: outsourcingCost,
      fixedCost: order.fixedCost,
    );
    final balance = calculateBalance(
      total: total,
      deposit: order.deposit,
      balancePayment: order.balancePayment,
    );

    return order.copyWith(
      items: syncedItems,
      subtotal: subtotal,
      total: total,
      balance: balance,
      laborCost: 0,
      outsourcingCost: outsourcingCost,
      totalCost: totalCost,
      totalProfit: total - totalCost,
    );
  }

  // 直接從 Firebase 讀取服務數據
  static Future<double> calculateItemOutsourcingCostAsync(
    OrderItem item,
    ServiceCatalogDataSource dataSource,
  ) async {
    final services = await dataSource.getServicesStream().first;
    final serviceByName = {for (var service in services) service.name: service};

    return calculateItemOutsourcingCost(item, serviceByName: serviceByName);
  }

  // 計算多個商品的外包成本
  static Future<double> calculateOutsourcingCostFromItemsAsync(
    List<OrderItem> items,
    ServiceCatalogDataSource dataSource,
  ) async {
    if (items.isEmpty) return 0;

    final services = await dataSource.getServicesStream().first;
    final serviceByName = {for (var service in services) service.name: service};

    return calculateOutsourcingCostFromItems(
      items,
      serviceByName: serviceByName,
    );
  }

  // 解析訂單的外包成本
  static Future<double> resolveOutsourcingCostForOrderAsync(
    Order order,
    ServiceCatalogDataSource dataSource,
  ) async {
    if (order.items.isEmpty) {
      return order.outsourcingCost;
    }

    return calculateOutsourcingCostFromItemsAsync(order.items, dataSource);
  }

  // 計算總成本
  static double calculateTotalCost({
    required double materialCost,
    required double outsourcingCost,
    required double fixedCost,
  }) {
    return materialCost + outsourcingCost + fixedCost;
  }

  // 新邏輯：使用服務明確設定的 outsourcingCost，不再反推 (/2.5)
  static double calculateItemOutsourcingCost(
    OrderItem item, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    final configuredPerUnit = serviceByName[item.service]?.outsourcingCost;
    if (configuredPerUnit == null) {
      return 0;
    }

    final perUnit = configuredPerUnit < 0 ? 0.0 : configuredPerUnit;
    return perUnit * item.quantity;
  }

  static double calculateOutsourcingCostFromItems(
    List<OrderItem> items, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    return items.fold<double>(
      0,
      (sum, item) =>
          sum +
          calculateItemOutsourcingCost(item, serviceByName: serviceByName),
    );
  }

  static double resolveOutsourcingCostForOrder(
    Order order, {
    Map<String, ServiceItem> serviceByName = const {},
  }) {
    if (order.items.isEmpty) {
      return order.outsourcingCost;
    }

    return calculateOutsourcingCostFromItems(
      order.items,
      serviceByName: serviceByName,
    );
  }
}
