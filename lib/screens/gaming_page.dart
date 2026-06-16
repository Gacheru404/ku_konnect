import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GamingPage extends StatefulWidget {
  const GamingPage({super.key});

  @override
  State<GamingPage> createState() => _GamingPageState();
}

class _GamingPageState extends State<GamingPage> {
  final supabase = Supabase.instance.client;
  final codeController = TextEditingController();
  final gameController = TextEditingController();
  final messageController = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> gameCodesStream;
  late final Stream<List<Map<String, dynamic>>> gamingChatStream;

  @override
  void initState() {
    super.initState();
    gameCodesStream = supabase
        .from('game_codes')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    gamingChatStream = supabase
        .from('gaming_chat')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
  }

  bool isSharing = false;

  Future<void> shareGameCode() async {
    final game = gameController.text.trim();
    final code = codeController.text.trim();

    if (game.isEmpty || code.isEmpty) return;

    setState(() => isSharing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      await supabase.from('game_codes').insert({
        'user_id': user.id,
        'username': profile['username'],
        'game_name': game,
        'code': code,
        'created_at': DateTime.now().toIso8601String(),
      });

      gameController.clear();
      codeController.clear();

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isSharing = false);
    }
  }

  Future<void> sendGamingMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (messageController.text.trim().isEmpty) return;

    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    await supabase.from('gaming_chat').insert({
      'user_id': user.id,
      'username': profile['username'],
      'message': messageController.text.trim(),
    });

    messageController.clear();
  }

  void showShareCodeDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share Game Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: gameController,
                decoration: const InputDecoration(
                  labelText: 'Game Name (e.g. eFootball)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Room Code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSharing ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSharing ? null : () async {
                await shareGameCode();
                setDialogState(() {});
              },
              child: isSharing
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator())
                  : const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gaming'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Game Codes'),
              Tab(text: 'Gaming Chat'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGameCodes(),
            _buildGamingChat(),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 70), // Lift higher
              child: FloatingActionButton(
                onPressed: showShareCodeDialog,
                child: const Icon(Icons.add),
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildGameCodes() {
    return StreamBuilder(
      stream: gameCodesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final codes = snapshot.data!;

        if (codes.isEmpty) {
          return const Center(
            child: Text('No game codes yet. Share one!'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: codes.length,
          itemBuilder: (context, index) {
            final item = codes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.sports_esports,
                  color: Colors.purple,
                  size: 35,
                ),
                title: Text(
                  item['game_name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Shared by ${item['username']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item['code'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: item['code']),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGamingChat() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder(
            stream: gamingChatStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final messages = snapshot.data!;
              final currentUser = supabase.auth.currentUser;

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg['user_id'] == currentUser?.id;
                  final time = DateFormat('hh:mm a').format(
                    DateTime.parse(msg['created_at']),
                  );

                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 280),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.purple[300] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg['username'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(msg['message']),
                          const SizedBox(height: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    hintText: 'Chat with gamers...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onSubmitted: (_) => sendGamingMessage(),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                backgroundColor: Colors.purple,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: sendGamingMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}