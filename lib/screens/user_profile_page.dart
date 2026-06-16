import 'package:flutter/material.dart';

import 'dm_page.dart';

class UserProfilePage extends StatelessWidget {

  final dynamic userData;

  const UserProfilePage({

    super.key,

    required this.userData,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(
          userData['username'],
        ),
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          children: [

            CircleAvatar(

              radius: 60,

              backgroundImage:

              userData['avatar_url'] != null

                  ? NetworkImage(
                userData['avatar_url'],
              )

                  : null,

              child:

              userData['avatar_url'] == null

                  ? const Icon(
                Icons.person,
                size: 60,
              )

                  : null,
            ),

            const SizedBox(height: 20),

            Text(

              userData['username'],

              style: const TextStyle(

                fontSize: 24,

                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              userData['bio'] ?? '',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton.icon(

                icon: const Icon(
                  Icons.chat,
                ),

                label: const Text(
                  'Message',
                ),

                onPressed: () {

                  Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (context) =>

                          DMPage(

                            receiverId:
                            userData['id'],

                            username:
                            userData['username'],
                          ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}