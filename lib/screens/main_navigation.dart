import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'shift_screen.dart';
import 'earnings_screen.dart';
import '../config/app_config.dart';
import '../services/push_service.dart';
import '../utils/app_colors.dart';

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
  StreamSubscription<Map<String, dynamic>>? _pushTaps;

  // Built once and kept alive by the IndexedStack: switching tabs never
  // re-runs network calls or loses scroll position.
  late final List<Widget> _screens = [
    if (AppConfig.isAttendanceEnabled) const ShiftScreen(),
    const OrdersScreen(),
    const EarningsScreen(),
    const ProfileScreen(),
  ];

  int get _ordersIndex => AppConfig.isAttendanceEnabled ? 1 : 0;

  @override
  void initState() {
    super.initState();
    // Tapping an order notification opens the Orders tab.
    _pushTaps = PushService.onNotificationTap.listen((_) {
      if (mounted) _onTabTapped(_ordersIndex);
    });
  }

  @override
  void dispose() {
    _pushTaps?.cancel();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons over the dark headers.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: NotificationListener<TabNavigationNotification>(
        onNotification: (notification) {
          _onTabTapped(notification.index);
          return true;
        },
        child: Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: Offset(0, -4))],
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabTapped,
              destinations: [
                if (AppConfig.isAttendanceEnabled)
                  const NavigationDestination(
                    icon: Icon(Icons.access_time_rounded),
                    label: 'Shift',
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'Orders',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Cash',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
