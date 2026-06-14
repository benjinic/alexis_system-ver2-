import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import '../components/navigation.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({
    super.key,
    required this.currentRoute,
    required this.child,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
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

  void _onItemTapped(int index) {
    const routes = [
      '/dashboard',
      '/pos',
      '/orders',
      '/customers',
      '/inventory',
      '/workshop',
      '/settings',
    ];

    if (widget.currentRoute != routes[index]) {
      Navigator.of(context).pushReplacementNamed(routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                Navigation(currentRoute: widget.currentRoute),
                Expanded(child: widget.child),
              ],
            )
          : SafeArea(child: widget.child),
      bottomNavigationBar: isDesktop
          ? null
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(canvasColor: const Color(0xFF1E1E2C)),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _getSelectedIndex(widget.currentRoute),
                onTap: _onItemTapped,
                selectedItemColor: const Color(0xFF64B5F6),
                unselectedItemColor: Colors.grey[500],
                showUnselectedLabels: true,
                selectedFontSize: 10,
                unselectedFontSize: 10,
                items: const [
                  BottomNavigationBarItem(
                    icon: IconText(Icons.analytics_outlined),
                    activeIcon: IconText(Icons.analytics),
                    label: 'Dash',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.storefront_outlined),
                    activeIcon: IconText(Icons.storefront),
                    label: 'POS',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.list_alt_outlined),
                    activeIcon: IconText(Icons.list_alt),
                    label: 'Orders',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.groups_outlined),
                    activeIcon: IconText(Icons.groups),
                    label: 'Clients',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.category_outlined),
                    activeIcon: IconText(Icons.category),
                    label: 'Fabric',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.content_cut_outlined),
                    activeIcon: IconText(Icons.content_cut),
                    label: 'Shop',
                  ),
                  BottomNavigationBarItem(
                    icon: IconText(Icons.tune_outlined),
                    activeIcon: IconText(Icons.tune),
                    label: 'Set',
                  ),
                ],
              ),
            ),
    );
  }
}
