import 'dart:convert';
import 'package:http/http.dart' as http;

class MpesaService {
  // Replace with your actual Daraja credentials
  static const String consumerKey = 'YOUR_CONSUMER_KEY';
  static const String consumerSecret = 'YOUR_CONSUMER_SECRET';
  static const String businessShortCode = 'YOUR_SHORTCODE';
  static const String passkey = 'YOUR_PASSKEY';
  static const String callbackUrl = 'YOUR_CALLBACK_URL';

  Future<String> getAccessToken() async {
    final credentials = base64Encode(
      utf8.encode('$consumerKey:$consumerSecret'),
    );

    final response = await http.get(
      Uri.parse(
        'https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
      ),
      headers: {'Authorization': 'Basic $credentials'},
    );

    final data = jsonDecode(response.body);
    return data['access_token'];
  }

  Future<bool> initiateStkPush({
    required String phoneNumber,
    required String amount,
    required String accountReference,
  }) async {
    try {
      final token = await getAccessToken();

      final timestamp = DateTime.now()
          .toString()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);

      final password = base64Encode(
        utf8.encode('$businessShortCode$passkey$timestamp'),
      );

      final response = await http.post(
        Uri.parse(
          'https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'BusinessShortCode': businessShortCode,
          'Password': password,
          'Timestamp': timestamp,
          'TransactionType': 'CustomerPayBillOnline',
          'Amount': amount,
          'PartyA': phoneNumber,
          'PartyB': businessShortCode,
          'PhoneNumber': phoneNumber,
          'CallBackURL': callbackUrl,
          'AccountReference': accountReference,
          'TransactionDesc': 'KU Konnect Marketplace',
        }),
      );

      final data = jsonDecode(response.body);
      return data['ResponseCode'] == '0';

    } catch (e) {
      return false;
    }
  }
}