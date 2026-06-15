import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/experience_card.dart'; // 確保路徑指向你的 ExperienceCard
import '../models/food_card.dart';
import '../services/apify_service.dart';
import '../services/ai_agent_service.dart';
import '../services/outscraper_service.dart';

class InstagramImportViewModel extends ChangeNotifier {
  final ApifyService _apify = ApifyService();
  final AiAgentService _aiAgent = AiAgentService();
  final OutscraperService _outscraper = OutscraperService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _loadingMessage = "";
  String get loadingMessage => _loadingMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 執行完整自動化管線，最終返回餐廳卡與地圖暫存卡。
  Future<InstagramImportResult?> pipelineImportAndBuildCard(String igUrl) async {
    _errorMessage = null;
    _isLoading = true;
    _loadingMessage = "正在透過 Apify 讀取 IG 貼文內容...";
    notifyListeners();

    try {
      // 1. 抓取 IG 內文與地標
      final igData = await _apify.fetchIgCaptionAndLocation(igUrl);
      if (igData == null || igData['caption'] == null) {
        throw "無法讀取該貼文內容，請檢查連結是否公開";
      }
      final String caption = igData['caption']!;
      final String locationTag = igData['location']!;

      // 2. AI 提取店家關鍵字
      _loadingMessage = "AI 正在分析內文，精準提取餐廳名稱...";
      notifyListeners();
      final restaurantQuery =
          _queryFromLocationTag(locationTag) ??
          await _aiAgent.extractRestaurantName(caption, locationTag);
      if (restaurantQuery == null) throw "AI 無法從內文中辨識出明確的餐廳名稱";
      debugPrint("[DEBUG] Restaurant query: $restaurantQuery");

      // 3. Outscraper 查詢 Google Maps 詳細店訊
      _loadingMessage = "Outscraper 正在撈取 Google Maps 商家資訊...";
      notifyListeners();
      
      final restaurantDetail = await _outscraper.fetchRestaurantDetail(
        restaurantQuery,
      );
      final menuPhotosRaw = await _outscraper.fetchPhotos(restaurantQuery, tag: "menu", photosLimit: 5);
      final reviewSnippets = await _outscraper.fetchReviews(restaurantQuery, limit: 3);

      // 4. 自動從 IG 內文萃取 Hashtags 作為分類標籤 (個人小客製)
      List<String> tags = _extractHashtags(caption);
      if (tags.isEmpty) {
        tags = ["IG匯入", "待吃清單"];
      }

      // 5. 提取照片 URL 清單
      List<String> extractedPhotoUrls = menuPhotosRaw
          .map((photoMap) => photoMap["url"] as String)
          .where((url) => url.isNotEmpty)
          .toList();
      extractedPhotoUrls = _mergePhotoUrls(
        restaurantDetail?.photoUrls ?? const [],
        extractedPhotoUrls,
      );

      // 6. 🏆 正式建構你的 ExperienceCard
      _loadingMessage = "正在產生您的用餐體驗小卡...";
      notifyListeners();

      final newCard = ExperienceCard(
        id: null, // 給 Firestore 自動生成 doc ID
        foodCardId: null, // 後續看你要不要綁定特定的主餐廳 ID
        placeId: restaurantDetail?.id,
        placeTitle: restaurantDetail?.primaryTitle ?? restaurantQuery,
        placeAddress: restaurantDetail?.formattedAddress,
        latitude: restaurantDetail?.location?.latitude,
        longitude: restaurantDetail?.location?.longitude,
        originalURL: igUrl,
        photoPaths: const [], // 剛匯入時尚未上傳至自己 Firebase Storage
        photoUrls: extractedPhotoUrls, // 這裡直接帶入 Outscraper 抓到的 5 張菜單相片網址！
        personalTags: tags, // 自動轉入的 ["台北美食", "西門美食", "萬華美食"]
        personalRating: 0.0, // 新加入預設 0 顆星，等使用者之後自己打分數
        personalNote: caption, // 完美保留完整的 IG 介紹文作為內文備忘錄！
        isDone: false, // 預設為 false (口袋名單狀態)
        createdTime: Timestamp.now(),
      );

      _isLoading = false;
      _loadingMessage = "";
      notifyListeners();
      return InstagramImportResult(
        experience: newCard,
        restaurant: (restaurantDetail ??
                FoodCard(
                  id: null,
                  originalURL: igUrl,
                  formattedAddress: newCard.placeAddress,
                  visited: false,
                  tags: tags,
                  photoUrls: extractedPhotoUrls,
                  displayNames: [
                    DisplayName(title: newCard.placeTitle, languageCode: 'zh-TW'),
                  ],
                  location: newCard.latitude != null && newCard.longitude != null
                      ? LocationCoordinate(
                          latitude: newCard.latitude,
                          longitude: newCard.longitude,
                        )
                      : null,
                ))
            .copyForImport(
          originalURL: igUrl,
          visited: false,
          tags: tags,
          photoUrls: extractedPhotoUrls,
          reviewSnippets: reviewSnippets,
        ),
      );

    } catch (e) {
      _isLoading = false;
      _loadingMessage = "";
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 輔助函式：用正則表達式把內文中的 # 標籤自動抓出來
  List<String> _extractHashtags(String text) {
    final RegExp exp = RegExp(r"#(\w+)");
    final matches = exp.allMatches(text);
    return matches.map((m) => m.group(1)!).toList();
  }

  String? _queryFromLocationTag(String locationTag) {
    final query = locationTag.trim();
    if (query.isEmpty) return null;
    final lower = query.toLowerCase();
    if (lower == 'null' ||
        lower == 'unknown' ||
        lower == 'instagram' ||
        lower == 'none') {
      return null;
    }
    return query;
  }

  List<String> _mergePhotoUrls(List<String> base, List<String> extra) {
    final seen = <String>{};
    final merged = <String>[];
    for (final url in [...base, ...extra]) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      merged.add(trimmed);
    }
    return merged;
  }
}

class InstagramImportResult {
  final ExperienceCard experience;
  final FoodCard restaurant;

  const InstagramImportResult({
    required this.experience,
    required this.restaurant,
  });
}
