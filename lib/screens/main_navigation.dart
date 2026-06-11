import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'releases_screen.dart';

/// Root navigation shell hosting the app's primary tabs in a bottom
/// navigation bar. Tabs are kept alive via [IndexedStack] so their state
/// (MQTT connection, loaded releases, scroll position) survives switching.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [HomeScreen(), ReleasesScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0F172A),
          selectedItemColor: const Color(0xFF2563EB),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_walk_rounded),
              label: 'Control',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.system_update_rounded),
              label: 'Versions',
            ),
          ],
        ),
      ),
    );
  }
}
