import 'dart:convert';
import 'package:meow_food_butler/models/food_card.dart';
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

    // Google Place ID → 轉成完整 Maps URL；一般中文店名不要誤判成 place_id。
    if (!q.startsWith("http") && _looksLikePlaceId(q)) {
      q = "https://www.google.com/maps/place/?q=place_id:$q";
    }
    
    return q;
  }

  bool _looksLikePlaceId(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith("ChIJ") ||
        RegExp(r'^[A-Za-z0-9_-]{24,}$').hasMatch(trimmed);
  }

  /// 抓取 Google Maps 店家基本資料，轉成 app 的餐廳卡 FoodCard。
  Future<FoodCard?> fetchRestaurantDetail(String query) async {
    final processedQuery = await _prepareQuery(query);
    print("🔍 送出店家資料查詢：$processedQuery");

    final uri = Uri.parse(
      "https://api.app.outscraper.com/maps/search-v3",
    ).replace(
      queryParameters: {
        "query": processedQuery,
        "limit": "1",
        "language": "zh-tw",
        "async": "false",
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {"X-API-KEY": _apiKey},
      ).timeout(const Duration(seconds: 120));

      print("📡 Outscraper 店家資料 API 回應狀態碼: ${response.statusCode}");
      if (response.statusCode != 200) {
        print("❌ 店家資料錯誤: ${response.body}");
        return null;
      }

      final data = jsonDecode(response.body);
      final placeData = _firstPlaceData(data["data"]);
      if (placeData == null) {
        print("❌ 店家資料回傳 data 為空");
        return null;
      }

      final name = _readString(placeData, "name") ?? query.trim();
      final latitude = _readDouble(placeData, "latitude");
      final longitude = _readDouble(placeData, "longitude");
      final photoUrl = _toHighResolutionGooglePhotoUrl(
        _readString(placeData, "photo"),
      );

      return FoodCard(
        id: _readString(placeData, "place_id") ??
            _readString(placeData, "google_id") ??
            _readString(placeData, "cid"),
        googleMapsUrl: _readString(placeData, "location_link"),
        formattedAddress: _readString(placeData, "address"),
        rating: _readDouble(placeData, "rating"),
        reviews: _readInt(placeData, "reviews"),
        phone: _readString(placeData, "phone"),
        website: _readString(placeData, "website"),
        priceRange:
            _readString(placeData, "range") ?? _readString(placeData, "prices"),
        category:
            _readString(placeData, "category") ?? _readString(placeData, "type"),
        subtypes: _readStringList(placeData["subtypes"]),
        description: _readString(placeData, "description"),
        workingHours: _readMap(placeData, "working_hours"),
        popularTimes: placeData["popular_times"],
        typicalTimeSpent: _readString(placeData, "typical_time_spent"),
        menuLink: _readString(placeData, "menu_link"),
        bookingLink: _readString(placeData, "booking_appointment_link"),
        verified: placeData["verified"] as bool?,
        photoUrls: photoUrl == null || photoUrl.isEmpty ? const [] : [photoUrl],
        displayNames: [
          DisplayName(title: name, languageCode: "zh-TW"),
        ],
        location: latitude != null && longitude != null
            ? LocationCoordinate(latitude: latitude, longitude: longitude)
            : null,
      );
    } catch (e) {
      print("❌ fetchRestaurantDetail 發生異常: $e");
      return null;
    }
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
        "url": _toHighResolutionGooglePhotoUrl(
              (p["photo_url_large"] ?? p["photo_url"])?.toString(),
            ) ??
            "",
        "tag": p["tag"] ?? "",
        "date": p["photo_date"] ?? "",
        "author": p["photo_source_name"] ?? "",
      }).toList();

    } catch (e) {
      print("❌ fetchPhotos 發生異常: $e");
      return [];
    }
  }

  Map<String, dynamic>? _firstPlaceData(dynamic data) {
    if (data is! List || data.isEmpty) return null;
    dynamic first = data.first;
    while (first is List && first.isNotEmpty) {
      first = first.first;
    }
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  String? _readString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value;
    return value.toString();
  }

  double? _readDouble(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _readInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _readMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  List<String> _readStringList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      return value
          .split(RegExp(r'[,、]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String? _toHighResolutionGooglePhotoUrl(String? rawUrl) {
    final url = rawUrl?.trim();
    if (url == null || url.isEmpty) return null;

    const targetSize = '=w3200-h2000-k-no';
    final sizePattern = RegExp(r'=w\d+-h\d+(?:-[^?&]*)?');
    if (sizePattern.hasMatch(url)) {
      return url.replaceFirst(sizePattern, targetSize);
    }

    final queryStart = url.indexOf('?');
    if (queryStart == -1) return '$url$targetSize';

    return '${url.substring(0, queryStart)}$targetSize${url.substring(queryStart)}';
  }
}
