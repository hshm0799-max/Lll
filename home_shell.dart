import 'package:flutter/material.dart';

import '../config.dart';
import 'bookings_page.dart';
import 'business_panel.dart';
import 'explore_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _hasBusiness = false;

  @override
  void initState() {
    super.initState();
    _checkBusiness();
  }

  // Owners and staff get an extra "Business" tab (role-based access, enforced by RLS on the server).
  Future<void> _checkBusiness() async {
    final rows = await db.from('business_members').select('business_id').eq('user_id', db.auth.currentUser!.id).eq('member_status', 'active').limit(1);
    if (mounted) setState(() => _hasBusiness = (rows as List).isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ExplorePage(),
      const BookingsPage(),
      if (_hasBusiness) const BusinessPanelPage(),
      const NotificationsPage(),
      ProfilePage(onBusinessCreated: _checkBusiness),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
      const NavigationDestination(icon: Icon(Icons.event_available), label: 'Bookings'),
      if (_hasBusiness) const NavigationDestination(icon: Icon(Icons.storefront), label: 'Business'),
      const NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
      const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
    ];
    final index = _index >= pages.length ? 0 : _index;
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
