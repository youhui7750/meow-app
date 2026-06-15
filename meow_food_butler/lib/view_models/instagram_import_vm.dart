import 'package:flutter/material.dart';

import '../services/instagram_import_service.dart';

// Re-export so existing importers (e.g. main_map_screen) keep resolving
// `InstagramImportResult` from this view model.
export '../services/instagram_import_service.dart' show InstagramImportResult;

/// Thin presentation wrapper around [InstagramImportService]. The whole import
/// pipeline (Apify scrape -> AI name extraction -> Outscraper enrichment) now runs
/// in the `importInstagram` Cloud Function; this only owns the loading/error UI
/// state the dialog renders.
class InstagramImportViewModel extends ChangeNotifier {
  final InstagramImportService _service = InstagramImportService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _loadingMessage = "";
  String get loadingMessage => _loadingMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<InstagramImportResult?> pipelineImportAndBuildCard(String igUrl) async {
    _errorMessage = null;
    _isLoading = true;
    _loadingMessage = "正在分析貼文並向 Google Maps 補全店家資訊...";
    notifyListeners();

    try {
      final result = await _service.import(igUrl);
      _isLoading = false;
      _loadingMessage = "";
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      _loadingMessage = "";
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }
}
