import 'package:flutter/material.dart';

class Navigation extends StatelessWidget {
  final String currentRoute;

  const Navigation({super.key, required this.currentRoute});

  void onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed('/');
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
    return NavigationRail(
      selectedIndex: _getSelectedIndex(currentRoute),
      onDestinationSelected: (index) => onDestinationSelected(context, index),
      labelType: NavigationRailLabelType.all,
      // 定義側邊欄的項目
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: Text('POS'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: Text('Orders'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Customers'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: Text('Fabric'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.cut_outlined),
          selectedIcon: Icon(Icons.cut),
          label: Text('Workshop'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );
  }

  int _getSelectedIndex(String route) {
    switch (route) {
      case '/':
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
