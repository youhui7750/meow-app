import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/experience_card.dart'; // 確保路徑指向你的 ExperienceCard
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

  /// 執行完整自動化管線，最終返回建構好的 ExperienceCard
  Future<ExperienceCard?> pipelineImportAndBuildCard(String igUrl) async {
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
      final restaurantQuery = await _aiAgent.extractRestaurantName(caption, locationTag);
      if (restaurantQuery == null) throw "AI 無法從內文中辨識出明確的餐廳名稱";

      // 3. Outscraper 查詢 Google Maps 詳細店訊
      _loadingMessage = "Outscraper 正在撈取 Google Maps 商家資訊...";
      notifyListeners();
      
      // 這裡假設你另外寫了一個 _outscraper.searchGooglePlaces()
      // 或者直接用原本 fetchReviews/fetchPhotos 回傳包裝好的店家基本屬性
      // 為了示範，我們先用已知的 fetchPhotos 順便帶回的店訊做基底
      final menuPhotosRaw = await _outscraper.fetchPhotos(restaurantQuery, tag: "menu", photosLimit: 5);
      
      // 假設我們用已修正的 Outscraper 拿到了基本店訊
      // 注意：Outscraper 撈回來的 key 通常包含商家經緯度與地址
      // if (menuPhotosRaw.isEmpty) {
      //   throw "在 Google 地圖上找不到「$restaurantQuery」的相關照片或店訊";
      // }

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

      // 6. 🏆 正式建構你的 ExperienceCard
      _loadingMessage = "正在產生您的用餐體驗小卡...";
      notifyListeners();

      // 💡 假定 Outscraper 或你原本的搜尋能提供經緯度與地址，這裡做對應塞入：
      final newCard = ExperienceCard(
        id: null, // 給 Firestore 自動生成 doc ID
        foodCardId: null, // 後續看你要不要綁定特定的主餐廳 ID
        placeId: "ChIJ_derived_from_outscraper_or_search", // 建議從 Outscraper 基礎搜尋帶入
        placeTitle: restaurantQuery.split(' ').first, // 去掉城市，純取店名例如 "圍爐烤肉"
        placeAddress: "台北市萬華區長沙街二段126號1樓", // 實際上從 Outscraper response 取得
        latitude: 25.0423, // 實際上從 Outscraper response 取得
        longitude: 121.5065, // 實際上從 Outscraper response 取得
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
      return newCard;

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
}