import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// List your admin user IDs here
const List<String> adminIds = [
  '0de42a82-4807-4f4d-9614-7d74ed914078',
];

class BuzzNewsPage extends StatefulWidget {
  const BuzzNewsPage({super.key});

  @override
  State<BuzzNewsPage> createState() => _BuzzNewsPageState();
}

class _BuzzNewsPageState extends State<BuzzNewsPage> {
  final supabase = Supabase.instance.client;
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  Uint8List? imageBytes;
  bool isUploading = false;
  late final Stream<List<Map<String, dynamic>>> newsStream;

  @override
  void initState() {
    super.initState();
    newsStream = supabase
        .from('buzz_news')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  bool get isAdmin {
    final userId = supabase.auth.currentUser?.id;
    return adminIds.contains(userId);
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => imageBytes = bytes);
  }

  Future<void> postAnnouncement() async {
    if (titleController.text.trim().isEmpty) return;

    setState(() => isUploading = true);

    try {
      String? imageUrl;
      if (imageBytes != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
        await supabase.storage
            .from('Buzz news')
            .uploadBinary(fileName, imageBytes!);
        imageUrl = supabase.storage.from('Buzz news').getPublicUrl(fileName);
      }

      await supabase.from('buzz_news').insert({
        'title': titleController.text.trim(),
        'body': bodyController.text.trim(),
        'image_url': imageUrl,
        'user_id': supabase.auth.currentUser!.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      titleController.clear();
      bodyController.clear();
      setState(() => imageBytes = null);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  Future<void> updateAnnouncement(
      String id,
      String title,
      String body,
      ) async {
    try {
      await supabase
          .from('buzz_news')
          .update({
        'title': title,
        'body': body,
      })
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
          ),
        );
      }
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    try {
      await supabase
          .from('buzz_news')
          .delete()
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement deleted'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
          ),
        );
      }
    }
  }

  void showPostDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post Announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    await pickImage();
                    setDialogState(() {});
                  },
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: imageBytes != null
                        ? Image.memory(imageBytes!, fit: BoxFit.cover)
                        : const Icon(Icons.add_a_photo, size: 50),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Caption/Content',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isUploading ? null : postAnnouncement,
              child: isUploading
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator())
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  void showEditDialog(Map<String, dynamic> item) {
    final editTitle =
    TextEditingController(text: item['title']);

    final editBody =
    TextEditingController(text: item['body']);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editTitle,
              decoration: const InputDecoration(
                labelText: 'Title',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: editBody,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Content',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await updateAnnouncement(
                item['id'].toString(),
                editTitle.text.trim(),
                editBody.text.trim(),
              );

              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'Current User: ${supabase.auth.currentUser?.id}',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buzz News'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: showPostDialog,
            ),
        ],
      ),
      body: StreamBuilder(
        stream: newsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final news = snapshot.data!;

          if (news.isEmpty) {
            return const Center(
              child: Text('No announcements yet.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: news.length,
            itemBuilder: (context, index) {
              final item = news[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['image_url'] != null)
                      ClipRRect(
                        borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                        child: Image.network(
                          item['image_url'],
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.campaign,
                                color: Colors.red,
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  item['title'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              if (isAdmin)
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () =>
                                      showEditDialog(item),
                                ),

                              if (isAdmin)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final confirm =
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text(
                                          'Delete announcement?',
                                        ),
                                        content: const Text(
                                          'This cannot be undone.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    context, false),
                                            child: const Text(
                                              'Cancel',
                                            ),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    context, true),
                                            child: const Text(
                                              'Delete',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      await deleteAnnouncement(
                                        item['id'].toString(),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(item['body'] ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );

  }
}
