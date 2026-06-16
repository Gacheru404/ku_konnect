import 'package:supabase_flutter/supabase_flutter.dart';

class UserStatusService {

  final supabase =
      Supabase.instance.client;

  Future<void> setOnline() async {
    final user =
        supabase.auth.currentUser;
    if (user == null) return;

    await supabase
        .from('profiles')
        .update({
      'is_online': true,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', user.id);
  }

  Future<void> setOffline() async {
    final user =
        supabase.auth.currentUser;
    if (user == null) return;

    // Set last_seen to 10 minutes ago in UTC
    final tenMinsAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 10));

    await supabase
        .from('profiles')
        .update({
      'is_online': false,
      'last_seen': tenMinsAgo.toIso8601String(),
    })
        .eq('id', user.id);
  }
}