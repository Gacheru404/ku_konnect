import 'package:flutter/material.dart';

import '../services/user_status_service.dart';

import '../services/notification_service.dart';

import 'home_page.dart';

import 'chat_page.dart';

import 'study_page.dart';

import 'market_page.dart';

import 'users_page.dart';

class MainNavigation extends StatefulWidget {

  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() =>
      _MainNavigationState();
}

class _MainNavigationState
    extends State<MainNavigation>

    with WidgetsBindingObserver {

  int currentIndex = 0;

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      HomePage(onGoToChat: () {
        setState(() {
          currentIndex = 1;
        });
      }),
      ChatPage(onBack: () {
        setState(() {
          currentIndex = 0;
        });
      }),
      const UsersPage(),
      const StudyPage(),
      const MarketPage(),
    ];
    // rest of initState

    WidgetsBinding.instance
        .addObserver(this);

    UserStatusService()
        .setOnline();

    NotificationService()
        .saveToken();
  }

  @override
  void dispose() {

    WidgetsBinding.instance
        .removeObserver(this);

    UserStatusService()
        .setOffline();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state) {

    if (state ==
        AppLifecycleState.resumed) {

      UserStatusService()
          .setOnline();

    } else {

      UserStatusService()
          .setOffline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentIndex != 0) {
          setState(() {
            currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: pages[currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(currentIndex == 1 ? Icons.chat_bubble : Icons.chat),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'Users',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.school),
              label: 'Study',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.store),
              label: 'Market',
            ),
          ],
        ),
      ),
    );
  }
}