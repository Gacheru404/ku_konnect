import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:intl/intl.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {

  const ChatPage({super.key});

  @override
  State<ChatPage> createState() =>
      _ChatPageState();
}

class _ChatPageState
    extends State<ChatPage> {

  final supabase =
      Supabase.instance.client;

  final TextEditingController
  messageController =
  TextEditingController();

  final ScrollController
  scrollController =
  ScrollController();

  File? selectedMedia;

  String? mediaType;

  bool isSending = false;

  late final Stream<List<Map<String, dynamic>>> messagesStream;

  @override
  void initState() {
    super.initState();
    messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
  }

  final List<String> blockedWords = [

    'politics',

    'siasa',

    'warm regards',

    'affordable',

    'sale',

    'brokies',

    'brokie',

    'vote',

    'betting',

    'odds',

    '1xbet',

    'aviator',

    'casino',

    'forex signal',

    'crypto giveaway',

    'free money',

    'earn cash',

    'whatsapp group',

    'telegram group',

    '.com',

    '.net',

    '.org',
  ];

  Future<void> pickMedia() async {

    final picker = ImagePicker();

    final file = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) {

      return;
    }

    setState(() {

      selectedMedia = File(file.path);

      mediaType = 'image';
    });
  }

  Future<void> sendMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final message = messageController.text.trim();
    if (message.isEmpty && selectedMedia == null) return;

    if (isSending) return;

    // MODERATION
    final lowerMessage = message.toLowerCase();
    bool containsBlockedWord = blockedWords.any((word) {
      return lowerMessage.contains(word);
    });

    if (containsBlockedWord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Advertisements/spam are not allowed.')),
      );
      return;
    }

    setState(() => isSending = true);

    try {
      // Use maybeSingle() to avoid crash if profile doesn't exist
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        throw 'User profile not found. Please update your profile first.';
      }

      String? mediaUrl;

      // UPLOAD IMAGE
      if (selectedMedia != null) {
        final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';

        await supabase.storage.from('Chat Media').upload(
          fileName,
          selectedMedia!,
        );

        mediaUrl = supabase.storage.from('Chat Media').getPublicUrl(fileName);
      }

      await supabase.from('messages').insert({
        'sender_id': user.id,
        'username': profile['username'],
        'message': message,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'avatar_url': profile['avatar_url'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      messageController.clear();
      setState(() {
        selectedMedia = null;
        mediaType = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  void scrollToBottom() {

    Future.delayed(
      const Duration(milliseconds: 200),
          () {

        if (!scrollController.hasClients) {

          return;
        }

        scrollController.animateTo(

          scrollController
              .position
              .maxScrollExtent,

          duration:
          const Duration(milliseconds: 300),

          curve: Curves.easeOut,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {

    final currentUser =
        supabase.auth.currentUser;

    return Scaffold(

      backgroundColor:
      Colors.grey[100],

      appBar: AppBar(

        title: const Text(
          'KU Chat',
        ),

        centerTitle: true,
      ),

      body: Column(

        children: [

          // IMAGE PREVIEW

          if (selectedMedia != null)

            Container(

              padding:
              const EdgeInsets.all(10),

              color: Colors.white,

              child: Stack(

                children: [

                  ClipRRect(

                    borderRadius:
                    BorderRadius.circular(12),

                    child: Image.file(

                      selectedMedia!,

                      height: 120,

                      width: 120,

                      fit: BoxFit.cover,
                    ),
                  ),

                  Positioned(

                    right: 0,

                    child: CircleAvatar(

                      radius: 14,

                      backgroundColor:
                      Colors.red,

                      child: IconButton(

                        padding:
                        EdgeInsets.zero,

                        onPressed: () {

                          setState(() {

                            selectedMedia = null;

                            mediaType = null;
                          });
                        },

                        icon: const Icon(

                          Icons.close,

                          color: Colors.white,

                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(

            child: StreamBuilder(

              stream: messagesStream,

              builder: (context, snapshot) {

                if (!snapshot.hasData) {

                  return const Center(

                    child:
                    CircularProgressIndicator(),
                  );
                }

                final messages =
                snapshot.data!;

                WidgetsBinding.instance
                    .addPostFrameCallback((_) {

                  scrollToBottom();
                });

                return ListView.builder(

                  controller:
                  scrollController,

                  padding:
                  const EdgeInsets.all(10),

                  itemCount:
                  messages.length,

                  itemBuilder:
                      (context, index) {

                    final message =
                    messages[index];

                    final isMe =

                        message['sender_id'] ==

                            currentUser?.id;

                    final time = DateFormat(
                      'hh:mm a',
                    ).format(

                      DateTime.parse(
                        message['created_at'],
                      ),
                    );

                    return Padding(

                      padding:
                      const EdgeInsets.only(
                        bottom: 12,
                      ),

                      child: Row(

                        mainAxisAlignment:

                        isMe

                            ? MainAxisAlignment.end

                            : MainAxisAlignment.start,

                        crossAxisAlignment:
                        CrossAxisAlignment.end,

                        children: [

                          // AVATAR

                          if (!isMe)
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundImage: message['avatar_url'] != null
                                      ? NetworkImage(message['avatar_url'])
                                      : null,
                                  child: message['avatar_url'] == null
                                      ? const Icon(Icons.person, size: 18)
                                      : null,
                                ),
                                StreamBuilder(
                                  stream: supabase
                                      .from('profiles')
                                      .stream(primaryKey: ['id'])
                                      .eq('id', message['sender_id']),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                                      final user = snapshot.data!.first;
                                      final lastSeenStr = user['last_seen'];
                                      if (lastSeenStr != null) {
                                        final lastSeen = DateTime.parse(lastSeenStr).toUtc();
                                        final now = DateTime.now().toUtc();
                                        final diff = now.difference(lastSeen);
                                        if (diff.inMinutes < 5) {
                                          return Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              height: 10,
                                              width: 10,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 1.5),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),

                          if (!isMe)

                            const SizedBox(width: 8),

                          // MESSAGE BUBBLE

                          Flexible(

                            child: Container(

                              padding:
                              const EdgeInsets.all(12),

                              decoration:
                              BoxDecoration(

                                color:

                                isMe

                                    ? Colors.green[300]

                                    : Colors.white,

                                borderRadius:
                                BorderRadius.only(

                                  topLeft:
                                  const Radius.circular(18),

                                  topRight:
                                  const Radius.circular(18),

                                  bottomLeft:
                                  Radius.circular(
                                    isMe ? 18 : 0,
                                  ),

                                  bottomRight:
                                  Radius.circular(
                                    isMe ? 0 : 18,
                                  ),
                                ),

                                boxShadow: [

                                  BoxShadow(

                                    color:
                                    Colors.black
                                        .withValues(alpha: 0.05),

                                    blurRadius: 5,

                                    offset:
                                    const Offset(0, 2),
                                  ),
                                ],
                              ),

                              child: Column(

                                crossAxisAlignment:

                                isMe

                                    ? CrossAxisAlignment.end

                                    : CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    message['username'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  // IMAGE

                                  if (message['media_url'] != null &&
                                      message['media_type']
                                          == 'image')

                                    Padding(

                                      padding:
                                      const EdgeInsets.only(
                                        bottom: 8,
                                      ),

                                      child: ClipRRect(

                                        borderRadius:
                                        BorderRadius.circular(12),

                                        child: Image.network(

                                          message['media_url'],

                                          height: 220,

                                          width: 220,

                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),

                                  // TEXT

                                  if (message['message'] != null &&
                                      message['message']
                                          .toString()
                                          .isNotEmpty)

                                    Text(

                                      message['message'],

                                      style:
                                      const TextStyle(
                                        fontSize: 16,
                                      ),
                                    ),

                                  const SizedBox(height: 5),

                                  // TIME

                                  Text(

                                    time,

                                    style:
                                    TextStyle(

                                      fontSize: 11,

                                      color:
                                      Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // INPUT BAR

          SafeArea(

            child: Container(

              padding:
              const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),

              color: Colors.white,

              child: Row(

                children: [

                  // ATTACH BUTTON

                  IconButton(

                    onPressed: pickMedia,

                    icon: const Icon(
                      Icons.attach_file,
                    ),
                  ),

                  // TEXT INPUT

                  Expanded(

                    child: TextField(
                      controller:
                      messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) =>
                          sendMessage(),
                      decoration:
                      InputDecoration(

                        hintText:
                        'Type a message...',

                        filled: true,

                        fillColor:
                        Colors.grey[200],

                        contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),

                        border:
                        OutlineInputBorder(

                          borderRadius:
                          BorderRadius.circular(30),

                          borderSide:
                          BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // SEND BUTTON

                  CircleAvatar(

                    radius: 25,

                    backgroundColor:
                    Colors.green,

                    child: IconButton(

                      onPressed:
                      isSending ? null : sendMessage,

                      icon: isSending 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.white,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}