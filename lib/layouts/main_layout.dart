import 'package:flutter/material.dart';
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Navigation(
            currentRoute: widget.currentRoute,
          ),
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
