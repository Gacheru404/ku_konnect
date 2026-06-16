import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class AddMarketItemPage
    extends StatefulWidget {

  const AddMarketItemPage({
    super.key,
  });

  @override
  State<AddMarketItemPage>
  createState() =>
      _AddMarketItemPageState();
}

class _AddMarketItemPageState
    extends State<AddMarketItemPage> {

  final supabase =
      Supabase.instance.client;

  final titleController =
  TextEditingController();

  final descriptionController =
  TextEditingController();

  final priceController =
  TextEditingController();

  Uint8List? imageBytes;

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

  bool isLoading = false;

  Future<void> uploadItem() async {
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final price = priceController.text.trim();

    if (title.isEmpty || description.isEmpty || price.isEmpty || imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select an image')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not logged in';

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.png';

      await supabase.storage
          .from('Market Place')
          .uploadBinary(
        fileName,
        imageBytes!,
        fileOptions: const FileOptions(contentType: 'image/png'),
      );

      final imageUrl = supabase.storage
          .from('Market Place')
          .getPublicUrl(fileName);

      await supabase
          .from('marketplace')
          .insert({
        'user_id': user.id,
        'username': profile['username'],
        'title': title,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Sell Item',
        ),
      ),

      body: SingleChildScrollView(

        padding:
        const EdgeInsets.all(20),

        child: Column(

          children: [

            GestureDetector(

              onTap: pickImage,

              child: Container(

                height: 220,

                width: double.infinity,

                decoration: BoxDecoration(

                  color: Colors.grey[300],

                  borderRadius:
                  BorderRadius.circular(20),
                ),

                child:

                imageBytes != null

                    ? ClipRRect(

                  borderRadius:
                  BorderRadius.circular(20),

                  child: Image.memory(

                    imageBytes!,

                    fit: BoxFit.cover,
                  ),
                )

                    : const Icon(
                  Icons.add_a_photo,
                  size: 60,
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
              titleController,

              decoration:
              const InputDecoration(

                labelText:
                'Item Title',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(

              controller:
              descriptionController,

              maxLines: 4,

              decoration:
              const InputDecoration(

                labelText:
                'Description',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(

              controller:
              priceController,

              keyboardType:
              TextInputType.number,

              decoration:
              const InputDecoration(

                labelText:
                'Price',

                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(

              width: double.infinity,

              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : uploadItem,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Post Item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}