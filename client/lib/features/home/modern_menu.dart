import 'package:flutter/material.dart';

class ModernMenuAction {
  final String title;
  final IconData icon;
  final Color? textColor;
  final Color? iconColor;
  final VoidCallback onTap;

  ModernMenuAction({
    required this.title,
    required this.icon,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });
}

class ModernMenuButton extends StatefulWidget {
  final List<ModernMenuAction> actions;
  final Widget child;

  const ModernMenuButton({
    super.key,
    required this.actions,
    required this.child,
  });

  @override
  State<ModernMenuButton> createState() => _ModernMenuButtonState();
}

class _ModernMenuButtonState extends State<ModernMenuButton>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    setState(() => _isOpen = true);
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
  }

  void _closeMenu() async {
    await _animationController.reverse();
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 点击外部关闭
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 菜单主体
          Positioned(
            width: 160,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              // 偏移调整：让菜单右上角对齐按钮中心，且稍微向下一点
              offset: Offset(-130, size.height + 10),
              child: ScaleTransition(
                scale: _scaleAnimation,
                alignment: Alignment.topRight, // 从右上角放大
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Material(
                    elevation: 0, // 手动绘制阴影，不使用默认 elevation
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? scheme.surfaceContainerHigh : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.9),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.actions.map((action) {
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                _closeMenu();
                                Future.delayed(
                                  const Duration(milliseconds: 200),
                                  action.onTap,
                                );
                              },
                              hoverColor: scheme.primary.withValues(alpha: 0.08),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      action.icon,
                                      size: 20,
                                      color: action.iconColor ??
                                          scheme.onSurface.withValues(alpha: 0.75),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      action.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: action.textColor ??
                                            scheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleMenu,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      ),
    );
  }
}
