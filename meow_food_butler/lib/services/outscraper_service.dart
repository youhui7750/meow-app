import 'dart:convert';
import 'package:http/http.dart' as http;

class OutscraperService {
  final String _apiKey = "YOUR_OUTSCRAPER_API_KEY";

  Future<Map<String, dynamic>?> searchGoogleMaps(String query) async {
    // 使用 Outscraper Google Maps Search 服務
    final url = Uri.parse("https://api.app.outscraper.com/maps/search?query=$query&limit=1");
    
    final res = await http.get(url, headers: {"X-API-KEY": _apiKey});
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['data'] != null && data['data'].isNotEmpty) {
        // 回傳第一筆搜尋到的商家詳細資料（包含經緯度、地址、星等）
        return data['data'][0]; 
      }
    }
    return null;
  }
}