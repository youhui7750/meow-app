import 'package:flutter/material.dart';
import 'package:meow_food_butler/view_models/app_settings_view_model.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _tagControllers = {};

  @override
  void dispose() {
    for (final controller in _tagControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String groupLabel) {
    return _tagControllers.putIfAbsent(
      groupLabel,
      TextEditingController.new,
    );
  }

  void _addTag(AppSettingsViewModel settings, String groupLabel) {
    final controller = _controllerFor(groupLabel);
    settings.addTag(groupLabel, controller.text);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag 編輯'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            '管理紀錄餐廳時可快速加入的標籤。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '快速標籤',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: settings.tagGroupLabels
                  .map(
                    (groupLabel) => _TagGroupEditor(
                      label: groupLabel,
                      tags: settings.tagsForGroup(groupLabel),
                      controller: _controllerFor(groupLabel),
                      onAdd: () => _addTag(settings, groupLabel),
                      onRemove: (tag) => settings.removeTag(groupLabel, tag),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TagGroupEditor extends StatelessWidget {
  final String label;
  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _TagGroupEditor({
    required this.label,
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => InputChip(
                    label: Text('#$tag'),
                    onDeleted: () => onRemove(tag),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: InputDecoration(
                    hintText: '新增 $label tag',
                    prefixIcon: const Icon(Icons.tag),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                tooltip: '新增 tag',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
