// chat_page.dart
// Group chat — WhatsApp-style keyboard / attachment panel.
// NO video call button here (that lives in dm_page.dart only).
// Storage bucket used: "Chat Media"  (already exists in your Supabase project)
// Table used: messages  (already exists)
// New columns needed on `messages`:
//   file_url text, file_name text
//   (image/audio/video columns already exist as media_url + media_type)

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class ChatPage extends StatefulWidget {
  final VoidCallback? onBack;
  const ChatPage({super.key, this.onBack});

  @override
  State<ChatPage> createState() => _ChatPageState();
}


class _ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver {

  Future<void> _recordVoiceNote() async {
    await _startRecording();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Recording Voice Note'),
        content: const Text(
          'Tap Stop when you are finished recording.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _cancelRecording();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _stopAndSendRecording();
            },
            child: const Text('Stop & Send'),
          ),
        ],
      ),
    );
  }

  final supabase = Supabase.instance.client;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool isSending = false;
  bool isRecording = false;
  bool showAttachPanel = false;

  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  String? _recordingPath;
  String? _currentlyPlayingUrl;

  // Preview state for selected media before sending
  File? _pendingFile;
  String? _pendingMediaType; // 'image' | 'video' | 'audio' | 'file'
  String? _pendingFileName;

  late final Stream<List<Map<String, dynamic>>> messagesStream;

  final List<String> blockedWords = [
    'politics', 'siasa', 'warm regards', 'affordable', 'sale',
    'brokies', 'brokie', 'vote', 'betting', 'odds', '1xbet',
    'aviator', 'casino', 'forex signal', 'crypto giveaway',
    'free money', 'earn cash', 'whatsapp group', 'telegram group',
    '.com', '.net', '.org',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    messageController.dispose();
    scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────

  bool _containsBlocked(String msg) {
    final lower = msg.toLowerCase();
    return blockedWords.any(lower.contains);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Media picking ───────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context); // close attach panel
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    setState(() {
      _pendingFile = File(file.path);
      _pendingMediaType = 'image';
      _pendingFileName = null;
      showAttachPanel = false;
    });
  }

  Future<void> _pickVideo(ImageSource source) async {
    Navigator.pop(context);
    final file = await ImagePicker().pickVideo(source: source);
    if (file == null) return;
    setState(() {
      _pendingFile = File(file.path);
      _pendingMediaType = 'video';
      _pendingFileName = null;
      showAttachPanel = false;
    });
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _pendingFile = File(result.files.single.path!);
      _pendingMediaType = 'file';
      _pendingFileName = result.files.single.name;
      showAttachPanel = false;
    });
  }

  // ─── Voice recording ─────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recordingPath =
    '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: _recordingPath!);
    _recordingDuration = Duration.zero;

    _recordingTimer?.cancel();

    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      },
    );

    setState(() => isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _recorder.stop();

    _recordingTimer?.cancel();

    setState(() => isRecording = false);
    if (path == null) return;
    setState(() {
      _pendingFile = File(path);
      _pendingMediaType = 'audio';
      _pendingFileName = null;
    });
    await sendMessage(); // send immediately like WhatsApp
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();

    _recordingTimer?.cancel();

    setState(() {
      isRecording = false;
      _recordingPath = null;
      _recordingDuration = Duration.zero;
    });
  }

  // ─── Send ────────────────────────────────────────────────────────

  Future<void> sendMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final text = messageController.text.trim();
    if (text.isEmpty && _pendingFile == null) return;
    if (isSending) return;

    if (text.isNotEmpty && _containsBlocked(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Advertisements / spam are not allowed.')),
      );
      return;
    }

    setState(() => isSending = true);
    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) throw 'Profile not found. Please update your profile.';

      String? mediaUrl, fileUrl, fileName;

      if (_pendingFile != null) {
        final ext = _pendingMediaType == 'audio'
            ? 'm4a'
            : _pendingMediaType == 'video'
            ? 'mp4'
            : _pendingMediaType == 'image'
            ? 'jpg'
            : _pendingFile!.path.split('.').last;

        final storageName =
            '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage.from('Chat Media').upload(storageName, _pendingFile!);
        final url = supabase.storage.from('Chat Media').getPublicUrl(storageName);

        if (_pendingMediaType == 'file') {
          fileUrl = url;
          fileName = _pendingFileName;
        } else {
          mediaUrl = url;
        }
      }

      final payload = {
        'sender_id': user.id,
        'username': profile['username'],
        'message': text.isEmpty ? '' : text,
        'media_url': mediaUrl,
        'media_type': _pendingMediaType != 'file' ? _pendingMediaType : null,
        'file_url': fileUrl,
        'file_name': fileName,
        'avatar_url': profile['avatar_url'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint('MESSAGE PAYLOAD: $payload');

      await supabase.from('messages').insert(payload);

      messageController.clear();
      setState(() {
        _pendingFile = null;
        _pendingMediaType = null;
        _pendingFileName = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  // ─── Attachment bottom sheet ──────────────────────────────────────

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachItem(Icons.image, Colors.purple, 'Gallery',
                          () => _pickImage(ImageSource.gallery)),
                  _attachItem(Icons.camera_alt, Colors.red, 'Camera',
                          () => _pickImage(ImageSource.camera)),
                  _attachItem(Icons.videocam, Colors.orange, 'Video',
                          () => _pickVideo(ImageSource.gallery)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachItem(Icons.video_camera_back, Colors.blue, 'Rec Video',
                          () => _pickVideo(ImageSource.camera)),
                  _attachItem(Icons.insert_drive_file, Colors.teal, 'File',
                          () => _pickFile()),
                  _attachItem(Icons.location_on, Colors.green, 'Location',
                      _sendLocation),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachItem(
                    Icons.mic,
                    Colors.pink,
                    'Voice Note',
                        () async {
                      Navigator.pop(context);
                      await _recordVoiceNote();
                    },
                  ),
                  _attachItem(Icons.poll, Colors.indigo, 'Poll', _createPoll),
                  _attachItem(Icons.contact_page, Colors.brown, 'Contact',
                      _shareContact),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachItem(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
              radius: 28,
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color, size: 28)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Placeholder features (extend these later) ────────────────────

  void _sendLocation() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location sharing coming soon')),
    );
  }

  void _createPoll() {
    Navigator.pop(context);
    _showPollDialog();
  }

  void _shareContact() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact sharing coming soon')),
    );
  }

  void _showPollDialog() {
    final questionCtrl = TextEditingController();
    final opt1 = TextEditingController(text: 'Option 1');
    final opt2 = TextEditingController(text: 'Option 2');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Poll'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: questionCtrl,
                decoration: const InputDecoration(
                    labelText: 'Question', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: opt1,
                decoration: const InputDecoration(
                    labelText: 'Option 1', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: opt2,
                decoration: const InputDecoration(
                    labelText: 'Option 2', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (questionCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              messageController.text =
              '📊 Poll: ${questionCtrl.text.trim()}\n1. ${opt1.text.trim()}\n2. ${opt2.text.trim()}';
              await sendMessage();
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  // ─── Message bubble ───────────────────────────────────────────────

  Widget _buildBubble(Map<String, dynamic> message, bool isMe) {
    final time = DateFormat('hh:mm a')
        .format(DateTime.parse(message['created_at']).toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _onlineDot(message),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(message['username'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.teal)),
                  // Image
                  if (message['media_type'] == 'image' &&
                      message['media_url'] != null)
                    _mediaImage(message['media_url']),
                  // Video
                  if (message['media_type'] == 'video' &&
                      message['media_url'] != null)
                    _mediaVideo(message['media_url']),
                  // Audio
                  if (message['media_type'] == 'audio' &&
                      message['media_url'] != null)
                    _audioBubble(message['media_url']),
                  // File
                  if (message['file_url'] != null) _fileBubble(message),
                  // Text
                  if (message['message'] != null &&
                      (message['message'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(message['message'],
                          style: const TextStyle(fontSize: 15)),
                    ),
                  const SizedBox(height: 4),
                  Text(time,
                      style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineDot(Map<String, dynamic> message) {
    return StreamBuilder(
      stream: supabase
          .from('profiles')
          .stream(primaryKey: ['id']).eq('id', message['sender_id']),
      builder: (_, snap) {
        bool online = false;
        if (snap.hasData && snap.data!.isNotEmpty) {
          final ls = snap.data!.first['last_seen'];
          if (ls != null) {
            online = DateTime.now()
                .toUtc()
                .difference(DateTime.parse(ls).toUtc())
                .inMinutes <
                5;
          }
        }
        return Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: message['avatar_url'] != null
                ? NetworkImage(message['avatar_url'])
                : null,
            child: message['avatar_url'] == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ]);
      },
    );
  }

  Widget _mediaImage(String url) {
    return GestureDetector(
      onTap: () => _openFullScreen(url, 'image'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(url,
            height: 200, width: 200, fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const SizedBox(
                height: 200,
                width: 200,
                child: Center(child: CircularProgressIndicator()))),
      ),
    );
  }

  Widget _mediaVideo(String url) {
    return GestureDetector(
      onTap: () => _openFullScreen(url, 'video'),
      child: Container(
        height: 180,
        width: 200,
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 60)),
      ),
    );
  }

  Widget _audioBubble(String url) {
    final isPlaying = _currentlyPlayingUrl == url;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 36, color: Colors.teal),
          onPressed: () async {
            if (isPlaying) {
              await _audioPlayer.pause();
              setState(() => _currentlyPlayingUrl = null);
            } else {
              await _audioPlayer.play(UrlSource(url));
              setState(() => _currentlyPlayingUrl = url);
            }
          },
        ),
        const Icon(Icons.graphic_eq, color: Colors.teal),
        const SizedBox(width: 8),
        const Text('Voice message',
            style: TextStyle(fontSize: 13, color: Colors.teal)),
      ],
    );
  }

  Widget _fileBubble(Map<String, dynamic> message) {
    final name = message['file_name'] ?? 'File';
    return GestureDetector(
      onTap: () => Share.share(message['file_url']),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.teal, size: 30),
          const SizedBox(width: 8),
          Flexible(
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.teal,
                      decoration: TextDecoration.underline,
                      fontSize: 14))),
        ],
      ),
    );
  }

  void _openFullScreen(String url, String type) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullScreenMedia(url: url, type: type),
        ));
  }

  // ─── Input bar ────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pending media preview
          if (_pendingFile != null) _buildPendingPreview(),
          // Recording indicator
          if (isRecording) _buildRecordingBar(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                // Attach button
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _showAttachSheet,
                ),
                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24)),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => sendMessage(),
                            maxLines: 5,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        // // Emoji placeholder
                        // IconButton(
                        //     icon: const Icon(Icons.emoji_emotions_outlined,
                        //         color: Colors.grey),
                        //     onPressed: () {}),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send / Mic button
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.green,
                  child: isSending
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingPreview() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          if (_pendingMediaType == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_pendingFile!,
                  height: 80, width: 80, fit: BoxFit.cover),
            )
          else if (_pendingMediaType == 'video')
            Container(
                height: 80,
                width: 80,
                color: Colors.black54,
                child: const Icon(Icons.videocam, color: Colors.white, size: 40))
          else if (_pendingMediaType == 'audio')
              const Row(children: [
                Icon(Icons.mic, color: Colors.teal),
                SizedBox(width: 8),
                Text('Voice message ready')
              ])
            else
              Row(children: [
                const Icon(Icons.insert_drive_file, color: Colors.teal),
                const SizedBox(width: 8),
                Text(_pendingFileName ?? 'File'),
              ]),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () =>
                setState(() {
                  _pendingFile = null;
                  _pendingMediaType = null;
                  _pendingFileName = null;
                }),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      color: Colors.red[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            'Recording... '
                '${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:'
                '${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelRecording,
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Icon(Icons.group, color: Colors.white),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KU Chat',
                    style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Kenyatta University',
                    style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: scrollController,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final isMe = msg['sender_id'] == currentUser?.id;
                    return _buildBubble(msg, isMe);
                  },
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }
}

// ─── Full screen media viewer ──────────────────────────────────────

class _FullScreenMedia extends StatefulWidget {
  final String url;
  final String type;
  const _FullScreenMedia({required this.url, required this.type});

  @override
  State<_FullScreenMedia> createState() => _FullScreenMediaState();
}

class _FullScreenMediaState extends State<_FullScreenMedia> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      )
        ..initialize().then((_) {
          setState(() {
            _isInitialized = true;
          });
        })
        ..addListener(() {
          if (_videoController.value.isPlaying != _isPlaying) {
            setState(() {
              _isPlaying = _videoController.value.isPlaying;
            });
          }
        });
    }
  }

  @override
  void dispose() {
    if (widget.type == 'video') {
      _videoController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => Share.share(widget.url),
          ),
        ],
      ),
      body: Center(
        child: widget.type == 'image'
            ? InteractiveViewer(child: Image.network(widget.url, fit: BoxFit.contain))
            : widget.type == 'video'
                ? _isInitialized
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _videoController.value.aspectRatio,
                            child: VideoPlayer(_videoController),
                          ),
                          if (!_isPlaying)
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline,
                                  size: 80, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  if (_videoController.value.isPlaying) {
                                    _videoController.pause();
                                  } else {
                                    _videoController.play();
                                  }
                                });
                              },
                            ),
                        ],
                      )
                    : const CircularProgressIndicator()
                : const Text('Unknown media type',
                    style: TextStyle(color: Colors.white)),
      ),
    );
  }