import 'package:flutter/material.dart';
import 'package:ku_konnect/screens/home_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_status_service.dart';

import 'edit_profile_page.dart';

// import 'home_screen.dart';

class ProfilePage extends StatefulWidget {

  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() =>
      _ProfilePageState();
}

class _ProfilePageState
    extends State<ProfilePage> {

  final supabase =
      Supabase.instance.client;

  Map<String, dynamic>? profile;

  bool isLoading = true;

  @override
  void initState() {

    super.initState();

    loadProfile();
  }

  Future<void> loadProfile() async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    final data = await supabase

        .from('profiles')

        .select()

        .eq('id', user.id)

        .single();

    setState(() {

      profile = data;

      isLoading = false;
    });
  }

  Future<void> logout() async {
    // Explicitly set offline before signing out using the service
    try {
      await UserStatusService().setOffline();
    } catch (_) {}

    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(

      context,

      MaterialPageRoute(
        builder: (context) =>
        const HomeScreen(),
      ),

          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {

    if (isLoading) {

      return const Scaffold(

        body: Center(
          child:
          CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(

      appBar: AppBar(

        title: const Text(
          'My Profile',
        ),

        actions: [

          IconButton(

            onPressed: logout,

            icon: const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          children: [

            CircleAvatar(

              radius: 60,

              backgroundImage:

              profile!['avatar_url'] != null

                  ? NetworkImage(
                profile!['avatar_url'],
              )

                  : null,

              child:

              profile!['avatar_url'] == null

                  ? const Icon(
                Icons.person,
                size: 60,
              )

                  : null,
            ),

            const SizedBox(height: 20),

            Text(

              profile!['username'],

              style: const TextStyle(

                fontSize: 28,

                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(

              profile!['bio'] ?? '',

              textAlign:
              TextAlign.center,

              style: const TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton(

                onPressed: () async {

                  await Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (context) =>

                      const EditProfilePage(),
                    ),
                  );

                  loadProfile();
                },

                child: const Text(
                  'Edit Profile',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}