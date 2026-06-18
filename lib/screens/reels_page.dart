// reels_page.dart
// TikTok-style vertical swipe feed.
// Storage bucket : "Reels"   (already exists, MIME: video/*)
// Table          : reels     (id, user_id, username, avatar_url,
//                             video_url, caption, created_at)
// Table          : reel_likes (id, user_id, reel_id, created_at)
// Table          : reel_comments (id, user_id, reel_id, username,
//                                 comment, created_at)
// All tables have RLS enabled (see SQL at bottom of this file).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final supabase = Supabase.instance.client;
  final PageController _pageController = PageController();

  List<Map<String, dynamic>> _reels = [];
  bool _loading = true;
  int _currentIndex = 0;

  // Keep one controller per visible reel to avoid rebuilding
  final Map<int, VideoPlayerController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _fetchReels();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Fetch reels ───────────────────────────────────────────────────

  Future<void> _fetchReels() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('reels')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _reels = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
      if (_reels.isNotEmpty) _initController(0);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load reels: $e')));
      }
    }
  }

  // ─── Video controller management ──────────────────────────────────

  Future<void> _initController(int index) async {
    if (_controllers.containsKey(index)) return;
    final url = _reels[index]['video_url'] as String?;
    if (url == null) return;

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllers[index] = ctrl;
    await ctrl.initialize();
    ctrl.setLooping(true);
    if (index == _currentIndex) ctrl.play();
    if (mounted) setState(() {});
  }

  void _onPageChanged(int index) {
    // Pause previous
    _controllers[_currentIndex]?.pause();
    _currentIndex = index;
    // Play current
    _initController(index).then((_) {
      _controllers[index]?.play();
      if (mounted) setState(() {});
    });
    // Pre-load next
    if (index + 1 < _reels.length) _initController(index + 1);
    // Dispose controllers far away to save memory
    final toRemove = _controllers.keys
        .where((k) => (k - index).abs() > 2)
        .toList();
    for (final k in toRemove) {
      _controllers[k]?.dispose();
      _controllers.remove(k);
    }
  }

  // ─── Upload reel ───────────────────────────────────────────────────

  Future<void> _uploadReel() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    if (!mounted) return;

    // Caption dialog
    String caption = '';
    await showDialog(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add a caption'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Write something…',
                border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                caption = ctrl.text.trim();
                Navigator.pop(context);
              },
              child: const Text('Post'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    // Show upload progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Uploading reel…'),
        ]),
      ),
    );

    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final storageName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.mp4';
      await supabase.storage
          .from('Reels')
          .upload(storageName, File(file.path));
      final videoUrl =
      supabase.storage.from('Reels').getPublicUrl(storageName);

      await supabase.from('reels').insert({
        'user_id': user.id,
        'username': profile?['username'] ?? 'Unknown',
        'avatar_url': profile?['avatar_url'],
        'video_url': videoUrl,
        'caption': caption.isEmpty ? null : caption,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) Navigator.pop(context); // close progress dialog
      await _fetchReels();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Reels',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: _uploadReel,
            tooltip: 'Post a reel',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchReels,
          ),
        ],
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.white))
          : _reels.isEmpty
          ? _emptyState()
          : PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, i) => _ReelItem(
          reel: _reels[i],
          controller: _controllers[i],
          isActive: i == _currentIndex,
          onTogglePlay: () {
            final c = _controllers[i];
            if (c == null) return;
            c.value.isPlaying ? c.pause() : c.play();
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
          const SizedBox(height: 16),
          const Text('No reels yet',
              style: TextStyle(color: Colors.white54, fontSize: 18)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Post the first reel'),
            onPressed: _uploadReel,
          ),
        ],
      ),
    );
  }
}

// ─── Single reel item ──────────────────────────────────────────────

class _ReelItem extends StatefulWidget {
  final Map<String, dynamic> reel;
  final VideoPlayerController? controller;
  final bool isActive;
  final VoidCallback onTogglePlay;

  const _ReelItem({
    required this.reel,
    required this.controller,
    required this.isActive,
    required this.onTogglePlay,
  });

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  final supabase = Supabase.instance.client;
  bool _liked = false;
  int _likeCount = 0;
  bool _loadingLike = false;

  @override
  void initState() {
    super.initState();
    _fetchLikes();
  }

  int get _reelId => widget.reel['id'] as int;
  String? get _myId => supabase.auth.currentUser?.id;

  Future<void> _fetchLikes() async {
    try {
      final rows = await supabase
          .from('reel_likes')
          .select()
          .eq('reel_id', _reelId);
      final liked = rows.any((r) => r['user_id'] == _myId);
      if (mounted) {
        setState(() {
          _likeCount = rows.length;
          _liked = liked;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_myId == null || _loadingLike) return;
    setState(() => _loadingLike = true);
    try {
      if (_liked) {
        await supabase
            .from('reel_likes')
            .delete()
            .eq('reel_id', _reelId)
            .eq('user_id', _myId!);
        if (mounted) {
        setState(() {
          _liked = false;
          _likeCount = (_likeCount - 1).clamp(0, 999999);
        });
      }
    } else {
      await supabase.from('reel_likes').insert({
        'reel_id': _reelId,
        'user_id': _myId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() {
          _liked = true;
          _likeCount++;
        });
      }
    }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLike = false);
    }
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(reelId: _reelId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final isReady = ctrl != null && ctrl.value.isInitialized;

    return GestureDetector(
      onTap: widget.onTogglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video ──────────────────────────────────────────────────
          isReady
              ? FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          )
              : Container(
              color: Colors.black,
              child: const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white))),

          // ── Gradient overlay ───────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(180),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Play/pause icon flash ──────────────────────────────────
          if (isReady && !ctrl.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow,
                  color: Colors.white54, size: 80),
            ),

          // ── Progress bar ───────────────────────────────────────────
          if (isReady)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                ctrl,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),

          // ── Right-side action buttons ──────────────────────────────
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundImage: widget.reel['avatar_url'] != null
                      ? NetworkImage(widget.reel['avatar_url'])
                      : null,
                  child: widget.reel['avatar_url'] == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(height: 20),
                // Like
                GestureDetector(
                  onTap: _toggleLike,
                  child: Column(children: [
                    Icon(
                      _liked ? Icons.favorite : Icons.favorite_border,
                      color: _liked ? Colors.red : Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text('$_likeCount',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 20),
                // Comments
                GestureDetector(
                  onTap: _openComments,
                  child: const Column(children: [
                    Icon(Icons.comment, color: Colors.white, size: 32),
                    SizedBox(height: 4),
                    Text('Comments',
                        style:
                        TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 20),
                // Share
                GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Share coming soon'))),
                  child: const Column(children: [
                    Icon(Icons.share, color: Colors.white, size: 32),
                    SizedBox(height: 4),
                    Text('Share',
                        style:
                        TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ],
            ),
          ),

          // ── Bottom info ─────────────────────────────────────────────
          Positioned(
            left: 12,
            right: 80,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.reel['username'] ?? 'unknown'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                if (widget.reel['caption'] != null &&
                    (widget.reel['caption'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.reel['caption'],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  DateFormat('MMM d').format(
                      DateTime.parse(widget.reel['created_at']).toLocal()),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Comments bottom sheet ─────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final int reelId;
  const _CommentsSheet({required this.reelId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = supabase
        .from('reel_comments')
        .stream(primaryKey: ['id'])
        .eq('reel_id', widget.reelId)
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _sending = true);
    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      await supabase.from('reel_comments').insert({
        'reel_id': widget.reelId,
        'user_id': user.id,
        'username': profile?['username'] ?? 'Unknown',
        'comment': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Comments',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            // Comments list
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _stream,
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final comments = snap.data!;
                  if (comments.isEmpty) {
                    return const Center(
                        child: Text('No comments yet — be first!',
                            style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: comments.length,
                    itemBuilder: (_, i) {
                      final c = comments[i];
                      final time = DateFormat('hh:mm a').format(
                          DateTime.parse(c['created_at']).toLocal());
                      return ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.person, size: 18)),
                        title: Text(c['username'] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        subtitle: Text(c['comment'] ?? ''),
                        trailing: Text(time,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      );
                    },
                  );
                },
              ),
            ),
            // Input
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                    top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: InputDecoration(
                          hintText: 'Add a comment…',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: _sending
                          ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : IconButton(
                        icon: const Icon(Icons.send,
                            color: Colors.white, size: 20),
                        onPressed: _postComment,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}