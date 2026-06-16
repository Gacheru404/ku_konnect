import 'dart:convert';
import 'package:http/http.dart' as http;

class PaymentService {
  // Replace these with your Daraja API credentials
  final String consumerKey = 'YOUR_CONSUMER_KEY';
  final String consumerSecret = 'YOUR_CONSUMER_SECRET';
  final String shortCode = '174379'; // Test shortcode
  final String passkey = 'bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919';
  final String callbackUrl = 'https://your-domain.com/callback';

  Future<String?> getAccessToken() async {
    final credentials = base64Encode(utf8.encode('$consumerKey:$consumerSecret'));
    final response = await http.get(
      Uri.parse('https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials'),
      headers: {'Authorization': 'Basic $credentials'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['access_token'];
    }
    return null;
  }

  Future<bool> stkPush(String phoneNumber, int amount) async {
    final token = await getAccessToken();
    if (token == null) return false;

    final timestamp = DateTime.now().year.toString() +
        DateTime.now().month.toString().padLeft(2, '0') +
        DateTime.now().day.toString().padLeft(2, '0') +
        DateTime.now().hour.toString().padLeft(2, '0') +
        DateTime.now().minute.toString().padLeft(2, '0') +
        DateTime.now().second.toString().padLeft(2, '0');

    final password = base64Encode(utf8.encode('$shortCode$passkey$timestamp'));

    final response = await http.post(
      Uri.parse('https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "BusinessShortCode": shortCode,
        "Password": password,
        "Timestamp": timestamp,
        "TransactionType": "CustomerPayBillOnline",
        "Amount": amount,
        "PartyA": phoneNumber,
        "PartyB": shortCode,
        "PhoneNumber": phoneNumber,
        "CallBackURL": callbackUrl,
        "AccountReference": "KUKonnect",
        "TransactionDesc": "Payment for Market Item"
      }),
    );

    return response.statusCode == 200;
  }
}
