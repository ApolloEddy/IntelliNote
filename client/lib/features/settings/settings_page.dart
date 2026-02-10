import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  bool _initialized = false;
  bool _savingName = false;
  String? _nameError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _nameController.text = context.read<AppState>().displayName;
    _initialized = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateDisplayName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '称呼不能为空';
    if (trimmed.length > 24) return '称呼不能超过 24 个字符';
    return null;
  }

  Future<void> _saveDisplayName(AppState state) async {
    if (_savingName) return;
    final error = _validateDisplayName(_nameController.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }

    setState(() {
      _savingName = true;
      _nameError = null;
    });

    final normalized = _nameController.text.trim();
    final changed = normalized != state.displayName;
    state.setDisplayName(normalized);
    _nameController.text = state.displayName;

    if (mounted) {
      setState(() => _savingName = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changed ? '称呼已保存' : '称呼未变化')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _SectionTitle('外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      state.setThemeMode(selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('主题色', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kThemeAccentOptions.map((accent) {
                      final selected = state.themeAccentId == accent.id;
                      return ChoiceChip(
                        selected: selected,
                        onSelected: (_) => state.setThemeAccent(accent.id),
                        label: Text(accent.label),
                        avatar: CircleAvatar(
                          radius: 7,
                          backgroundColor: accent.color,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('用户气泡色', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: kUserBubbleToneOptions
                        .map(
                          (tone) => ButtonSegment<String>(
                            value: tone.id,
                            label: Text(tone.label),
                          ),
                        )
                        .toList(),
                    selected: {state.userBubbleToneId},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      state.setUserBubbleTone(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('通用'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    maxLength: 24,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [LengthLimitingTextInputFormatter(24)],
                    onChanged: (_) {
                      if (_nameError != null) {
                        setState(() => _nameError = null);
                      }
                    },
                    onSubmitted: (_) => _saveDisplayName(state),
                    decoration: InputDecoration(
                      labelText: '首页称呼',
                      hintText: '例如：Eddy',
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _savingName ? null : () => _saveDisplayName(state),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_savingName ? '保存中...' : '保存称呼'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          _nameController.text = 'Eddy';
                          state.setDisplayName('Eddy');
                          setState(() => _nameError = null);
                        },
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('删除 Notebook 前二次确认'),
                    value: state.confirmBeforeDeleteNotebook,
                    onChanged: state.setConfirmBeforeDeleteNotebook,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('首页显示笔记本数量'),
                    value: state.showNotebookCount,
                    onChanged: state.setShowNotebookCount,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('规划中'),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.language_outlined),
                  title: Text('界面语言'),
                  subtitle: Text('后续支持中英文切换'),
                  trailing: Text('规划中'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.keyboard_command_key_outlined),
                  title: Text('快捷键'),
                  subtitle: Text('后续支持全局快捷操作'),
                  trailing: Text('规划中'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.play_circle_outline),
                  title: Text('启动行为'),
                  subtitle: Text('后续支持打开上次会话'),
                  trailing: Text('规划中'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
