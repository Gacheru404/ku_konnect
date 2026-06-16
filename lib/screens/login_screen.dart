import 'package:flutter/material.dart';

import '../services/auth_service.dart';

import 'main_navigation.dart';

import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {

  final emailController =
  TextEditingController();

  final passwordController =
  TextEditingController();

  String errorMessage = '';

  Future<void> login() async {

    final email =
    emailController.text.trim();

    final password =
    passwordController.text.trim();

    // Check KU email first
    if (!email.endsWith('@students.ku.ac.ke')) {
      setState(() {
        errorMessage = 'Only KU student emails are allowed';
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your password.';
      });
      return;
    }

    try {
      await AuthService().signIn(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MainNavigation(),
        ),
      );

    } catch (e) {
      setState(() {
        errorMessage = 'Invalid password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Login'),
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [

            TextField(

              controller:
              emailController,

              textInputAction:
              TextInputAction.next,

              decoration:
              const InputDecoration(

                labelText: "Email",

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(

              controller:
              passwordController,

              obscureText: true,

              textInputAction:
              TextInputAction.done,

              onSubmitted: (_) =>
                  login(),

              decoration:
              const InputDecoration(

                labelText: "Password",

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton(

                onPressed: login,

                child: const Text(

                  "Login",

                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            Text(

              errorMessage,

              style: const TextStyle(
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 20),

            Row(

              mainAxisAlignment:
              MainAxisAlignment.center,

              children: [

                const Text(
                  "Don't have an account?",
                ),

                TextButton(

                  onPressed: () {

                    Navigator.push(

                      context,

                      MaterialPageRoute(
                        builder: (context) =>
                        const SignupScreen(),
                      ),
                    );
                  },

                  child: const Text(
                    'Sign Up',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}