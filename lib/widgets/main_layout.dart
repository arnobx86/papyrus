import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../core/connectivity_service.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final isOnline = context.watch<ConnectivityService>().isOnline;
    
    int currentIndex = 0;
    if (location.startsWith('/kena-becha')) {
      currentIndex = 1;
    } else if (location.startsWith('/len-den')) {
      currentIndex = 2;
    } else if (location.startsWith('/ay-bay')) {
      currentIndex = 3;
    }

    return Scaffold(
      body: Column(
        children: [
          if (!isOnline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.wifiOff, color: Colors.white, size: 14),
                  SizedBox(width: 8),
                  Text(
                    'Offline Mode – Viewing Cached Data',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/shop-home');
                break;
              case 1:
                context.go('/kena-becha');
                break;
              case 2:
                context.go('/len-den');
                break;
              case 3:
                context.go('/ay-bay');
                break;
            }
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.layoutGrid),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.shoppingCart),
              label: 'কেনা বেচা',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.users),
              label: 'লেন দেন',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.wallet),
              label: 'আয় ব্যয়',
            ),
          ],
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}
