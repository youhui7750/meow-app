import 'package:flutter/material.dart';
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

  void _updateStatus(bool loading, String msg, [String? error]) {
    _isLoading = loading;
    _loadingMessage = msg;
    _errorMessage = error;
    notifyListeners();
  }

  Future<bool> pipelineImport(String url) async {
    if (!url.contains("instagram.com")) {
      _updateStatus(false, "", "請輸入有效的 IG 連結");
      return false;
    }

    try {
      // Step 1: Apify 抓取
      _updateStatus(true, "正在透過 Apify 讀取 IG 貼文內容 (約需 10-20 秒)...");
      final igData = await _apify.fetchIgCaptionAndLocation(url);
      if (igData == null) throw "無法解析該貼文，可能為私密帳號或連結錯誤";

      // Step 2: AI Agent 辨識
      _updateStatus(true, "AI 正在分析內文並辨識餐廳名稱...");
      final restaurantQuery = await _aiAgent.extractRestaurantName(igData['caption']!, igData['location']!);
      if (restaurantQuery == null) throw "AI 無法從內文中辨識出餐廳名稱";

      // Step 3: Outscraper 搜尋店訊
      _updateStatus(true, "已辨識出「$restaurantQuery」，正在透過 Outscraper 補全 Google Maps 資料...");
      final googlePlace = await _outscraper.searchGoogleMaps(restaurantQuery);
      if (googlePlace == null) throw "在 Google 地圖上找不到該餐廳";

      // 成功！此處可以將 googlePlace 的經緯度與名字存入 Firebase
      print("🎉 成功獲取完整店訊: ${googlePlace['name']}, 座標: ${googlePlace['latitude']}, ${googlePlace['longitude']}");

      _updateStatus(false, "");
      return true;
    } catch (e) {
      _updateStatus(false, "", e.toString());
      return false;
    }
  }
}