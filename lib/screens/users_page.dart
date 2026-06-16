import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_page.dart';

class UsersPage extends StatelessWidget {

  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {

    final supabase =
        Supabase.instance.client;

    return Scaffold(

      appBar: AppBar(
        title: const Text('Students'),
      ),

      body: FutureBuilder(

        future: supabase
            .from('profiles')
            .select(),

        builder: (context, snapshot) {

          if (!snapshot.hasData) {

            return const Center(
              child:
              CircularProgressIndicator(),
            );
          }

          final users =
          snapshot.data!;

          return ListView.builder(

            itemCount:
            users.length,

            itemBuilder:
                (context, index) {

              final user =
              users[index];

              final lastSeenStr = user['last_seen'];
              String statusText = 'Offline';
              if (lastSeenStr != null) {
                final lastSeen = DateTime.parse(lastSeenStr).toUtc();
                final now = DateTime.now().toUtc();
                final diff = now.difference(lastSeen);
                if (diff.inMinutes < 5) {
                  statusText = 'Online';
                } else {
                  // Format for local time display
                  statusText = 'Last seen: ${DateFormat('MMM d, hh:mm a').format(lastSeen.toLocal())}';
                }
              }

              return ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(
                      backgroundImage: user['avatar_url'] != null
                          ? NetworkImage(user['avatar_url'])
                          : null,
                      child: user['avatar_url'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    if (statusText == 'Online')
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 12,
                          width: 12,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(user['username']),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['bio'] ?? ''),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusText == 'Online' ? Colors.green : Colors.grey,
                        fontWeight: statusText == 'Online' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                onTap: () {

                  Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (context) =>

                          UserProfilePage(
                            userData: user,
                          ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}