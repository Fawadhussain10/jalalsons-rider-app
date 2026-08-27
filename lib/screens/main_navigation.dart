import 'package:flutter/material.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'shift_screen.dart';
import 'earnings_screen.dart';
import '../config/app_config.dart';

class TabNavigationNotification extends Notification {
  final int index;
  TabNavigationNotification(this.index);
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late PageController _pageController;

  List<Widget> get _screens {
    final screens = <Widget>[];
    if (AppConfig.isAttendanceEnabled) {
      screens.add(const ShiftScreen());
    }
    screens.addAll([
      const OrdersScreen(),
      const EarningsScreen(),
      const ProfileScreen(),
    ]);
    return screens;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.jumpToPage(index); // Use jumpToPage for instant switch or animateToPage
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<TabNavigationNotification>(
      onNotification: (notification) {
        _onTabTapped(notification.index);
        return true;
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(), // Disable swipe to avoid conflict with maps/charts
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          children: _screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          items: [
            if (AppConfig.isAttendanceEnabled)
              const BottomNavigationBarItem(
                icon: Icon(Icons.access_time),
                label: 'Shift',
              ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              label: 'Orders',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet),
              label: 'Cash',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
