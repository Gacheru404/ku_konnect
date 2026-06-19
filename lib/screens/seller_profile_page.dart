import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage({super.key});

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? profile;
  bool isLoading = true;
  bool isEditing = false;

  late TextEditingController businessNameController;
  late TextEditingController phoneNumberController;
  late TextEditingController bioController;

  @override
  void initState() {
    super.initState();
    businessNameController = TextEditingController();
    phoneNumberController = TextEditingController();
    bioController = TextEditingController();
    loadProfile();
  }

  @override
  void dispose() {
    businessNameController.dispose();
    phoneNumberController.dispose();
    bioController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
        profile = data;
        businessNameController.text = data['business_name'] ?? '';
        phoneNumberController.text = data['phone_number'] ?? '';
        bioController.text = data['bio'] ?? '';
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> updateProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('profiles')
          .update({
            'business_name': businessNameController.text,
            'phone_number': phoneNumberController.text,
            'bio': bioController.text,
          })
          .eq('id', user.id);

      if (!mounted) return;

      setState(() => isEditing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );

      loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return const Scaffold(
        body: Center(child: Text('Profile not found')),
      );
    }

    final isVerified = profile!['seller_verified'] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller Profile'),
        actions: [
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => isEditing = true),
            ),
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: updateProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Verification Status Card
            Card(
              color: isVerified ? Colors.green[50] : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isVerified ? Icons.verified : Icons.pending,
                      color: isVerified ? Colors.green : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isVerified
                                ? 'Verified Seller'
                                : 'Verification Pending',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color:
                                  isVerified ? Colors.green : Colors.orange,
                            ),
                          ),
                          Text(
                            isVerified
                                ? 'Your account has been verified'
                                : 'Your verification is being reviewed',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Account Information Section
            const Text(
              'Account Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Username (read-only)
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: profile!['username'] ?? 'N/A',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
              ),
              controller: TextEditingController(text: profile!['username'] ?? ''),
            ),

            const SizedBox(height: 12),

            // Email (read-only)
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: profile!['email'] ?? 'N/A',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.email),
              ),
              controller: TextEditingController(text: profile!['email'] ?? ''),
            ),

            const SizedBox(height: 24),

            // Business Information Section
            const Text(
              'Business Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Business Name
            TextField(
              enabled: isEditing,
              controller: businessNameController,
              decoration: InputDecoration(
                labelText: 'Business Name',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.business),
              ),
            ),

            const SizedBox(height: 12),

            // Phone Number
            TextField(
              enabled: isEditing,
              controller: phoneNumberController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.phone),
              ),
            ),

            const SizedBox(height: 12),

            // Bio
            TextField(
              enabled: isEditing,
              controller: bioController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Bio/Description',
                hintText: 'Tell customers about your business',
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            // Statistics Section
            const Text(
              'Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.store, size: 32, color: Colors.blue),
                          const SizedBox(height: 8),
                          const Text('Active Listings', style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '0',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.shopping_cart,
                              size: 32, color: Colors.green),
                          const SizedBox(height: 8),
                          const Text('Total Sales', style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            'KES 0',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Action Buttons
            if (!isEditing)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.analytics),
                      label: const Text('View Analytics'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Analytics coming soon'),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_box),
                      label: const Text('Add New Listing'),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
