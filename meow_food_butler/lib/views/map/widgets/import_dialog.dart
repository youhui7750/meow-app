import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../view_models/instagram_import_vm.dart';

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoImportSharedUrl();
      });
    }
  }

  Future<void> _autoImportSharedUrl() async {
    if (!mounted) return;
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    final viewModel = context.read<InstagramImportViewModel>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final newExpCard = await viewModel.pipelineImportAndBuildCard(url);
    if (!mounted) return;
    if (newExpCard != null) {
      navigator.pop(newExpCard);
      messenger.showSnackBar(const SnackBar(content: Text('餐廳資料自動補全並匯入成功！')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InstagramImportViewModel>();

    return AlertDialog(
      title: const Text('💡 智慧貼文匯入餐廳'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            enabled: !vm.isLoading,
            decoration: InputDecoration(
              hintText: '請貼上 IG Reels / Post 連結',
              errorText: vm.errorMessage,
              border: const OutlineInputBorder(),
            ),
          ),
          if (vm.isLoading) ...[
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(vm.loadingMessage, style: const TextStyle(fontSize: 12, color: Colors.blue), textAlign: TextAlign.center),
          ]
        ],
      ),
      actions: [
        TextButton(
          onPressed: vm.isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: vm.isLoading ? null : () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final newExpCard = await context.read<InstagramImportViewModel>().pipelineImportAndBuildCard(_controller.text.trim());
            if (newExpCard != null && mounted) {
              navigator.pop(newExpCard); // 卡片當結果回傳
              messenger.showSnackBar(const SnackBar(content: Text('餐廳資料自動補全並匯入成功！')));
            }
          },
          child: const Text('開始分析'),
        ),
      ],
    );
  }
}