import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'upload_reel_page.dart';
import 'user_profile_page.dart';
import 'package:share_plus/share_plus.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UploadReelPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: supabase
            .from('reels')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reels = snapshot.data!;

          if (reels.isEmpty) {
            return const Center(child: Text('No reels yet'));
          }

          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            itemBuilder: (context, index) {
              return ReelVideoCard(reel: reels[index]);
            },
          );
        },
      ),
    );
  }
}

class ReelVideoCard extends StatefulWidget {
  final dynamic reel;

  const ReelVideoCard({super.key, required this.reel});

  @override
  State<ReelVideoCard> createState() => _ReelVideoCardState();
}

class _ReelVideoCardState extends State<ReelVideoCard> {
  final supabase = Supabase.instance.client;
  late VideoPlayerController controller;
  final commentController = TextEditingController();
  bool isLiked = false;
  int likeCount = 0;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.reel['video_url']),
    )..initialize().then((_) {
      setState(() {});
      controller.play();
      controller.setLooping(true);
    });
    checkIfLiked();
    getLikeCount();
  }

  @override
  void dispose() {
    controller.dispose();
    commentController.dispose();
    super.dispose();
  }

  Future<void> checkIfLiked() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final result = await supabase
        .from('reel_likes')
        .select()
        .eq('reel_id', widget.reel['id'])
        .eq('user_id', user.id)
        .maybeSingle();

    if (mounted) {
      setState(() {
        isLiked = result != null;
      });
    }
  }

  Future<void> getLikeCount() async {
    final result = await supabase
        .from('reel_likes')
        .select()
        .eq('reel_id', widget.reel['id']);

    if (mounted) {
      setState(() {
        likeCount = result.length;
      });
    }
  }

  Future<void> toggleLike() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (isLiked) {
      await supabase
          .from('reel_likes')
          .delete()
          .eq('reel_id', widget.reel['id'])
          .eq('user_id', user.id);
      setState(() {
        isLiked = false;
        likeCount--;
      });
    } else {
      await supabase.from('reel_likes').insert({
        'reel_id': widget.reel['id'],
        'user_id': user.id,
      });
      setState(() {
        isLiked = true;
        likeCount++;
      });
    }
  }

  Future<void> postComment() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (commentController.text.trim().isEmpty) return;

    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    await supabase.from('reel_comments').insert({
      'reel_id': widget.reel['id'],
      'user_id': user.id,
      'username': profile['username'],
      'comment': commentController.text.trim(),
    });

    commentController.clear();
  }

  void showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Comments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder(
                stream: supabase
                    .from('reel_comments')
                    .stream(primaryKey: ['id'])
                    .order('created_at', ascending: true),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allComments = snapshot.data!;
                  final comments = allComments
                      .where((c) => c['reel_id'] == widget.reel['id'])
                      .toList();

                  if (comments.isEmpty) {
                    return const Center(
                      child: Text('No comments yet. Be first!'),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          comment['username'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(comment['comment'] ?? ''),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 10,
                left: 10,
                right: 10,
                top: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: postComment,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Video
        Positioned.fill(
          child: controller.value.isInitialized
              ? GestureDetector(
            onTap: () {
              if (controller.value.isPlaying) {
                controller.pause();
              } else {
                controller.play();
              }
            },
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          )
              : const Center(child: CircularProgressIndicator()),
        ),

        // Right side actions
        Positioned(
          right: 10,
          bottom: 120,
          child: Column(
            children: [
              // Like button
              GestureDetector(
                onTap: toggleLike,
                child: Column(
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.white,
                      size: 35,
                    ),
                    Text(
                      '$likeCount',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Comment button
              GestureDetector(
                onTap: showComments,
                child: const Column(
                  children: [
                    Icon(
                      Icons.comment,
                      color: Colors.white,
                      size: 35,
                    ),
                    Text(
                      'Comments',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Share button
              GestureDetector(
                onTap: () {
                  Share.share('Check out this reel on KU Konnect: ${widget.reel['video_url']}');
                },
                child: const Column(
                  children: [
                    Icon(
                      Icons.share,
                      color: Colors.white,
                      size: 35,
                    ),
                    Text(
                      'Share',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom info
        Positioned(
          bottom: 40,
          left: 20,
          right: 70,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  final profile = await supabase
                      .from('profiles')
                      .select()
                      .eq('id', widget.reel['user_id'])
                      .single();
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfilePage(userData: profile),
                    ),
                  );
                },
                child: Text(
                  '@${widget.reel['username']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.reel['caption'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}