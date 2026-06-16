import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final supabase = Supabase.instance.client;
  final List<String> categories = ['General', 'Engineering', 'Medicine', 'Business', 'Arts', 'Science'];
  late final Stream<List<Map<String, dynamic>>> studyDocsStream;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    studyDocsStream = supabase
        .from('study_documents')
        .stream(primaryKey: ['id'])
        .order('uploaded_at', ascending: false);
  }

  Future<void> uploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx'],
    );

    if (result == null) return;
    if (!mounted) return;

    // 1. File size validation (limit to 50MB)
    final fileSize = result.files.single.size;
    if (fileSize > 50 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large. Maximum size is 50MB.')),
      );
      return;
    }

    final category = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Category'),
        children: categories
            .map((c) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, c),
          child: Text(c),
        ))
            .toList(),
      ),
    );

    if (category == null) return;
    if (!mounted) return;

    setState(() => _isUploading = true);

    try {
      final pickedFile = result.files.single;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not authenticated';
      
      // 2. Sanitize filename (remove spaces and special characters)
      final originalName = pickedFile.name;
      final sanitizedName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '_');
      final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

      // 3. Use correct bucket name (lowercase, no spaces)
      const bucketName = 'storage-docs';

      if (kIsWeb) {
        // Web requires uploading as bytes
        await supabase.storage
            .from(bucketName)
            .uploadBinary(fileName, pickedFile.bytes!);
      } else {
        // Mobile/Desktop can upload using the file path
        final file = File(pickedFile.path!);
        await supabase.storage
            .from(bucketName)
            .upload(fileName, file);
      }

      final url = supabase.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      await supabase.from('study_documents').insert({
        'user_id': user.id,
        'username': profile['username'],
        'file_name': originalName,
        'file_url': url,
        'category': category,
        'uploaded_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document uploaded successfully!')),
      );

    } catch (e) {
      debugPrint('Upload error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study Hub'),
          bottom: TabBar(
            isScrollable: true,
            tabs: categories.map((c) => Tab(text: c)).toList(),
          ),
          actions: [
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.upload_file),
                onPressed: uploadDocument,
              ),
          ],
        ),
        body: TabBarView(
          children: categories.map((c) => _buildDocList(c)).toList(),
        ),
      ),
    );
  }

  Widget _buildDocList(String category) {
    return StreamBuilder(
      stream: studyDocsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!;
        final docs = allDocs.where((d) {
          // If category is null, show it in 'General'
          final docCategory = d['category'] ?? 'General';
          return docCategory == category;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.description_outlined, size: 60, color: Colors.grey),
                const SizedBox(height: 10),
                Text('No documents in $category yet.'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                leading: const Icon(Icons.description, color: Colors.blue),
                title: Text(doc['file_name']),
                subtitle: Text('By ${doc['username']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () async {
                    final url = Uri.parse(doc['file_url']);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
