import 'package:flutter/material.dart';

import '../services/auth_service.dart';

import 'login_screen.dart';

import 'main_navigation.dart';

class SignupScreen extends StatefulWidget {

  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() =>
      _SignupScreenState();
}

class _SignupScreenState
    extends State<SignupScreen> {

  final TextEditingController
  usernameController =
  TextEditingController();

  final emailController =
  TextEditingController();

  final passwordController =
  TextEditingController();

  String errorMessage = '';

  bool _obscurePassword = true;

  Future<void> createAccount() async {

    String username =
    usernameController.text.trim();

    String email =
    emailController.text.trim();

    String password =
    passwordController.text.trim();

    // USERNAME VALIDATION

    if (username.isEmpty) {

      setState(() {

        errorMessage =
        'Username is required.';
      });

      return;
    }

    if (username.length < 4) {

      setState(() {

        errorMessage =
        'Username must be at least 4 characters.';
      });

      return;
    }

    bool hasSpaces =
    username.contains(' ');

    if (hasSpaces) {

      setState(() {

        errorMessage =
        'Username cannot contain spaces.';
      });

      return;
    }

    // EMAIL VALIDATION

    if (email.isEmpty) {

      setState(() {

        errorMessage =
        'Email is required.';
      });

      return;
    }

    // KU EMAIL VALIDATION

    if (!email.endsWith(
        '@students.ku.ac.ke')) {

      setState(() {

        errorMessage =
        'Only KU student emails are allowed.';
      });

      return;
    }

    // PASSWORD VALIDATION

    if (password.length < 12) {

      setState(() {

        errorMessage =
        'Password must be at least 12 characters long.';
      });

      return;
    }

    bool hasUppercase =
    password.contains(
      RegExp(r'[A-Z]'),
    );

    bool hasLowercase =
    password.contains(
      RegExp(r'[a-z]')
    );

    bool hasNumber =
    password.contains(
      RegExp(r'[0-9]'),
    );

    bool hasSpecialCharacter =
    password.contains(
      RegExp(r'[!@#$%^&*(),.?":{}|<>]')
    );

    if (!hasUppercase ||
        !hasLowercase ||
        !hasNumber ||
        !hasSpecialCharacter) {

      setState(() {

        errorMessage =
        'Password must contain a capital letter and number.';
      });

      return;
    }

    try {

      await AuthService().signUp(

        email: email,

        password: password,

        username: username,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MainNavigation(),
        ),
      );

    } catch (e) {

      String error =

      e.toString().replaceAll(
        'Exception: ',
        '',
      );

      if (error.contains(
          'User already registered')) {

        error =
        'Account already exists. Please log in.';
      }

      setState(() {

        errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Sign Up'),
      ),

      body: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [

          Image.asset(
          'assets/logo.png',
          height: 100, // Adjust size as needed
        ),

            const SizedBox(height: 30),

            // USERNAME FIELD

            TextField(

              controller:
              usernameController,

              decoration:
              const InputDecoration(

                labelText: 'Username',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            // EMAIL FIELD

            TextField(

              controller:
              emailController,

              decoration:
              const InputDecoration(

                labelText:
                'KU Student Email',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            // PASSWORD FIELD

            TextField(

              controller:
              passwordController,

              obscureText: _obscurePassword,

              decoration:
              InputDecoration(

                labelText: 'Password',

                border:
                const OutlineInputBorder(),

                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // SIGNUP BUTTON

            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton(

                onPressed: createAccount,

                child: const Text(

                  'Create Account',

                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // ERROR MESSAGE

            Text(

              errorMessage,

              style: const TextStyle(
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 20),

            // LOGIN LINK

            Row(

              mainAxisAlignment:
              MainAxisAlignment.center,

              children: [

                const Text(
                  'Already have an account?',
                ),

                TextButton(

                  onPressed: () {

                    Navigator.push(

                      context,

                      MaterialPageRoute(
                        builder: (context) =>
                        const LoginScreen(),
                      ),
                    );
                  },

                  child: const Text(
                    'Login',
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