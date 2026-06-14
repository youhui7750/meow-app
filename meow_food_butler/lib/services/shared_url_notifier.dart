import 'package:flutter/foundation.dart';

class SharedUrlNotifier extends ChangeNotifier {
  String? _sharedUrl;

  String? get sharedUrl => _sharedUrl;

  void updateSharedUrl(String url) {
    if (url.trim().isEmpty) return;
    _sharedUrl = url.trim();
    notifyListeners();
  }

  void clearSharedUrl() {
    if (_sharedUrl != null) {
      _sharedUrl = null;
      notifyListeners();
    }
  }
}
