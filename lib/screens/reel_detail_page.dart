// reel_detail_page.dart
// Full-screen single reel — opened when tapping a reel from a profile
// or any other entry point outside the main feed.
// It plays the video, shows likes + comments, and lets the user
// like/comment just like in the feed.

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ReelDetailPage extends StatefulWidget {
  final Map<String, dynamic> reel;

  const ReelDetailPage({super.key, required this.reel});

  @override
  State<ReelDetailPage> createState() => _ReelDetailPageState();
}

class _ReelDetailPageState extends State<ReelDetailPage> {
  final supabase = Supabase.instance.client;

  VideoPlayerController? _ctrl;
  bool _liked = false;
  int _likeCount = 0;
  bool _loadingLike = false;
  bool _showComments = false;

  int get _reelId => widget.reel['id'] as int;
  String? get _myId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _fetchLikes();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // ─── Video ─────────────────────────────────────────────────────────

  Future<void> _initVideo() async {
    final url = widget.reel['video_url'] as String?;
    if (url == null) return;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    await ctrl.initialize();
    ctrl.setLooping(true);
    ctrl.play();
    if (mounted) setState(() => _ctrl = ctrl);
  }

  // ─── Likes ─────────────────────────────────────────────────────────

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
        setState(() {
          _liked = false;
          _likeCount = (_likeCount - 1).clamp(0, 999999);
        });
      } else {
        await supabase.from('reel_likes').insert({
          'reel_id': _reelId,
          'user_id': _myId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        setState(() {
          _liked = true;
          _likeCount++;
        });
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

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isReady = _ctrl != null && _ctrl!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '@${widget.reel['username'] ?? ''}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => Share.share(
                'Check out this reel on KU Konnect!\n${widget.reel['video_url'] ?? ''}'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video ──────────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              if (_ctrl == null) return;
              _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
              setState(() {});
            },
            child: isReady
                ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.size.width,
                height: _ctrl!.value.size.height,
                child: VideoPlayer(_ctrl!),
              ),
            )
                : const Center(
                child:
                CircularProgressIndicator(color: Colors.white)),
          ),

          // ── Gradient ───────────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(200),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Pause icon ─────────────────────────────────────────────
          if (isReady && !_ctrl!.value.isPlaying)
            const Center(
                child: Icon(Icons.play_arrow,
                    color: Colors.white54, size: 80)),

          // ── Progress bar ───────────────────────────────────────────
          if (isReady)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _ctrl!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),

          // ── Right-side actions ─────────────────────────────────────
          Positioned(
            right: 12,
            bottom: 120,
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
                // Like button
                GestureDetector(
                  onTap: _toggleLike,
                  child: Column(
                    children: [
                      _loadingLike
                          ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : Icon(
                        _liked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color:
                        _liked ? Colors.red : Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 4),
                      Text('$_likeCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Comments button
                GestureDetector(
                  onTap: () =>
                      setState(() => _showComments = !_showComments),
                  child: const Column(
                    children: [
                      Icon(Icons.comment, color: Colors.white, size: 32),
                      SizedBox(height: 4),
                      Text('Comments',
                          style: TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Share
                GestureDetector(
                  onTap: () => Share.share(widget.reel['video_url'] ?? ''),
                  child: const Column(
                    children: [
                      Icon(Icons.share, color: Colors.white, size: 32),
                      SizedBox(height: 4),
                      Text('Share',
                          style: TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Caption & date ─────────────────────────────────────────
          Positioned(
            left: 12,
            right: 80,
            bottom: 50,
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  DateFormat('MMM d, yyyy').format(
                      DateTime.parse(widget.reel['created_at'])
                          .toLocal()),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Inline comments panel ──────────────────────────────────
          if (_showComments)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.55,
              child: _CommentsPanel(
                reelId: _reelId,
                onClose: () => setState(() => _showComments = false),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Inline comments panel ─────────────────────────────────────────

class _CommentsPanel extends StatefulWidget {
  final int reelId;
  final VoidCallback onClose;

  const _CommentsPanel(
      {required this.reelId, required this.onClose});

  @override
  State<_CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<_CommentsPanel> {
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text('Comments',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
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
                      child: Text('No comments yet',
                          style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
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
                  bottom:
                  MediaQuery.of(context).viewInsets.bottom + 8,
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
    );
  }
}