import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Backend URL - Bilgisayarınızın yerel IP adresi
  static const String baseUrl = 'http://192.168.1.168:5000';

  Future<Map<String, dynamic>> startWatching({
    required String from,
    required String to,
    required String date,
    required String wagonType,
    required int passengers,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/watch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': from,
          'to': to,
          'date': date,
          'wagon_type': wagonType,
          'passengers': passengers,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API Hatası: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<Map<String, dynamic>> stopWatching() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/watch'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API Hatası: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/status'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API Hatası: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
      ).timeout(Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
