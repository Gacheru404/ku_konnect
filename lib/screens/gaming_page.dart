// gaming_page.dart
// Gaming chat — same WhatsApp-style keyboard as chat_page.dart
// but uses the `gaming_chat` table and has a game-code sharing feature.
// Storage bucket: "Chat Media"
// Tables: gaming_chat, game_codes, profiles
// gaming_chat columns expected:
//   id, sender_id, username, avatar_url, message, media_url,
//   media_type, file_url, file_name, created_at
// game_codes columns expected:
//   id, user_id, username, game_name, code, platform, created_at

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class GamingPage extends StatefulWidget {
  const GamingPage({super.key});

  @override
  State<GamingPage> createState() => _GamingPageState();
}

class _GamingPageState extends State<GamingPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool isSending = false;
  bool isRecording = false;
  String? _currentlyPlayingUrl;

  File? _pendingFile;
  String? _pendingMediaType;
  String? _pendingFileName;

  late TabController _tabController;

  late final Stream<List<Map<String, dynamic>>> _chatStream;
  late final Stream<List<Map<String, dynamic>>> _codesStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _chatStream = supabase
        .from('gaming_chat')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
    _codesStream = supabase
        .from('game_codes')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
    messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    messageController.dispose();
    scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String get _myId => supabase.auth.currentUser!.id;

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

  // ─── Media picking ─────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final file =
    await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    setState(() {
      _pendingFile = File(file.path);
      _pendingMediaType = 'image';
      _pendingFileName = null;
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
    });
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _pendingFile = File(result.files.single.path!);
      _pendingMediaType = 'file';
      _pendingFileName = result.files.single.name;
    });
  }

  // ─── Voice recording ──────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() => isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _recorder.stop();
    setState(() => isRecording = false);
    if (path == null) return;
    setState(() {
      _pendingFile = File(path);
      _pendingMediaType = 'audio';
    });
    await _sendMessage();
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();
    setState(() => isRecording = false);
  }

  // ─── Send message ─────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty && _pendingFile == null) return;
    if (isSending) return;
    setState(() => isSending = true);

    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', _myId)
          .maybeSingle();
      if (profile == null) throw 'Profile not found';

      String? mediaUrl, fileUrl, fileName;

      if (_pendingFile != null) {
        final ext = _pendingMediaType == 'audio'
            ? 'm4a'
            : _pendingMediaType == 'video'
            ? 'mp4'
            : _pendingMediaType == 'image'
            ? 'jpg'
            : _pendingFile!.path.split('.').last;
        final name = '$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage
            .from('Chat Media')
            .upload(name, _pendingFile!);
        final url =
        supabase.storage.from('Chat Media').getPublicUrl(name);
        if (_pendingMediaType == 'file') {
          fileUrl = url;
          fileName = _pendingFileName;
        } else {
          mediaUrl = url;
        }
      }

      await supabase.from('gaming_chat').insert({
        'sender_id': _myId,
        'username': profile['username'],
        'avatar_url': profile['avatar_url'],
        'message': text.isEmpty ? null : text,
        'media_url': mediaUrl,
        'media_type': _pendingMediaType != 'file' ? _pendingMediaType : null,
        'file_url': fileUrl,
        'file_name': fileName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  // ─── Share game code ──────────────────────────────────────────────

  void _showShareGameCode() {
    final gameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final platformCtrl = TextEditingController(text: 'PC');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Share Game Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: gameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Game name',
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Friend/room code',
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: platformCtrl,
                decoration: const InputDecoration(
                    labelText: 'Platform (PC / PS5 / Mobile…)',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (gameCtrl.text.trim().isEmpty ||
                  codeCtrl.text.trim().isEmpty) {return;}
              Navigator.pop(context);
              try {
                final profile = await supabase
                    .from('profiles')
                    .select()
                    .eq('id', _myId)
                    .maybeSingle();
                await supabase.from('game_codes').insert({
                  'user_id': _myId,
                  'username': profile?['username'] ?? 'Unknown',
                  'game_name': gameCtrl.text.trim(),
                  'code': codeCtrl.text.trim(),
                  'platform': platformCtrl.text.trim(),
                  'created_at':
                  DateTime.now().toUtc().toIso8601String(),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code shared!')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  // ─── Attachment sheet ──────────────────────────────────────────────

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
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
                  _attachItem(Icons.video_camera_back, Colors.blue,
                      'Rec Video',
                          () => _pickVideo(ImageSource.camera)),
                  _attachItem(Icons.insert_drive_file, Colors.teal, 'File',
                          () => _pickFile()),
                  _attachItem(Icons.gamepad, Colors.green, 'Game Code',
                          () {
                        Navigator.pop(context);
                        _showShareGameCode();
                      }),
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
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Message bubble ────────────────────────────────────────────────

  Widget _buildBubble(Map<String, dynamic> msg) {
    final isMe = msg['sender_id'] == _myId;
    final time = DateFormat('hh:mm a')
        .format(DateTime.parse(msg['created_at']).toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage: msg['avatar_url'] != null
                  ? NetworkImage(msg['avatar_url'])
                  : null,
              child: msg['avatar_url'] == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFF1E3A5F)
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(msg['username'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.greenAccent)),
                  if (msg['media_type'] == 'image' &&
                      msg['media_url'] != null)
                    _mediaImage(msg['media_url']),
                  if (msg['media_type'] == 'video' &&
                      msg['media_url'] != null)
                    _mediaVideo(msg['media_url']),
                  if (msg['media_type'] == 'audio' &&
                      msg['media_url'] != null)
                    _audioBubble(msg['media_url']),
                  if (msg['file_url'] != null) _fileBubble(msg),
                  if (msg['message'] != null &&
                      (msg['message'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(msg['message'],
                          style: const TextStyle(
                              fontSize: 15, color: Colors.white)),
                    ),
                  const SizedBox(height: 4),
                  Text(time,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaImage(String url) => GestureDetector(
    onTap: () => _openFullScreen(url, 'image'),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(url,
          height: 200, width: 200, fit: BoxFit.cover),
    ),
  );

  Widget _mediaVideo(String url) => GestureDetector(
    onTap: () => _openFullScreen(url, 'video'),
    child: Container(
      height: 180,
      width: 200,
      decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10)),
      child: const Center(
          child: Icon(Icons.play_circle_fill,
              color: Colors.greenAccent, size: 60)),
    ),
  );

  Widget _audioBubble(String url) {
    final isPlaying = _currentlyPlayingUrl == url;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 36, color: Colors.greenAccent),
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
        const Icon(Icons.graphic_eq, color: Colors.greenAccent),
        const SizedBox(width: 8),
        const Text('Voice note',
            style: TextStyle(fontSize: 13, color: Colors.greenAccent)),
      ],
    );
  }

  Widget _fileBubble(Map<String, dynamic> msg) {
    final name = msg['file_name'] ?? 'File';
    return GestureDetector(
      onTap: () => Share.share(msg['file_url']),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file,
              color: Colors.greenAccent, size: 30),
          const SizedBox(width: 8),
          Flexible(
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.greenAccent,
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
            builder: (_) => _FullScreenMedia(url: url, type: type)));
  }

  // ─── Input bar ─────────────────────────────────────────────────────

  Widget _buildInputBar() {
    final hasContent =
        messageController.text.isNotEmpty || _pendingFile != null;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingFile != null) _buildPendingPreview(),
          if (isRecording) _buildRecordingBar(),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file,
                      color: Colors.greenAccent),
                  onPressed: _showAttachSheet,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(24)),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            maxLines: 5,
                            minLines: 1,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        // IconButton(
                        //     icon: const Icon(Icons.emoji_emotions_outlined,
                        //         color: Colors.white38),
                        //     onPressed: () {}),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onLongPress: _startRecording,
                  onLongPressEnd: (_) => _stopAndSendRecording(),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.greenAccent,
                    child: isSending
                        ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                        : IconButton(
                      icon: Icon(
                          hasContent ? Icons.send : Icons.mic,
                          color: Colors.black),
                      onPressed: hasContent
                          ? _sendMessage
                          : _startRecording,
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

  Widget _buildPendingPreview() {
    return Container(
      color: const Color(0xFF2A2A2A),
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
                child: const Icon(Icons.videocam,
                    color: Colors.white, size: 40))
          else if (_pendingMediaType == 'audio')
              const Row(children: [
                Icon(Icons.mic, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Voice note ready',
                    style: TextStyle(color: Colors.white)),
              ])
            else
              Row(children: [
                const Icon(Icons.insert_drive_file,
                    color: Colors.greenAccent),
                const SizedBox(width: 8),
                Text(_pendingFileName ?? 'File',
                    style: const TextStyle(color: Colors.white)),
              ]),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() {
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
      color: Colors.red[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 8),
          const Text('Recording…',
              style: TextStyle(color: Colors.white)),
          const Spacer(),
          TextButton(
            onPressed: _cancelRecording,
            child: const Text('Cancel',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── Game codes tab ────────────────────────────────────────────────

  Widget _buildCodesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _codesStream,
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final codes = snap.data!;
        if (codes.isEmpty) {
          return const Center(
              child: Text('No game codes yet — share one!',
                  style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: codes.length,
          itemBuilder: (_, i) {
            final c = codes[i];
            return Card(
              color: const Color(0xFF1E3A5F),
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.greenAccent,
                  child: Icon(Icons.gamepad, color: Colors.black),
                ),
                title: Text(c['game_name'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${c['username']} • ${c['platform'] ?? ''}\nCode: ${c['code']}',
                    style: const TextStyle(color: Colors.white70)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, color: Colors.greenAccent),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: c['code'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Code copied!')));
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.sports_esports, color: Colors.greenAccent),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gaming Chat',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('KU Gamers', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Game Codes'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.gamepad, color: Colors.greenAccent),
            onPressed: _showShareGameCode,
            tooltip: 'Share game code',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Chat tab ──────────────────────────────────────────────
          Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _chatStream,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final msgs = snap.data!;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _buildBubble(msgs[i]),
                    );
                  },
                ),
              ),
              _buildInputBar(),
            ],
          ),
          // ── Game codes tab ────────────────────────────────────────
          _buildCodesTab(),
        ],
      ),
    );
  }
}

// ─── Full screen media viewer ──────────────────────────────────────

class _FullScreenMedia extends StatelessWidget {
  final String url;
  final String type;
  const _FullScreenMedia({required this.url, required this.type});

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
            onPressed: () => Share.share(url),
          ),
        ],
      ),
      body: Center(
        child: type == 'image'
            ? InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain))
            : const Text('Open in browser to play video',
            style: TextStyle(color: Colors.white)),
      ),
    );
  }
}