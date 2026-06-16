import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class ReelDetailPage extends StatefulWidget {
  final dynamic reel;

  const ReelDetailPage({super.key, required this.reel});

  @override
  State<ReelDetailPage> createState() => _ReelDetailPageState();
}

class _ReelDetailPageState extends State<ReelDetailPage> {
  final supabase = Supabase.instance.client;
  final commentController = TextEditingController();
  late VideoPlayerController controller;
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

    setState(() {
      isLiked = result != null;
    });
  }

  Future<void> getLikeCount() async {
    final result = await supabase
        .from('reel_likes')
        .select()
        .eq('reel_id', widget.reel['id']);

    setState(() {
      likeCount = result.length;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video
          Positioned.fill(
            child: controller.value.isInitialized
                ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
                : const Center(child: CircularProgressIndicator()),
          ),

          // Back button
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Right side actions
          Positioned(
            right: 10,
            bottom: 100,
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.white,
                    size: 35,
                  ),
                  onPressed: toggleLike,
                ),
                Text(
                  '$likeCount',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                IconButton(
                  icon: const Icon(
                    Icons.comment,
                    color: Colors.white,
                    size: 35,
                  ),
                  onPressed: () => showComments(context),
                ),
              ],
            ),
          ),

          // Bottom info
          Positioned(
            bottom: 20,
            left: 15,
            right: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.reel['username']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.reel['caption'] ?? '',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showComments(BuildContext context) {
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
                    .eq('reel_id', widget.reel['id'])
                    .order('created_at', ascending: true),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final comments = snapshot.data!;

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
                          comment['username'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(comment['comment']),
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
}