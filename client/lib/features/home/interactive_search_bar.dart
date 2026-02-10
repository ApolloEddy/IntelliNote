import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';

class InteractiveSearchBar extends StatefulWidget {
  const InteractiveSearchBar({
    super.key,
    this.topOffset = 10,
    this.rightOffset = 16,
  });

  final double topOffset;
  final double rightOffset;

  @override
  State<InteractiveSearchBar> createState() => _InteractiveSearchBarState();
}

class _InteractiveSearchBarState extends State<InteractiveSearchBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _widthAnim;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();

  bool _isExpanded = false;
  bool _searchCommitted = false;
  bool _isPointerInside = false;
  Timer? _collapseTimer;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _textController.text = context.read<AppState>().notebookQuery;
    _searchCommitted = _textController.text.trim().isNotEmpty;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // 保持300ms，配合曲线会很顺滑
      reverseDuration: const Duration(milliseconds: 200),
    );
    _widthAnim = Tween<double>(begin: 48, end: 300).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _scheduleCollapseCheck() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(milliseconds: 140), _collapseIfIdle);
  }

  void _collapseIfIdle() {
    if (!_isExpanded) return;
    if (_focusNode.hasFocus) return;
    if (_isPointerInside) return;
    if (_textController.text.trim().isNotEmpty) return;
    _collapse();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
    if (_focusNode.hasFocus) {
      _collapseTimer?.cancel();
      return;
    }
    if (_isDesktop) {
      _scheduleCollapseCheck();
    }
  }

  void _expand({bool requestFocus = false}) {
    if (!_isExpanded) {
      setState(() => _isExpanded = true);
      _controller.forward();
      // Android 端点击展开后自动聚焦，Windows 端 hover 展开不一定聚焦
      if (Platform.isAndroid || requestFocus) {
        _focusNode.requestFocus();
      }
    }
  }

  void _collapse() {
    if (_isExpanded) {
      // 如果正在输入，暂时不收起？不，按需求是点击外部就收起
      _focusNode.unfocus();
      _controller.reverse().then((_) {
        if (mounted) setState(() => _isExpanded = false);
      });
    }
  }

  void _applySearch() {
    final query = _textController.text.trim();
    context.read<AppState>().searchNotebooks(query);
    if (!mounted) return;
    setState(() => _searchCommitted = query.isNotEmpty);
    _focusNode.unfocus();
  }

  void _clearSearch() {
    context.read<AppState>().searchNotebooks('');
    if (!mounted) return;
    setState(() => _searchCommitted = false);
  }

  @override
  Widget build(BuildContext context) {
    // 屏幕宽度，用于计算展开后的最大宽度（适配移动端）
    final screenWidth = MediaQuery.of(context).size.width;
    final maxSearchWidth = screenWidth - 32; // 左右留边
    
    // 更新动画目标值以适配屏幕
    if (_widthAnim.value > maxSearchWidth) {
       // 这里动态修改动画稍微有点麻烦，简单起见我们在 build 里控制 Container 宽度
    }

    final showBackdrop =
        _isExpanded &&
        !_searchCommitted &&
        (_isPointerInside || _focusNode.hasFocus);

    return Stack(
      children: [
        // 1. 遮罩层 (模糊 + 变暗) - 仅在展开时显示
        if (showBackdrop)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _focusNode.unfocus();
                if (_textController.text.trim().isEmpty) {
                  _collapse();
                }
              }, // 点击空白处收起
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5 * value, sigmaY: 5 * value),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.2 * value),
                    ),
                  );
                },
              ),
            ),
          ),

        // 2. 搜索栏主体
        Positioned(
          top: widget.topOffset, // 对应 AppBar 的位置
          right: widget.rightOffset,
          child: MouseRegion(
            onEnter: (event) {
              if (_isDesktop) {
                if (!_isPointerInside) {
                  setState(() => _isPointerInside = true);
                }
                _expand();
              }
            },
            onExit: (event) {
              if (_isDesktop) {
                if (_isPointerInside) {
                  setState(() => _isPointerInside = false);
                }
                _scheduleCollapseCheck();
              }
            },
            child: GestureDetector(
              onTap: () {
                 if (!_isExpanded) {
                   _expand(requestFocus: true);
                 } else {
                   _focusNode.requestFocus();
                 }
              },
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // 计算当前宽度
                  final currentWidth = _isExpanded 
                      ? (_isDesktop ? 400.0 : maxSearchWidth) // PC端定宽，移动端撑满
                      : 48.0;
                  
                  // 动画过程中的插值
                  final width = 48.0 + (_controller.value * (currentWidth - 48.0));
                  final theme = Theme.of(context);
                  final scheme = theme.colorScheme;
                  final isDark = theme.brightness == Brightness.dark;
                  final collapsedColor = isDark
                      ? scheme.surfaceContainer.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.88);
                  final expandedColor = isDark
                      ? scheme.surfaceContainerHigh
                      : Colors.white;

                  return Container(
                    width: width,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isExpanded ? expandedColor : collapsedColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.transparent
                            : scheme.outlineVariant.withValues(alpha: 0.85),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? (_isExpanded ? 0.2 : 0.16) : (_isExpanded ? 0.08 : 0.04)),
                          blurRadius: _isExpanded ? 10 : 6,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        // 图标
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Icon(
                            Icons.search_rounded,
                            color: _isExpanded 
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                        // 输入框 (仅展开时显示内容，但由于 Row 的约束，需要配合 Expanded)
                        Expanded(
                          child: _isExpanded
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8, right: 16),
                                  child: TextField(
                                    controller: _textController,
                                    focusNode: _focusNode,
                                    onChanged: (value) {
                                      _collapseTimer?.cancel();
                                      if (value.trim().isEmpty) {
                                        _clearSearch();
                                      } else {
                                        if (_searchCommitted) {
                                          setState(() => _searchCommitted = false);
                                        }
                                      }
                                    },
                                    onSubmitted: (_) => _applySearch(),
                                    decoration: const InputDecoration(
                                      hintText: '搜索笔记...',
                                      border: InputBorder.none,
                                      isDense: true,
                                      filled: false,
                                    ),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
