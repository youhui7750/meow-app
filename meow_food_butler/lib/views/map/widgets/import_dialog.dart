import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../view_models/instagram_import_vm.dart';

class ImportInstagramDialog extends StatefulWidget {
  const ImportInstagramDialog({super.key});

  @override
  State<ImportInstagramDialog> createState() => _ImportInstagramDialogState();
}

class _ImportInstagramDialogState extends State<ImportInstagramDialog> {
  final _controller = TextEditingController();

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
            final newExpCard = await context.read<InstagramImportViewModel>().pipelineImportAndBuildCard(_controller.text.trim());
            if (newExpCard != null && mounted) {
              Navigator.pop(context, newExpCard); // 卡片當結果回傳
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('餐廳資料自動補全並匯入成功！')));
            }
          },
          child: const Text('開始分析'),
        ),
      ],
    );
  }
}