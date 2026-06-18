// dm_page.dart
// 1-on-1 Direct Message — WhatsApp-style.
// Includes: video call button, voice notes, all attachments,
//           read receipts, online indicator, typing indicator.
// Storage bucket: "Chat Media"
// Table: direct_messages
// Columns already present (from your screenshots):
//   id, sender_id, receiver_id, message, created_at,
//   media_url, media_type, is_read, audio_url, image_url,
//   video_url, file_type
// Extra columns to add via Supabase SQL editor:
//   file_url text, file_name text, is_typing bool default false

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class DmPage extends StatefulWidget {
  final String receiverId;
  final String receiverUsername;
  final String? receiverAvatarUrl;

  const DmPage({
    super.key,
    required this.receiverId,
    required this.receiverUsername,
    this.receiverAvatarUrl,
  });

  @override
  State<DmPage> createState() => _DmPageState();
}

class _DmPageState extends State<DmPage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool isSending = false;
  bool isRecording = false;
  String? _currentlyPlayingUrl;

  File? _pendingFile;
  String? _pendingMediaType; // 'image' | 'video' | 'audio' | 'file'
  String? _pendingFileName;

  late Stream<List<Map<String, dynamic>>> _messagesStream;
  late Stream<List<Map<String, dynamic>>> _typingStream;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messagesStream = supabase
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);

    _typingStream = supabase
        .from('typing_status')
        .stream(primaryKey: ['id']);



    messageController.addListener(_onTyping);
    _markAllRead();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    messageController.removeListener(_onTyping);
    messageController.dispose();
    scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _setTyping(false);
    super.dispose();
  }

  // ─── Typing indicator ──────────────────────────────────────────────

  DateTime? _lastTypingSent;

  Future<void> _onTyping() async {
    final text = messageController.text.trim();

    if (text.isEmpty) {
      await _setTyping(false);
      return;
    }

    final now = DateTime.now();

    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!).inSeconds >= 2) {
      _lastTypingSent = now;
      await _setTyping(true);
    }

    setState(() {});
  }

  Future<void> _setTyping(bool typing) async {
    try {
      await supabase.from('typing_status').upsert(
        {
          'user_id': _myId,
          'receiver_id': widget.receiverId,
          'is_typing': typing,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,receiver_id',
      );
    } catch (e) {
      debugPrint('Typing error: $e');
    }
  }

  // ─── Read receipts ──────────────────────────────────────────────

  Future<void> _markAllRead() async {
    try {
      await supabase
          .from('direct_messages')
          .update({'is_read': true})
          .eq('receiver_id', _myId)
          .eq('sender_id', widget.receiverId);
    } catch (_) {}
  }

  // ─── Scroll ────────────────────────────────────────────────────────

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
      _pendingFileName = null;
    });
    await _sendMessage();
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();
    setState(() {
      isRecording = false;
    });
  }

  // ─── Send ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty && _pendingFile == null) return;
    if (isSending) return;

    setState(() => isSending = true);
    await _setTyping(false);

    try {
      String? mediaUrl, fileUrl, fileName;
      String? mediaType;

      if (_pendingFile != null) {
        final ext = _pendingMediaType == 'audio'
            ? 'm4a'
            : _pendingMediaType == 'video'
            ? 'mp4'
            : _pendingMediaType == 'image'
            ? 'jpg'
            : _pendingFile!.path.split('.').last;

        final storageName =
            '$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage
            .from('Chat Media')
            .upload(storageName, _pendingFile!);
        final url =
        supabase.storage.from('Chat Media').getPublicUrl(storageName);

        if (_pendingMediaType == 'file') {
          fileUrl = url;
          fileName = _pendingFileName;
        } else {
          mediaUrl = url;
          mediaType = _pendingMediaType;
        }
      }

      await supabase.from('direct_messages').insert({
        'sender_id': _myId,
        'receiver_id': widget.receiverId,
        'message': text.isEmpty ? null : text,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'file_url': fileUrl,
        'file_name': fileName,
        'is_read': false,
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

  // ─── Attachment sheet ──────────────────────────────────────────────

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
                  style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  _attachItem(Icons.poll, Colors.indigo, 'Poll', _createPoll),
                  _attachItem(Icons.contact_page, Colors.brown, 'Contact',
                      _shareContact),
                  const SizedBox(width: 64),
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

  void _sendLocation() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location sharing coming soon')));
  }

  void _createPoll() {
    Navigator.pop(context);
    final qCtrl = TextEditingController();
    final o1 = TextEditingController(text: 'Option 1');
    final o2 = TextEditingController(text: 'Option 2');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Poll'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: qCtrl,
                decoration: const InputDecoration(
                    labelText: 'Question', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: o1,
                decoration: const InputDecoration(
                    labelText: 'Option 1', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: o2,
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
              if (qCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              messageController.text =
              '📊 Poll: ${qCtrl.text.trim()}\n1. ${o1.text.trim()}\n2. ${o2.text.trim()}';
              await _sendMessage();
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _shareContact() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact sharing coming soon')));
  }

  // ─── Message bubble ────────────────────────────────────────────────

  Widget _buildBubble(Map<String, dynamic> msg) {
    final isMe = msg['sender_id'] == _myId;
    final time = DateFormat('hh:mm a')
        .format(DateTime.parse(msg['created_at']).toLocal());
    final isRead = msg['is_read'] == true;

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
              backgroundImage: widget.receiverAvatarUrl != null
                  ? NetworkImage(widget.receiverAvatarUrl!)
                  : null,
              child: widget.receiverAvatarUrl == null
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
                crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
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
                          style: const TextStyle(fontSize: 15)),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all : Icons.done,
                          size: 14,
                          color: isRead ? Colors.blue : Colors.grey,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaImage(String url) {
    return GestureDetector(
      onTap: () => _openFullScreen(url, 'image'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(url,
            height: 200, width: 200, fit: BoxFit.cover,
            loadingBuilder: (_, child, prog) => prog == null
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
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10)),
        child: const Center(
            child: Icon(Icons.play_circle_fill,
                color: Colors.white, size: 60)),
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

  Widget _fileBubble(Map<String, dynamic> msg) {
    final name = msg['file_name'] ?? 'File';
    return GestureDetector(
      onTap: () => Share.share(msg['file_url']),
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
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _showAttachSheet,
                ),
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
                            onSubmitted: (_) => _sendMessage(),
                            maxLines: 5,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        // IconButton(
                        //     icon: const Icon(Icons.emoji_emotions_outlined,
                        //         color: Colors.grey),
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
                    backgroundColor: Colors.green,
                    child: isSending
                        ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : IconButton(
                      icon: Icon(
                          hasContent ? Icons.send : Icons.mic,
                          color: Colors.white),
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
                child: const Icon(Icons.videocam,
                    color: Colors.white, size: 40))
          else if (_pendingMediaType == 'audio')
              const Row(children: [
                Icon(Icons.mic, color: Colors.teal),
                SizedBox(width: 8),
                Text('Voice message ready'),
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
      color: Colors.red[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 8),
          const Text('Recording…', style: TextStyle(color: Colors.red)),
          const Spacer(),
          TextButton(
            onPressed: _cancelRecording,
            child:
            const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── Online / typing status ────────────────────────────────────────

  Widget _buildOnlineStatus() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('profiles')
          .stream(primaryKey: ['id']).eq('id', widget.receiverId),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const Text('', style: TextStyle(fontSize: 12));
        }
        final profile = snap.data!.first;
        final ls = profile['last_seen'];
        if (ls == null) return const SizedBox.shrink();
        final diff =
        DateTime.now().toUtc().difference(DateTime.parse(ls).toUtc());
        final online = diff.inMinutes < 5;
        return Text(
          online ? 'Online' : 'Last seen ${_formatLastSeen(diff)}',
          style: TextStyle(
              fontSize: 12,
              color: online ? Colors.greenAccent : Colors.white70),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _typingStream,
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final row = snap.data!.first;
        final typing = row['is_typing'] == true;

        final updatedAt =
        DateTime.parse(row['updated_at']).toUtc();

        final fresh =
            DateTime.now().toUtc().difference(updatedAt).inSeconds < 5;

        if (!(typing && fresh)) {
          return const SizedBox.shrink();
        }
        if (!typing) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 4),
          child: Row(
            children: [
              const SizedBox(
                height: 20,
                width: 40,
                child: _TypingDots(),
              ),
              const SizedBox(width: 6),
              Text('${widget.receiverUsername} is typing…',
                  style:
                  const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  String _formatLastSeen(Duration diff) {
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
  }

  // ─── Video call ────────────────────────────────────────────────────

  void _startVideoCall() {
    // Integrate Agora / Jitsi / WebRTC here.
    // For now, navigate to a placeholder or your video call screen.
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Video Call'),
        content: Text('Calling ${widget.receiverUsername}…\n\n'
            'Connect an Agora or Jitsi plugin to enable real video calls.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('End Call')),
        ],
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: widget.receiverAvatarUrl != null
                  ? NetworkImage(widget.receiverAvatarUrl!)
                  : null,
              child: widget.receiverAvatarUrl == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.receiverUsername,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                _buildOnlineStatus(),
              ],
            ),
          ],
        ),
        actions: [
          // Audio call placeholder
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Audio call coming soon'))),
          ),
          // Video call — DMs only
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: _startVideoCall,
          ),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Filter to only this conversation
                final all = snap.data!;
                final msgs = all.where((m) {
                  final s = m['sender_id'];
                  final r = m['receiver_id'];
                  return (s == _myId && r == widget.receiverId) ||
                      (s == widget.receiverId && r == _myId);
                }).toList();

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                if (msgs.isEmpty) {
                  return Center(
                    child: Text('Say hi to ${widget.receiverUsername}! 👋',
                        style:
                        const TextStyle(color: Colors.grey, fontSize: 16)),
                  );
                }

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
          _buildTypingIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }
}

// ─── Animated typing dots ──────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final opacity =
            ((t * 3 - i).clamp(0.0, 1.0) * (1 - (t * 3 - i - 1).clamp(0.0, 1.0)));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: const CircleAvatar(
                    radius: 4, backgroundColor: Colors.grey),
              ),
            );
          }),
        );
      },
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