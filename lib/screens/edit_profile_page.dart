import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {

  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() =>
      _EditProfilePageState();
}

class _EditProfilePageState
    extends State<EditProfilePage> {

  final supabase =
      Supabase.instance.client;

  final bioController =
  TextEditingController();

  Uint8List? imageBytes;

  String? avatarUrl;

  Future<void> pickImage() async {

    final picker = ImagePicker();

    final file = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) return;

    final bytes =
    await file.readAsBytes();

    setState(() {

      imageBytes = bytes;
    });
  }

  Future<void> saveProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      String? imageUrl = avatarUrl;

      if (imageBytes != null) {
        final fileName = '${user.id}/avatar.png';

        await supabase.storage
            .from('Avatars')
            .uploadBinary(
          fileName,
          imageBytes!,
          fileOptions: const FileOptions(upsert: true),
        );

        imageUrl = supabase.storage
            .from('Avatars')
            .getPublicUrl(fileName);

        // Add cache buster to force image refresh
        imageUrl = '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      }

      await supabase
          .from('profiles')
          .update({
        'bio': bioController.text.trim(),
        'avatar_url': imageUrl,
      }).eq('id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );

      Navigator.pop(context);

    } catch (e) {
      debugPrint('Profile save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Edit Profile',
        ),
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          children: [

            GestureDetector(

              onTap: pickImage,

              child: CircleAvatar(

                radius: 50,

                backgroundImage:

                imageBytes != null

                    ? MemoryImage(imageBytes!)

                    : null,

                child:

                imageBytes == null

                    ? const Icon(
                  Icons.camera_alt,
                  size: 40,
                )

                    : null,
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
              bioController,

              maxLines: 3,

              decoration:
              const InputDecoration(

                labelText: 'Bio',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton(

                onPressed:
                saveProfile,

                child: const Text(
                  'Save Profile',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}