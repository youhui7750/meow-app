import 'dart:convert';
import 'package:http/http.dart' as http;

class OutscraperService {
  // 替換成你的 Outscraper 真实 API KEY
  final String _apiKey = "YTk5NGI2OTc5NGFlNDQ2NjhkZTgyMjJmNjI4MDM0NDd8MWNhYzE2MGYyMw"; 

  /// 1. 展開短網址 (對應 Python 中的 expand_url)
  Future<String> _expandUrl(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('HEAD', Uri.parse(url))..followRedirects = true;
      
      // 發送 HEAD 請求並追蹤重新導向
      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 10));
      final finalUrl = streamedResponse.request?.url.toString() ?? url;
      
      print("🔗 短網址展開後：$finalUrl");
      return finalUrl;
    } catch (e) {
      print("⚠️ 展開短網址失敗: $e");
      return url;
    }
  }

  /// 2. 處理核心查詢語法轉換 (對應 Python 中的邏輯)
  Future<String> _prepareQuery(String query) async {
    String q = query.trim();
    
    // 如果偵測到短網址先展開
    if (q.contains("goo.gl") || q.contains("maps.app")) {
      print("🔗 偵測到短網址，展開中...");
      q = await _expandUrl(q);
    }

    // Place ID（無空白、不是 http 開頭）→ 轉成完整 Maps URL
    if (!q.startsWith("http") && !q.contains(" ")) {
      q = "https://www.google.com/maps/place/?q=place_id:$q";
    }
    
    return q;
  }

  /// 功能一：抓取 Google Maps 商家評論 (reviewsLimit 帶 0 代表全部)
  Future<List<Map<String, dynamic>>> fetchReviews(String query, {int limit = 10}) async {
    final processedQuery = await _prepareQuery(query);
    print("🔍 送出評論查詢：$processedQuery | 目標筆數：${limit == 0 ? '全部' : limit}");

    final uri = Uri.parse("https://api.app.outscraper.com/maps/reviews-v3").replace(
      queryParameters: {
        "query": processedQuery,
        "reviewsLimit": limit.toString(),
        "language": "zh-tw",
        "sort": "newest",
        "async": "false",
      },
    );

    try {
      final response = await http.get(
        uri, 
        headers: {"X-API-KEY": _apiKey},
      ).timeout(const Duration(seconds: 120)); // 對應 Python 120 秒超時

      print("📡 Outscraper 評論 API 回應狀態碼: ${response.statusCode}");
      if (response.statusCode != 200) {
        print("❌ 評論錯誤: ${response.body}");
        return [];
      }

      final data = jsonDecode(response.body);
      final List<dynamic> places = data["data"] ?? [];
      if (places.isEmpty) {
        print("❌ 評論回傳 data 為空");
        return [];
      }

      final placeData = places[0];
      print("✅ 商家名稱：${placeData['name']}");
      print("✅ 綜合評分：${placeData['rating']} ⭐（總計 ${placeData['reviews']} 則）");

      final List<dynamic> reviewsRaw = placeData["reviews_data"] ?? [];
      print("✅ 成功取得實體評論：${reviewsRaw.length} 則");

      // 整理並清洗資料欄位
      return reviewsRaw.map<Map<String, dynamic>>((r) => {
        "author": r["author_title"] ?? "",
        "author_id": r["author_id"] ?? "",
        "rating": r["review_rating"],
        "text": r["review_text"] ?? "",
        "likes": r["review_likes"],
        "datetime": r["review_datetime_utc"] ?? "",
        "relative_time": r["review_timestamp"] ?? "",
        "response": r["owner_answer"] ?? "",
        "response_time": r["owner_answer_timestamp_datetime_utc"] ?? "",
      }).toList();

    } catch (e) {
      print("❌ fetchReviews 發生異常: $e");
      return [];
    }
  }

  /// 功能二：抓取 Google Maps 店家照片 (支援 tag: all / latest / menu / by_owner)
  Future<List<Map<String, dynamic>>> fetchPhotos(String query, {int photosLimit = 10, String tag = "menu"}) async {
    final processedQuery = await _prepareQuery(query);
    print("🔍 送出照片查詢：$processedQuery | 分類：$tag | 目標筆數：$photosLimit");

    final uri = Uri.parse("https://api.app.outscraper.com/google-maps-photos").replace(
      queryParameters: {
        "query": processedQuery,
        "photosLimit": photosLimit > 0 ? photosLimit.toString() : "100",
        "limit": "1", // 只取一間店
        "tag": tag,
        "language": "zh-tw",
        "async": "false",
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {"X-API-KEY": _apiKey},
      ).timeout(const Duration(seconds: 120));

      print("📡 Outscraper 照片 API 回應狀態碼: ${response.statusCode}");
      if (response.statusCode != 200) {
        print("❌ 照片錯誤: ${response.body}");
        return [];
      }

      final data = jsonDecode(response.body);
      final List<dynamic> places = data["data"] ?? [];
      if (places.isEmpty) {
        print("❌ 照片回傳資料為空");
        return [];
      }

      // ✨ 重點坑點處理：防範 Python 腳本中提到的 `places[0][0]` 嵌套 List 狀況
      var placeData = places[0];
      if (placeData is List && placeData.isNotEmpty) {
        placeData = placeData[0];
      }

      print("✅ 商家名稱：${placeData['name']}");
      final List<dynamic> photosRaw = placeData["photos_data"] ?? [];
      print("✅ 成功取得照片數量：${photosRaw.length} 張");

      // 整理並清洗照片欄位
      return photosRaw.map<Map<String, dynamic>>((p) => {
        "url": p["photo_url_large"] ?? p["photo_url"] ?? "",
        "tag": p["tag"] ?? "",
        "date": p["photo_date"] ?? "",
        "author": p["photo_source_name"] ?? "",
      }).toList();

    } catch (e) {
      print("❌ fetchPhotos 發生異常: $e");
      return [];
    }
  }
}