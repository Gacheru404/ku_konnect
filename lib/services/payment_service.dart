import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

class PaymentService {
  // 1. DARAJA API CREDENTIALS
  // Replace YOUR_CONSUMER_KEY and YOUR_CONSUMER_SECRET with your actual keys from Daraja Portal
  final String consumerKey = 'Br0ZX17V9OQz6oI1AdtlNyPA9QHikEmSPzlnRPL9Vs3pUoEV';
  final String consumerSecret = 'K2jR1MXhya4VoRYHvcpfucrO3qGAZSIZgIn6zmCvRfyBGCihMwb8yMlwzwKwfDvA';
  
  // Sandbox Shortcode and Passkey
  final String shortCode = '174379'; 
  final String passkey = 'bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919';
  
  // Callback URL: Safaricom will send the transaction results to this URL.
  // For testing STK prompt, any valid https URL works, but to receive status you need a real one.
  final String callbackUrl = 'https://ad10412edf94bf39c1860e577aff2f1c.m.pipedream.net';

  Future<String?> getAccessToken() async {
    try {
      final credentials = base64Encode(utf8.encode('$consumerKey:$consumerSecret'));
      final response = await http.get(
        Uri.parse('https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials'),
        headers: {'Authorization': 'Basic $credentials'},
      );

      // ignore: avoid_print
      print('AUTH Status: ${response.statusCode}');

      //ignore: avoid_print
      print('AUTH Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['access_token'];
      }
    } catch (e) {
      developer.log('Mpesa Auth Error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> stkPush(String phoneNumber, int amount) async {
    try {
      final token = await getAccessToken();

      if (token == null) {
        throw Exception(
          'Failed to get access token. Check Consumer Key and Consumer Secret.',
        );
      }

      // Generate Timestamp: YYYYMMDDHHmmss
      final now = DateTime.now();
      final timestamp = "${now.year}"
          "${now.month.toString().padLeft(2, '0')}"
          "${now.day.toString().padLeft(2, '0')}"
          "${now.hour.toString().padLeft(2, '0')}"
          "${now.minute.toString().padLeft(2, '0')}"
          "${now.second.toString().padLeft(2, '0')}";

      // Password = base64(shortcode + passkey + timestamp)
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
          "PartyA": phoneNumber, // Format: 2547XXXXXXXX
          "PartyB": shortCode,
          "PhoneNumber": phoneNumber,
          "CallBackURL": callbackUrl,
          "AccountReference": "KUKonnect",
          "TransactionDesc": "Marketplace Purchase"
        }),
      );

      // ignore: avoid_print
      print('STK Status Code: ${response.statusCode}');

      // ignore: avoid_print
      print('STK Response Body: ${response.body}');

      final data = jsonDecode(response.body);

      if (data['ResponseCode'] == '0') {
        return data;
      }

      return null;

    } catch (e) {
      developer.log('STK Push Error: $e');
      throw Exception(e.toString());
    }
  }
}
