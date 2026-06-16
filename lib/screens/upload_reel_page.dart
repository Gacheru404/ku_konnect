import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class UploadReelPage
    extends StatefulWidget {

  const UploadReelPage({
    super.key,
  });

  @override
  State<UploadReelPage>
  createState() =>
      _UploadReelPageState();
}

class _UploadReelPageState
    extends State<UploadReelPage> {

  final supabase =
      Supabase.instance.client;

  final captionController =
  TextEditingController();

  File? videoFile;

  Future<void> pickVideo() async {

    final picker = ImagePicker();

    final file =
    await picker.pickVideo(
      source: ImageSource.gallery,
    );

    if (file == null) return;

    setState(() {

      videoFile = File(file.path);
    });
  }

  Future<void> uploadReel() async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    if (videoFile == null) return;

    final profile = await supabase

        .from('profiles')

        .select()

        .eq('id', user.id)

        .single();

    final fileName =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.mp4';

    await supabase.storage

        .from('Reels')

        .upload(

      fileName,

      videoFile!,
    );

    final videoUrl = supabase.storage

        .from('Reels')

        .getPublicUrl(fileName);

    await supabase

        .from('reels')

        .insert({

      'user_id': user.id,

      'username':
      profile['username'],

      'caption':
      captionController.text.trim(),

      'video_url': videoUrl,
    });

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Upload Reel',
        ),
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          children: [

            GestureDetector(

              onTap: pickVideo,

              child: Container(

                height: 250,

                width: double.infinity,

                decoration: BoxDecoration(

                  color: Colors.grey[300],

                  borderRadius:
                  BorderRadius.circular(20),
                ),

                child: const Center(

                  child: Icon(
                    Icons.video_library,
                    size: 70,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
              captionController,

              decoration:
              const InputDecoration(

                labelText: 'Caption',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(

              width: double.infinity,

              height: 55,

              child: ElevatedButton(

                onPressed:
                uploadReel,

                child: const Text(
                  'Upload Reel',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}