import 'package:flutter/foundation.dart';

enum AppLanguage { traditionalChinese, english }

class AppTagGroup {
  final String label;
  final List<String> tags;

  const AppTagGroup({
    required this.label,
    required this.tags,
  });
}

class AppSettingsViewModel extends ChangeNotifier {
  static const Map<String, List<String>> _defaultTagGroups = {
    '料理類型': [
      '日式',
      '韓式',
      '台式',
      '義式',
      '咖啡廳',
      '甜點',
      '火鍋',
      '小吃',
    ],
    '價格': [
      '平價',
      'CP值高',
      '偏貴',
    ],
    '氣氛': [
      '氣氛好',
      '安靜',
      '熱鬧',
      '適合拍照',
    ],
    '用餐情境': [
      '朋友聚餐',
      '約會適合',
      '一個人可',
      '適合聊天',
    ],
    '特色': [
      '服務好',
      '出餐快',
      '需要排隊',
      '交通方便',
    ],
  };

  AppLanguage _language = AppLanguage.traditionalChinese;
  bool _notificationsEnabled = true;
  Map<String, List<String>>? _tagGroups = _defaultTagGroups;

  Map<String, List<String>> get _resolvedTagGroups {
    return _tagGroups ??= _defaultTagGroups;
  }

  AppLanguage get language => _language;
  bool get notificationsEnabled => _notificationsEnabled;
  List<String> get tagGroupLabels => List.unmodifiable(_resolvedTagGroups.keys);

  List<String> tagsForGroup(String label) {
    return List.unmodifiable(_resolvedTagGroups[label] ?? const []);
  }

  List<AppTagGroup> get quickTagGroups {
    return _resolvedTagGroups.entries
        .map((entry) => AppTagGroup(label: entry.key, tags: entry.value))
        .toList();
  }

  void setLanguage(AppLanguage language) {
    if (_language == language) return;
    _language = language;
    notifyListeners();
  }

  void setNotificationsEnabled(bool enabled) {
    if (_notificationsEnabled == enabled) return;
    _notificationsEnabled = enabled;
    notifyListeners();
  }

  void addTag(String groupLabel, String rawTag) {
    final tag = _normalizeTag(rawTag);
    final currentGroups = _resolvedTagGroups;
    final currentTags = currentGroups[groupLabel] ?? const <String>[];
    if (tag.isEmpty || currentTags.contains(tag)) return;

    _tagGroups = {
      ...currentGroups,
      groupLabel: [...currentTags, tag],
    };
    notifyListeners();
  }

  void removeTag(String groupLabel, String tag) {
    final currentGroups = _resolvedTagGroups;
    final currentTags = currentGroups[groupLabel] ?? const <String>[];
    final nextTags = currentTags.where((item) => item != tag).toList();
    if (nextTags.length == currentTags.length) return;

    _tagGroups = {
      ...currentGroups,
      groupLabel: nextTags,
    };
    notifyListeners();
  }

  String _normalizeTag(String rawTag) {
    return rawTag.trim().replaceAll(RegExp(r'\s+'), '-');
  }
}
