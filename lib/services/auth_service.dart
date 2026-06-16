import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {

  final supabase =
      Supabase.instance.client;

  // SIGN UP

  Future<void> signUp({

    required String email,

    required String password,

    required String username,

  }) async {

    // CHECK USERNAME

    final existingUsername =

    await supabase

        .from('profiles')

        .select()

        .eq('username', username)

        .maybeSingle();

    if (existingUsername != null) {

      throw Exception(
        'Username already taken.',
      );
    }

    // CREATE AUTH USER

    final AuthResponse response =

    await supabase.auth.signUp(

      email: email,

      password: password,
    );

    final user = response.user;

    if (user == null) {

      throw Exception(
          'Failed to create account.');
    }

    // WAIT FOR SESSION

    await Future.delayed(
      const Duration(seconds: 1),
    );

    // INSERT PROFILE

    await supabase

        .from('profiles')

        .insert({

      'id': user.id,

      'username': username,

      'email': email,

      'bio': '',
    });
  }

  // LOGIN

  Future<AuthResponse> signIn({

    required String email,

    required String password,

  }) async {

    return await supabase.auth
        .signInWithPassword(

      email: email,

      password: password,
    );
  }

  // LOGOUT

  Future<void> signOut() async {

    await supabase.auth.signOut();
  }
}