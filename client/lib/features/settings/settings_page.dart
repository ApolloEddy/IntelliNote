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
  final TextEditingController _ocrModelController = TextEditingController();
  final TextEditingController _ocrMaxPagesController = TextEditingController();
  final TextEditingController _ocrTimeoutController = TextEditingController();
  final TextEditingController _ocrTextMinController = TextEditingController();
  final TextEditingController _ocrScanMaxController = TextEditingController();
  final TextEditingController _ocrRatioController = TextEditingController();
  final TextEditingController _visionModelController = TextEditingController();
  final TextEditingController _visionMaxPagesController = TextEditingController();
  final TextEditingController _visionMaxImagesController = TextEditingController();
  final TextEditingController _visionTimeoutController = TextEditingController();
  final TextEditingController _visionMinRatioController = TextEditingController();
  bool _initialized = false;
  bool _ocrInitialized = false;
  bool _savingName = false;
  bool _savingOcr = false;
  String? _nameError;
  String? _ocrError;
  bool _ocrEnabled = false;
  bool _visionEnabled = false;
  bool _visionIncludeTextPages = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final state = context.read<AppState>();
    _nameController.text = state.displayName;
    _ocrEnabled = state.pdfOcrEnabled;
    _ocrModelController.text = state.pdfOcrModelName;
    _ocrMaxPagesController.text = state.pdfOcrMaxPages.toString();
    _ocrTimeoutController.text = state.pdfOcrTimeoutSeconds.toString();
    _ocrTextMinController.text = state.pdfTextPageMinChars.toString();
    _ocrScanMaxController.text = state.pdfScanPageMaxChars.toString();
    _ocrRatioController.text = state.pdfScanImageRatioThreshold.toStringAsFixed(2);
    _visionEnabled = state.pdfVisionEnabled;
    _visionIncludeTextPages = state.pdfVisionIncludeTextPages;
    _visionModelController.text = state.pdfVisionModelName;
    _visionMaxPagesController.text = state.pdfVisionMaxPages.toString();
    _visionMaxImagesController.text = state.pdfVisionMaxImagesPerPage.toString();
    _visionTimeoutController.text = state.pdfVisionTimeoutSeconds.toString();
    _visionMinRatioController.text = state.pdfVisionMinImageRatio.toStringAsFixed(2);
    state.loadPdfOcrConfig();
    _initialized = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ocrModelController.dispose();
    _ocrMaxPagesController.dispose();
    _ocrTimeoutController.dispose();
    _ocrTextMinController.dispose();
    _ocrScanMaxController.dispose();
    _ocrRatioController.dispose();
    _visionModelController.dispose();
    _visionMaxPagesController.dispose();
    _visionMaxImagesController.dispose();
    _visionTimeoutController.dispose();
    _visionMinRatioController.dispose();
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

  void _syncOcrForm(AppState state) {
    if (!_ocrInitialized && state.pdfOcrConfigLoaded) {
      _ocrEnabled = state.pdfOcrEnabled;
      _ocrModelController.text = state.pdfOcrModelName;
      _ocrMaxPagesController.text = state.pdfOcrMaxPages.toString();
      _ocrTimeoutController.text = state.pdfOcrTimeoutSeconds.toString();
      _ocrTextMinController.text = state.pdfTextPageMinChars.toString();
      _ocrScanMaxController.text = state.pdfScanPageMaxChars.toString();
      _ocrRatioController.text = state.pdfScanImageRatioThreshold.toStringAsFixed(2);
      _visionEnabled = state.pdfVisionEnabled;
      _visionIncludeTextPages = state.pdfVisionIncludeTextPages;
      _visionModelController.text = state.pdfVisionModelName;
      _visionMaxPagesController.text = state.pdfVisionMaxPages.toString();
      _visionMaxImagesController.text = state.pdfVisionMaxImagesPerPage.toString();
      _visionTimeoutController.text = state.pdfVisionTimeoutSeconds.toString();
      _visionMinRatioController.text = state.pdfVisionMinImageRatio.toStringAsFixed(2);
      _ocrInitialized = true;
    }
  }

  int? _parseIntInRange(String raw, {required int min, required int max}) {
    final value = int.tryParse(raw.trim());
    if (value == null) return null;
    if (value < min || value > max) return null;
    return value;
  }

  double? _parseDoubleInRange(String raw, {required double min, required double max}) {
    final value = double.tryParse(raw.trim());
    if (value == null) return null;
    if (value < min || value > max) return null;
    return value;
  }

  Future<void> _saveOcrConfig(AppState state) async {
    if (_savingOcr || state.pdfOcrConfigLoading) return;
    final modelName = _ocrModelController.text.trim();
    final maxPages = _parseIntInRange(_ocrMaxPagesController.text, min: 1, max: 200);
    final timeout = _parseIntInRange(_ocrTimeoutController.text, min: 10, max: 180);
    final textMin = _parseIntInRange(_ocrTextMinController.text, min: 1, max: 2000);
    final scanMax = _parseIntInRange(_ocrScanMaxController.text, min: 0, max: 200);
    final ratio = _parseDoubleInRange(_ocrRatioController.text, min: 0, max: 1);
    final visionModelName = _visionModelController.text.trim();
    final visionMaxPages = _parseIntInRange(_visionMaxPagesController.text, min: 1, max: 200);
    final visionMaxImages = _parseIntInRange(_visionMaxImagesController.text, min: 1, max: 12);
    final visionTimeout = _parseIntInRange(_visionTimeoutController.text, min: 8, max: 180);
    final visionMinRatio = _parseDoubleInRange(_visionMinRatioController.text, min: 0, max: 1);

    if (modelName.isEmpty) {
      setState(() => _ocrError = 'OCR 模型名称不能为空');
      return;
    }
    if (visionModelName.isEmpty) {
      setState(() => _ocrError = 'Vision 模型名称不能为空');
      return;
    }
    if (maxPages == null ||
        timeout == null ||
        textMin == null ||
        scanMax == null ||
        ratio == null ||
        visionMaxPages == null ||
        visionMaxImages == null ||
        visionTimeout == null ||
        visionMinRatio == null) {
      setState(() => _ocrError = '请输入合法参数（页数/超时/阈值范围）');
      return;
    }

    setState(() {
      _savingOcr = true;
      _ocrError = null;
    });
    final ok = await state.savePdfOcrConfig(
      enabled: _ocrEnabled,
      modelName: modelName,
      maxPages: maxPages,
      timeoutSeconds: timeout,
      textPageMinChars: textMin,
      scanPageMaxChars: scanMax,
      scanImageRatioThreshold: ratio,
      visionEnabled: _visionEnabled,
      visionModelName: visionModelName,
      visionMaxPages: visionMaxPages,
      visionMaxImagesPerPage: visionMaxImages,
      visionTimeoutSeconds: visionTimeout,
      visionMinImageRatio: visionMinRatio,
      visionIncludeTextPages: _visionIncludeTextPages,
    );
    if (!mounted) return;
    setState(() => _savingOcr = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'OCR 配置已保存' : 'OCR 配置保存失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _syncOcrForm(state);

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
          const _SectionTitle('PDF 解析 (Server)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用扫描版 PDF OCR'),
                    subtitle: const Text('关闭时仅提取文本层内容'),
                    value: _ocrEnabled,
                    onChanged: state.pdfOcrConfigLoading
                        ? null
                        : (v) => setState(() {
                              _ocrEnabled = v;
                              _ocrError = null;
                            }),
                  ),
                  TextField(
                    controller: _ocrModelController,
                    decoration: const InputDecoration(
                      labelText: 'OCR 模型名',
                      hintText: 'qwen-vl-max-latest',
                    ),
                    onChanged: (_) {
                      if (_ocrError != null) setState(() => _ocrError = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ocrMaxPagesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'OCR 最大页数 (1-200)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ocrTimeoutController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'OCR 超时秒数 (10-180)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ocrTextMinController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '文本页最小字符 (1-2000)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ocrScanMaxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '扫描页最大字符 (0-200)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ocrRatioController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '扫描页图片占比阈值 (0.0-1.0)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 PDF 图像语义识别 (Vision)'),
                    subtitle: const Text('对图表/结构图等进行非 OCR 的语义理解'),
                    value: _visionEnabled,
                    onChanged: state.pdfOcrConfigLoading
                        ? null
                        : (v) => setState(() {
                              _visionEnabled = v;
                              _ocrError = null;
                            }),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('文本型 PDF 也执行图像识别'),
                    subtitle: const Text('关闭后仅扫描页触发图像识别'),
                    value: _visionIncludeTextPages,
                    onChanged: state.pdfOcrConfigLoading
                        ? null
                        : (v) => setState(() {
                              _visionIncludeTextPages = v;
                              _ocrError = null;
                            }),
                  ),
                  TextField(
                    controller: _visionModelController,
                    decoration: const InputDecoration(
                      labelText: 'Vision 模型名',
                      hintText: 'qwen-vl-max-latest',
                    ),
                    onChanged: (_) {
                      if (_ocrError != null) setState(() => _ocrError = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _visionMaxPagesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Vision 最大页数 (1-200)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _visionMaxImagesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '每页最多图片 (1-12)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _visionTimeoutController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Vision 超时秒数 (8-180)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _visionMinRatioController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: '最小图片占比 (0.0-1.0)'),
                        ),
                      ),
                    ],
                  ),
                  if (_ocrError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _ocrError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (state.pdfOcrConfigError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '服务端错误：${state.pdfOcrConfigError}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: (_savingOcr || state.pdfOcrConfigLoading)
                            ? null
                            : () => _saveOcrConfig(state),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          (_savingOcr || state.pdfOcrConfigLoading) ? '保存中...' : '保存 OCR 配置',
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: state.pdfOcrConfigLoading
                            ? null
                            : () {
                                setState(() => _ocrInitialized = false);
                                state.loadPdfOcrConfig(force: true);
                              },
                        child: const Text('从服务端刷新'),
                      ),
                    ],
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
