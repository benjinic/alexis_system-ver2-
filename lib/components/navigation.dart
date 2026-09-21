import 'package:flutter/material.dart';
import 'icon_text.dart';
import '../l10n/app_localizations.dart';

class Navigation extends StatelessWidget {
  final String currentRoute;
  final int urgentCount;

  const Navigation({
    super.key,
    required this.currentRoute,
    this.urgentCount = 0,
  });

  void onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed('/dashboard');
        break;
      case 1:
        Navigator.of(context).pushReplacementNamed('/pos');
        break;
      case 2:
        Navigator.of(context).pushReplacementNamed('/orders');
        break;
      case 3:
        Navigator.of(context).pushReplacementNamed('/customers');
        break;
      case 4:
        Navigator.of(context).pushReplacementNamed('/inventory');
        break;
      case 5:
        Navigator.of(context).pushReplacementNamed('/workshop');
        break;
      case 6:
        Navigator.of(context).pushReplacementNamed('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NavigationRail(
      selectedIndex: _getSelectedIndex(currentRoute),
      onDestinationSelected: (index) => onDestinationSelected(context, index),
      labelType: NavigationRailLabelType.all,
      // 定義側邊欄的項目
      destinations: [
        // 1. Dashboard (儀表板) -> 儀表板風格
        NavigationRailDestination(
          icon: const IconText(Icons.dashboard_outlined),
          selectedIcon: const IconText(Icons.dashboard),
          label: Text(l10n.navDashboard),
        ),
        // 2. POS (收銀) -> 購物車結算
        NavigationRailDestination(
          icon: const IconText(Icons.shopping_cart_outlined),
          selectedIcon: const IconText(Icons.shopping_cart),
          label: Text(l10n.navPOS),
        ),
        // 3. Orders (訂單) -> 收據風格
        NavigationRailDestination(
          icon: const IconText(Icons.receipt_long_outlined),
          selectedIcon: const IconText(Icons.receipt_long),
          label: Text(l10n.navOrders),
        ),
        // 4. Customers (客戶) -> 個人客戶風格
        NavigationRailDestination(
          icon: const IconText(Icons.person_outlined),
          selectedIcon: const IconText(Icons.person),
          label: Text(l10n.navClients),
        ),
        // 5. Fabric (布料/庫存) -> 分類管理
        NavigationRailDestination(
          icon: const IconText(Icons.category_outlined),
          selectedIcon: const IconText(Icons.category),
          label: Text(l10n.navFabric),
        ),
        // 6. Workshop (工廠) -> 工坊製作
        NavigationRailDestination(
          icon: Badge(
            isLabelVisible: urgentCount > 0,
            label: Text(urgentCount > 9 ? '9+' : '$urgentCount'),
            child: const IconText(Icons.engineering_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: urgentCount > 0,
            label: Text(urgentCount > 9 ? '9+' : '$urgentCount'),
            child: const IconText(Icons.engineering),
          ),
          label: Text(l10n.navShop),
        ),
        // 7. Settings (設定) -> 標準設定
        NavigationRailDestination(
          icon: const IconText(Icons.settings_outlined),
          selectedIcon: const IconText(Icons.settings),
          label: Text(l10n.navSettings),
        ),
      ],
    );
  }

  int _getSelectedIndex(String route) {
    switch (route) {
      case '/dashboard':
        return 0;
      case '/pos':
        return 1;
      case '/orders':
        return 2;
      case '/customers':
        return 3;
      case '/inventory':
        return 4;
      case '/workshop':
        return 5;
      case '/settings':
        return 6;
      default:
        return 0;
    }
  }
}
