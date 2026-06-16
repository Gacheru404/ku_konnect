import 'package:flutter/material.dart';
import 'buzz_news_page.dart';
import 'gaming_page.dart';
import 'reels_page.dart';
import 'market_page.dart';
import 'profile_page.dart';

class HomePage extends StatelessWidget {
  final VoidCallback? onGoToChat;

  const HomePage({super.key, this.onGoToChat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KU Konnect'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                );
              },
              child: const CircleAvatar(
                child: Icon(Icons.person),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect with fellow comrades, chat, study, game, trade and have fun.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),

              // Chat banner — clickable
              GestureDetector(
                onTap: () {
                  if (onGoToChat != null) {
                    onGoToChat!();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.local_fire_department, size: 40),
                      SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Campus chats are active right now. Join the conversation!',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),
              const Text(
                'Quick Access',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                children: [
                  buildCard(
                    context,
                    Icons.campaign,
                    'Buzz News',
                    Colors.red[100]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BuzzNewsPage(),
                      ),
                    ),
                  ),
                  buildCard(
                    context,
                    Icons.sports_esports,
                    'Gaming',
                    Colors.purple[100]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GamingPage(),
                      ),
                    ),
                  ),
                  buildCard(
                    context,
                    Icons.video_library,
                    'Reels',
                    Colors.orange[100]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReelsPage(),
                      ),
                    ),
                  ),
                  buildCard(
                    context,
                    Icons.store,
                    'Market',
                    Colors.blue[100]!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MarketPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildCard(
      BuildContext context,
      IconData icon,
      String title,
      Color color, {
        VoidCallback? onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 45),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}