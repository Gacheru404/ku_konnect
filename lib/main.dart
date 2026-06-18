import 'package:flutter/material.dart';

import 'firebase_options.dart';

import 'package:firebase_core/firebase_core.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';

import 'screens/main_navigation.dart';

Future<void> backgroundHandler(
    RemoteMessage message) async {

    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
    );
}

void main() async {

    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
    );

    await Supabase.initialize(
        url: 'https://fcakuqdkuurmfuedgxzc.supabase.co',
        publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjYWt1cWRrdXVybWZ1ZWRneHpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE0MDQ2OTAsImV4cCI6MjA5Njk4MDY5MH0.jeQjTlhl8WY0gycc4m58Pfqa6iMoBgS4BIP3q-05qlk',
    );

    FirebaseMessaging.onBackgroundMessage(
        backgroundHandler,
    );

    runApp(
        const KUKonnectApp(),
    );
}

class KUKonnectApp extends StatefulWidget {

    const KUKonnectApp({super.key});

    @override
    State<KUKonnectApp> createState() =>
        _KUKonnectAppState();
}

class _KUKonnectAppState
    extends State<KUKonnectApp> {

    @override
    void initState() {

        super.initState();

        requestNotificationPermission();

        _startOnlineHeartbeat();
    }

    void _startOnlineHeartbeat() {
        _onlineTimer =
            Timer.periodic(const Duration(seconds: 30), (_) async {

                final user =
                    Supabase.instance.client.auth.currentUser;

                if (user == null) return;

                await Supabase.instance.client
                    .from('profiles')
                    .update({
                    'last_seen':
                    DateTime.now().toUtc().toIso8601String(),
                })
                    .eq('id', user.id);
            });
    }

    @override
    void dispose() {
        _onlineTimer?.cancel();
        super.dispose();
    }

    Future<void>
    requestNotificationPermission() async {

        await FirebaseMessaging.instance
            .requestPermission(

            alert: true,

            badge: true,

            sound: true,
        );
    }

    @override
    Widget build(BuildContext context) {

        return MaterialApp(

            debugShowCheckedModeBanner: false,

            home: const AuthGate(),
        );
    }
}

class AuthGate extends StatelessWidget {

    const AuthGate({super.key});

    @override
    Widget build(BuildContext context) {

        final session =

            Supabase.instance.client
                .auth.currentSession;

        if (session != null) {

            return const MainNavigation();
        }

        return const HomeScreen();
    }
}