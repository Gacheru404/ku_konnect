import 'dart:io';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';

import 'package:image_picker/image_picker.dart';

import 'package:record/record.dart';

import 'package:audioplayers/audioplayers.dart';

import 'package:video_player/video_player.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class DMPage extends StatefulWidget {
  final String receiverId;

  final String username;

  const DMPage({
    super.key,
    required this.receiverId,
    required this.username,
  });

  @override
  State<DMPage> createState() =>
      _DMPageState();
}

class _DMPageState
    extends State<DMPage> {

  final supabase =
      Supabase.instance.client;

  final messageController =
  TextEditingController();

  final scrollController =
  ScrollController();

  final AudioRecorder recorder =
  AudioRecorder();

  final AudioPlayer audioPlayer =
  AudioPlayer();

  bool isTyping = false;

  bool isRecording = false;

  bool isUploading = false;

  String? recordingPath;

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

  @override
  void initState() {

    super.initState();

    markMessagesAsRead();
  }

  @override
  void dispose() {

    messageController.dispose();

    scrollController.dispose();

    recorder.dispose();

    audioPlayer.dispose();

    super.dispose();
  }

  Future<void> markMessagesAsRead() async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    await supabase
        .from('direct_messages')
        .update({
      'is_read': true,
    })
        .eq(
      'sender_id',
      widget.receiverId,
    )
        .eq(
      'receiver_id',
      user.id,
    )
        .eq(
      'is_read',
      false,
    );
  }

  Future<void> updateTypingStatus(
      bool typing) async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    final existing = await supabase
        .from('typing_status')
        .select()
        .eq('user_id', user.id)
        .eq(
      'receiver_id',
      widget.receiverId,
    );

    if (existing.isEmpty) {

      await supabase
          .from('typing_status')
          .insert({

        'user_id': user.id,

        'receiver_id':
        widget.receiverId,

        'is_typing': typing,
      });

    } else {

      await supabase
          .from('typing_status')
          .update({

        'is_typing': typing,

        'updated_at':
        DateTime.now()
            .toIso8601String(),
      })
          .eq('user_id', user.id)
          .eq(
        'receiver_id',
        widget.receiverId,
      );
    }
  }

  bool containsBlockedContent(
      String message) {

    final lowerMessage =
    message.toLowerCase();

    return blockedWords.any((word) {

      return lowerMessage.contains(word);
    });
  }

  Future<void> sendMessage() async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    final message =
    messageController.text.trim();

    if (message.isEmpty) return;

    if (containsBlockedContent(
        message)) {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(

          content: Text(
            'Advertisements/spam are not allowed.',
          ),
        ),
      );

      return;
    }

    await supabase
        .from('direct_messages')
        .insert({

      'sender_id': user.id,

      'receiver_id':
      widget.receiverId,

      'message': message,

      'is_read': false,
    });

    messageController.clear();

    isTyping = false;

    await updateTypingStatus(
      false,
    );
  }

  Future<void> startRecording() async {

    final hasPermission =
    await recorder.hasPermission();

    if (!hasPermission) return;

    final dir =
    await getTemporaryDirectory();

    recordingPath =
    '${dir.path}/voice_message.m4a';

    await recorder.start(

      const RecordConfig(),

      path: recordingPath!,
    );

    setState(() {

      isRecording = true;
    });
  }

  Future<void> stopRecording() async {

    final path =
    await recorder.stop();

    setState(() {

      isRecording = false;
    });

    if (path == null) return;

    await uploadAudio(path);
  }

  Future<void> uploadAudio(
      String path) async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    setState(() {

      isUploading = true;
    });

    try {

      final file =
      File(path);

      final fileName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.m4a';

      await supabase.storage
          .from('Chat Media')
          .upload(
        fileName,
        file,
      );

      final audioUrl = supabase
          .storage
          .from('Chat Media')
          .getPublicUrl(fileName);

      await supabase
          .from('direct_messages')
          .insert({

        'sender_id': user.id,

        'receiver_id':
        widget.receiverId,

        'audio_url': audioUrl,

        'is_read': false,
      });

    } finally {

      setState(() {

        isUploading = false;
      });
    }
  }

  Future<void> pickAndUploadImage() async {

    final picker = ImagePicker();

    final pickedFile =
    await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    setState(() {

      isUploading = true;
    });

    try {

      final file =
      File(pickedFile.path);

      final fileName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('Chat Media')
          .upload(
        fileName,
        file,
      );

      final imageUrl = supabase
          .storage
          .from('Chat Media')
          .getPublicUrl(fileName);

      await supabase
          .from('direct_messages')
          .insert({

        'sender_id': user.id,

        'receiver_id':
        widget.receiverId,

        'image_url': imageUrl,

        'is_read': false,
      });

    } finally {

      setState(() {

        isUploading = false;
      });
    }
  }

  Future<void> pickAndUploadVideo() async {

    final picker = ImagePicker();

    final pickedFile =
    await picker.pickVideo(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) return;

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    setState(() {

      isUploading = true;
    });

    try {

      final file =
      File(pickedFile.path);

      final fileName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.mp4';

      await supabase.storage
          .from('Chat Media')
          .upload(
        fileName,
        file,
      );

      final videoUrl = supabase
          .storage
          .from('Chat Media')
          .getPublicUrl(fileName);

      await supabase
          .from('direct_messages')
          .insert({

        'sender_id': user.id,

        'receiver_id':
        widget.receiverId,

        'video_url': videoUrl,

        'is_read': false,
      });

    } finally {

      setState(() {

        isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    final currentUser =
        supabase.auth.currentUser;

    return Scaffold(

      appBar: AppBar(

        title: StreamBuilder(

          stream: supabase
              .from('typing_status')
              .stream(
            primaryKey: ['id'],
          ),

          builder: (context, snapshot) {

            bool typing = false;

            if (snapshot.hasData) {

              final data =
              snapshot.data!;

              typing = data.any((item) {

                return item['user_id']
                    == widget.receiverId &&

                    item['receiver_id']
                        == currentUser?.id &&

                    item['is_typing']
                        == true;
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(widget.username),
                    const SizedBox(width: 8),
                    StreamBuilder(
                      stream: supabase
                          .from('profiles')
                          .stream(primaryKey: ['id'])
                          .eq('id', widget.receiverId),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final user = snapshot.data!.first;
                          final lastSeenStr = user['last_seen'];
                          if (lastSeenStr != null) {
                            final lastSeen = DateTime.parse(lastSeenStr).toUtc();
                            final now = DateTime.now().toUtc();
                            final diff = now.difference(lastSeen);
                            if (diff.inMinutes < 5) {
                              return Container(
                                height: 8,
                                width: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
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
                if (typing)
                  const Text(
                    'Typing...',
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  ),
              ],
            );
          },
        ),
      ),

      body: Column(

        children: [

          if (isUploading)

            const LinearProgressIndicator(),

          Expanded(

            child: StreamBuilder(

              stream: supabase
                  .from('direct_messages')
                  .stream(
                primaryKey: ['id'],
              )
                  .order(
                'created_at',
                ascending: true,
              ),

              builder:
                  (context, snapshot) {

                if (!snapshot.hasData) {

                  return const Center(
                    child:
                    CircularProgressIndicator(),
                  );
                }

                final allMessages =
                snapshot.data!;

                final messages =
                allMessages.where((msg) {

                  return (

                      (msg['sender_id'] ==
                          currentUser?.id &&

                          msg['receiver_id'] ==
                              widget.receiverId)

                          ||

                          (msg['sender_id'] ==
                              widget.receiverId &&

                              msg['receiver_id'] ==
                                  currentUser?.id)

                  );

                }).toList();

                WidgetsBinding.instance
                    .addPostFrameCallback((_) {

                  markMessagesAsRead();

                  if (scrollController
                      .hasClients) {

                    scrollController.jumpTo(

                      scrollController
                          .position
                          .maxScrollExtent,
                    );
                  }
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
                        message['sender_id']
                            == currentUser?.id;

                    final isRead =
                        message['is_read']
                            ?? false;

                    final time =
                    DateFormat(
                      'hh:mm a',
                    ).format(

                      DateTime.parse(
                        message['created_at'],
                      ),
                    );

                    return Align(

                      alignment:

                      isMe

                          ? Alignment.centerRight

                          : Alignment.centerLeft,

                      child: Container(

                        margin:
                        const EdgeInsets.symmetric(
                          vertical: 5,
                        ),

                        padding:
                        const EdgeInsets.all(12),

                        constraints:
                        const BoxConstraints(
                          maxWidth: 300,
                        ),

                        decoration:
                        BoxDecoration(

                          color:

                          isMe

                              ? Colors.green[300]

                              : Colors.grey[300],

                          borderRadius:
                          BorderRadius.circular(15),
                        ),

                        child: Column(

                          crossAxisAlignment:

                          isMe

                              ? CrossAxisAlignment.end

                              : CrossAxisAlignment.start,

                          children: [

                            if (message['message']
                                !=
                                null)

                              Text(
                                message['message'],
                              ),

                            if (message['image_url']
                                !=
                                null)

                              Padding(

                                padding:
                                const EdgeInsets.only(
                                  top: 8,
                                ),

                                child: ClipRRect(

                                  borderRadius:
                                  BorderRadius.circular(10),

                                  child: Image.network(

                                    message['image_url'],

                                    width: 220,

                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),

                            if (message['video_url']
                                !=
                                null)

                              Padding(

                                padding:
                                const EdgeInsets.only(
                                  top: 8,
                                ),

                                child: SizedBox(

                                  height: 220,

                                  width: 220,

                                  child:
                                  VideoPlayerWidget(

                                    videoUrl:
                                    message['video_url'],
                                  ),
                                ),
                              ),

                            if (message['audio_url']
                                !=
                                null)

                              IconButton(

                                onPressed: () async {

                                  await audioPlayer
                                      .play(

                                    UrlSource(
                                      message['audio_url'],
                                    ),
                                  );
                                },

                                icon: const Icon(
                                  Icons.play_arrow,
                                ),
                              ),

                            const SizedBox(
                              height: 5,
                            ),

                            Row(

                              mainAxisSize:
                              MainAxisSize.min,

                              children: [

                                Text(

                                  time,

                                  style:
                                  const TextStyle(
                                    fontSize: 11,
                                  ),
                                ),

                                const SizedBox(
                                  width: 5,
                                ),

                                if (isMe)

                                  Icon(

                                    isRead

                                        ? Icons.done_all

                                        : Icons.done,

                                    size: 16,

                                    color:

                                    isRead

                                        ? Colors.blue

                                        : Colors.black54,
                                  ),
                              ],
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

            padding:
            const EdgeInsets.all(10),

            child: Row(

              children: [

                IconButton(

                  onPressed:
                  pickAndUploadImage,

                  icon: const Icon(
                    Icons.image,
                  ),
                ),

                IconButton(

                  onPressed:
                  pickAndUploadVideo,

                  icon: const Icon(
                    Icons.videocam,
                  ),
                ),

                IconButton(

                  onPressed: () async {

                    if (isRecording) {

                      await stopRecording();

                    } else {

                      await startRecording();
                    }
                  },

                  icon: Icon(

                    isRecording

                        ? Icons.stop

                        : Icons.mic,
                  ),
                ),

                Expanded(
                  child: TextField(
                    controller:
                    messageController,
                    textInputAction:
                    TextInputAction.send,
                    onSubmitted: (_) =>
                        sendMessage(),
                    onChanged:
                        (value) async {

                      if (value.isNotEmpty &&
                          !isTyping) {

                        isTyping = true;

                        await updateTypingStatus(
                          true,
                        );

                      } else if (
                      value.isEmpty &&
                          isTyping) {

                        isTyping = false;

                        await updateTypingStatus(
                          false,
                        );
                      }
                    },

                    decoration:
                    InputDecoration(

                      hintText:
                      'Type a message...',

                      border:
                      OutlineInputBorder(

                        borderRadius:
                        BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                CircleAvatar(

                  child: IconButton(

                    onPressed:
                    sendMessage,

                    icon: const Icon(
                      Icons.send,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerWidget
    extends StatefulWidget {

  final String videoUrl;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
  });

  @override
  State<VideoPlayerWidget>
  createState() =>
      _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState
    extends State<VideoPlayerWidget> {

  late VideoPlayerController
  controller;

  @override
  void initState() {

    super.initState();

    controller =
    VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    )

      ..initialize().then((_) {

        if (mounted) {

          setState(() {});
        }
      });
  }

  @override
  void dispose() {

    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    if (!controller.value.isInitialized) {

      return const Center(
        child:
        CircularProgressIndicator(),
      );
    }

    return GestureDetector(

      onTap: () {

        if (controller.value.isPlaying) {

          controller.pause();

        } else {

          controller.play();
        }
      },

      child: ClipRRect(

        borderRadius:
        BorderRadius.circular(12),

        child: AspectRatio(

          aspectRatio:
          controller.value.aspectRatio,

          child: VideoPlayer(
            controller,
          ),
        ),
      ),
    );
  }
}