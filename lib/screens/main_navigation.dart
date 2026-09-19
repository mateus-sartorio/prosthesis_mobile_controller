import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'releases_screen.dart';
import 'sensors_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  static const bool _showReleasesTab = false;

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const HomeScreen(),
      SensorsScreen(isActive: _currentIndex == 1),
      if (_showReleasesTab) const ReleasesScreen(),
    ];

    const items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: Icon(Icons.directions_walk_rounded),
        label: 'Control',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.show_chart_rounded),
        label: 'Sensors',
      ),
      if (_showReleasesTab)
        BottomNavigationBarItem(
          icon: Icon(Icons.system_update_rounded),
          label: 'Versions',
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(index: _currentIndex, children: screens),
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
          items: items,
        ),
      ),
    );
  }
}
