import 'package:flutter/foundation.dart';

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
      '拉麵',
      '火鍋',
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

  Map<String, List<String>> _tagGroups = _defaultTagGroups;

  List<String> get tagGroupLabels => List.unmodifiable(_tagGroups.keys);

  List<String> tagsForGroup(String label) {
    return List.unmodifiable(_tagGroups[label] ?? const []);
  }

  List<AppTagGroup> get quickTagGroups {
    return _tagGroups.entries
        .map((entry) => AppTagGroup(label: entry.key, tags: entry.value))
        .toList();
  }

  void addTag(String groupLabel, String rawTag) {
    final tag = _normalizeTag(rawTag);
    final currentTags = _tagGroups[groupLabel] ?? const <String>[];
    if (tag.isEmpty || currentTags.contains(tag)) return;

    _tagGroups = {
      ..._tagGroups,
      groupLabel: [...currentTags, tag],
    };
    notifyListeners();
  }

  void removeTag(String groupLabel, String tag) {
    final currentTags = _tagGroups[groupLabel] ?? const <String>[];
    final nextTags = currentTags.where((item) => item != tag).toList();
    if (nextTags.length == currentTags.length) return;

    _tagGroups = {
      ..._tagGroups,
      groupLabel: nextTags,
    };
    notifyListeners();
  }

  String _normalizeTag(String rawTag) {
    return rawTag.trim().replaceAll(RegExp(r'\s+'), '-');
  }
}
