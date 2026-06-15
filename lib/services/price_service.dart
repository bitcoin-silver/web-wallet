import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class PriceData {
  final double price;
  final String currency;
  final DateTime lastUpdated;
  final double changePercent24h;

  PriceData({
    required this.price,
    required this.currency,
    required this.lastUpdated,
    required this.changePercent24h,
  });
}

class PriceService {
  Future<PriceData?> getBTCSPrice({String currency = 'USD'}) async {
    try {
      final response = await http.post(
        Uri.parse(Config.liveCoinWatchUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': Config.liveCoinWatchApiKey,
        },
        body: jsonEncode({
          'currency': currency,
          'code': Config.btcsCode,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PriceData(
          price: (data['rate'] as num).toDouble(),
          currency: currency,
          lastUpdated: DateTime.now(),
          changePercent24h: (data['delta']?['day'] as num?)?.toDouble() ?? 0.0,
        );
      } else {
        print('Error fetching price: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception fetching price: $e');
      return null;
    }
  }
}
