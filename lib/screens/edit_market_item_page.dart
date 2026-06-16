import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditMarketItemPage extends StatefulWidget {
  final dynamic item;

  const EditMarketItemPage({super.key, required this.item});

  @override
  State<EditMarketItemPage> createState() => _EditMarketItemPageState();
}

class _EditMarketItemPageState extends State<EditMarketItemPage> {
  final supabase = Supabase.instance.client;
  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController priceController;
  Uint8List? newImageBytes;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.item['title']);
    descriptionController =
        TextEditingController(text: widget.item['description']);
    priceController = TextEditingController(text: widget.item['price']);
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      newImageBytes = bytes;
    });
  }

  Future<void> updateItem() async {
    try {
      String imageUrl = widget.item['image_url'];

      if (newImageBytes != null) {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}.png';
        await supabase.storage
            .from('Market Place')
            .uploadBinary(fileName, newImageBytes!);
        imageUrl = supabase.storage
            .from('Market Place')
            .getPublicUrl(fileName);
      }

      await supabase.from('marketplace').update({
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'price': double.parse(priceController.text),
        'image_url': imageUrl,
      }).eq('id', widget.item['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item updated!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Item'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: pickImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: newImageBytes != null
                    ? Image.memory(
                  newImageBytes!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
                    : Image.network(
                  widget.item['image_url'],
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap image to change it',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: updateItem,
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}