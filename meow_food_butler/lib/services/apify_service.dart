/// Apify 是一個可以爬蟲 IG 的 API，
/// 我們將使用他來得取商家重要資料，
/// 連結 Outscraper 在 Google Maps 查詢


import 'dart:convert';
import 'package:http/http.dart' as http;

class ApifyService {
  final String _token = "apify_api_b1zChrfREXql3CasdDLzc96jWNgjyg0z27B6"; // 建議之後移至 .env
  final String _actorId = "apify~instagram-scraper";

  Future<Map<String, String>?> fetchIgCaptionAndLocation(String igUrl) async {
    // 1. 啟動 Actor Run
    final startUrl = Uri.parse("https://api.apify.com/v2/acts/$_actorId/runs?token=$_token");
    final startRes = await http.post(
      startUrl,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "directUrls": [igUrl],
        "resultsType": "posts",
        "resultsLimit": 1,
        "addParentData": false,
      }),
    );

    if (startRes.statusCode != 200 && startRes.statusCode != 201) return null;
    final runId = jsonDecode(startRes.body)["data"]["id"];

    // 2. 輪詢 (Polling) 狀態
    final statusUrl = Uri.parse("https://api.apify.com/v2/actor-runs/$runId?token=$_token");
    while (true) {
      await Future.delayed(const Duration(seconds: 3)); // 每 3 秒檢查一次
      final statusRes = await http.get(statusUrl);
      if (statusRes.statusCode != 200) continue;

      final status = jsonDecode(statusRes.body)["data"]["status"];
      if (status == "SUCCEEDED") {
        final datasetId = jsonDecode(statusRes.body)["data"]["defaultDatasetId"];
        
        // 3. 取得結果 Dataset
        final datasetUrl = Uri.parse("https://api.apify.com/v2/datasets/$datasetId/items?token=$_token&format=json");
        final itemsRes = await http.get(datasetUrl);
        final List<dynamic> items = jsonDecode(itemsRes.body);

        if (items.isNotEmpty) {
          return {
            "caption": items[0]["caption"] ?? "",
            "location": items[0]["locationName"] ?? "",
          };
        }
        return null;
      } else if (["FAILED", "ABORTED", "TIMED-OUT"].contains(status)) {
        return null;
      }
    }
  }
}