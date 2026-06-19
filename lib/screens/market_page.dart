import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_market_item_page.dart';
import 'edit_market_item_page.dart';
import '../services/payment_service.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final supabase = Supabase.instance.client;

  Future<void> deleteItem(String itemId) async {
    try {
      await supabase
          .from('marketplace')
          .delete()
          .eq('id', int.parse(itemId));

      debugPrint('DELETE SUCCESS');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item deleted.')),
      );
    } catch (e) {
      debugPrint('DELETE ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }
  void showDeleteConfirm(String itemId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              deleteItem(itemId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void showMpesaDialog(dynamic item) {
    final phoneController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Pay with M-Pesa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item['title'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                'KES ${item['price']}',
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'M-Pesa Phone (254XXXXXXXXX)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'You will receive an M-Pesa prompt on your phone.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: isProcessing
                  ? null
                  : () async {
                final phone = phoneController.text.trim();
                if (phone.isEmpty || !phone.startsWith('254') || phone.length != 12) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid phone number format (254...)')),
                  );
                  return;
                }

                setState(() => isProcessing = true);
                // ignore: avoid_print
                print('ITEM PRICE RAW: ${item['price']}');
                // ignore: avoid_print
                print('ITEM PRICE TYPE: ${item['price'].runtimeType}');
                // ignore: avoid_print
                print('PARSED PRICE: ${int.tryParse(item['price'].toString()) ?? 0}');

                final rawPrice = item['price'];

                // ignore: avoid_print
                print('RAW PRICE VALUE: $rawPrice');
                // ignore: avoid_print
                print('RAW PRICE TYPE: ${rawPrice.runtimeType}');

                double parsedPrice = 0;

                if (rawPrice is int) {
                  parsedPrice = rawPrice.toDouble();
                } else if (rawPrice is double) {
                  parsedPrice = rawPrice;
                } else if (rawPrice is String) {
                  parsedPrice = double.tryParse(
                    rawPrice.replaceAll(RegExp(r'[^0-9.]'), ''),
                  ) ??
                      0;
                }

                final amount = parsedPrice.round();
                //ignore: avoid_print
                print('FINAL AMOUNT: $amount');

                // DEBUG
                // ignore: avoid_print
                print('RAW PRICE: ${item['price']}');
                //ignore: avoid_print
                print('AMOUNT SENT TO MPESA: $amount');

                if (amount < 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid item price. Amount must be at least KES 1'),
                    ),
                  );

                  setState(() => isProcessing = false);
                  return;
                }

                final user = supabase.auth.currentUser;

                await supabase.from('payments').insert({
                  'buyer_id': user?.id,
                  'seller_id': item['user_id'],
                  'item_id': item['id'],
                  'item_title': item['title'],
                  'amount': amount,
                  'phone_number': phone,
                  'status': 'pending',
                });

                final response = await PaymentService().stkPush(
                  phone,
                  amount,
                );

                if (response != null) {
                  await supabase
                      .from('payments')
                      .update({
                        'checkout_request_id':
                          response['CheckoutRequestID']?.toString(),
                  })
                      .eq('buyer_id', user!.id)
                      .eq('item_id', item['id'])
                      .eq('status', 'pending');
                }

                if (!context.mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      response != null
                          ? 'M-Pesa prompt sent! Check your phone.'
                          : 'Failed to send M-Pesa prompt.',
                    ),
                  ),
                );
              },
              child: isProcessing
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
                  : const Text(
                'Send Request',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddMarketItemPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: supabase
            .from('marketplace')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!;

          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.store, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'No items yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  Text(
                    'Be the first to sell something!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isOwner = item['user_id'] == currentUser?.id;

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.network(
                          item['image_url'],
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                height: 220,
                                color: Colors.grey[300],
                                child: const Icon(Icons.image_not_supported,
                                    size: 60),
                              ),
                        ),
                      ),
                      const SizedBox(height: 15),

                      // Title and owner actions
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['title'],
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isOwner) ...[
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EditMarketItemPage(item: item),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon:
                              const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  showDeleteConfirm(item['id'].toString()),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(item['description'] ?? ''),
                      const SizedBox(height: 12),

                      // Price
                      Text(
                        'KES ${item['price']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Seller: ${item['username']}',
                        style: const TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 15),

                      // Buy button — only show if not your own item
                      if (!isOwner)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.payment),
                            label: const Text('Buy via M-Pesa'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding:
                              const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => showMpesaDialog(item),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}