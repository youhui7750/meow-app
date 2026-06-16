import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:provider/provider.dart';

/// Dialog for pasting an Instagram / Google Maps URL to import a restaurant.
class ImportInstagramDialog extends StatefulWidget {
  final String? initialUrl;

  const ImportInstagramDialog({super.key, this.initialUrl});

  @override
  State<ImportInstagramDialog> createState() => _ImportInstagramDialogState();
}

class _ImportInstagramDialogState extends State<ImportInstagramDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialUrl = widget.initialUrl?.trim();
    if (initialUrl != null && initialUrl.isNotEmpty) {
      _controller.text = initialUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startImport());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startImport() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    unawaited(context.read<SavedViewModel>().importFromUrl(url));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('匯入餐廳連結'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '貼上 Instagram Reels / Post 或 Google Maps 連結',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _startImport(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _startImport,
          child: const Text('匯入'),
        ),
      ],
    );
  }
}
