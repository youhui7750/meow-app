import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';

/// Dialog for pasting an Instagram / Google Maps URL to import a restaurant.
///
/// The import itself runs in the background via [SavedViewModel.importFromUrl]
/// and is non-blocking: the dialog closes immediately once the user confirms,
/// and progress + completion are surfaced via bottom SnackBar notifications.
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
    if (widget.initialUrl != null && widget.initialUrl!.trim().isNotEmpty) {
      _controller.text = widget.initialUrl!.trim();
      // Auto-start import for shared URLs — close dialog instantly.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startImport());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startImport() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    // Fire-and-forget: import runs in background, progress via SnackBar stream.
    unawaited(context.read<SavedViewModel>().importFromUrl(url));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('💡 智慧貼文匯入餐廳'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '請貼上 IG Reels / Post 或 Google Maps 連結',
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
          child: const Text('開始分析'),
        ),
      ],
    );
  }
}
