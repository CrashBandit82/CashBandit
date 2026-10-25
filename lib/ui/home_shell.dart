import 'package:flutter/material.dart';

import 'booking_form.dart';
import 'bookings_screen.dart';
import 'dashboard_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [DashboardScreen(), BookingsScreen(), RecurringScreen(), SettingsScreen()],
      ),
      floatingActionButton: _tab < 2
          ? FloatingActionButton.extended(
              heroTag: 'add',
              tooltip: 'Neue Buchung',
              onPressed: () => openBookingForm(context),
              icon: const Icon(Icons.add, size: 28),
              label: const Text('Buchung', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Übersicht'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Buchungen',
          ),
          NavigationDestination(icon: Icon(Icons.repeat), selectedIcon: Icon(Icons.repeat_on), label: 'Regelmäßig'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Einstellungen'),
        ],
      ),
    );
  }
}
