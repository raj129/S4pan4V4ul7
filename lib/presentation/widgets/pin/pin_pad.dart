import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Reusable secure PIN entry grid.
///
/// Renders the standard 3x4 numeric layout (1-9, optional leading affordance,
/// 0, backspace or trailing affordance). Digits are emitted only through
/// [onDigit]; no PIN value is stored by this widget.
class PinPad extends StatelessWidget {
  const PinPad({
    required this.onDigit,
    required this.onDelete,
    super.key,
    this.enabled = true,
    this.leading,
    this.trailing,
    this.onTrailing,
    this.padding,
    this.keySize = AppSpacing.huge + AppSpacing.xl,
    this.spacing = AppSpacing.md,
  });

  /// Called when a number key is pressed.
  final ValueChanged<int> onDigit;

  /// Called by the default backspace key when [trailing] is not supplied.
  final VoidCallback onDelete;

  /// Disables all keys while preserving layout.
  final bool enabled;

  /// Optional bottom-left affordance. When omitted, the cell stays empty.
  final Widget? leading;

  /// Optional bottom-right affordance. When omitted, a backspace key is shown.
  final Widget? trailing;

  /// Tap handler for [trailing]. If omitted, [onDelete] is used.
  final VoidCallback? onTrailing;

  /// Outer padding around the keypad.
  final EdgeInsetsGeometry? padding;

  /// Circular key diameter. Defaults to a large accessible touch target.
  final double keySize;

  /// Gap between keypad rows.
  final double spacing;

  static const _layout = <List<int>>[
    <int>[1, 2, 3],
    <int>[4, 5, 6],
    <int>[7, 8, 9],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[
      for (final row in _layout)
        _PinPadRow(
          children: [
            for (final digit in row)
              PinKey(
                onTap: () => onDigit(digit),
                enabled: enabled,
                size: keySize,
                semanticLabel: 'Digit $digit',
                child: Text('$digit', style: theme.textTheme.headlineMedium),
              ),
          ],
        ),
      _PinPadRow(
        children: [
          SizedBox.square(
            dimension: keySize,
            child: Center(child: leading),
          ),
          PinKey(
            onTap: () => onDigit(0),
            enabled: enabled,
            size: keySize,
            semanticLabel: 'Digit 0',
            child: Text('0', style: theme.textTheme.headlineMedium),
          ),
          PinKey(
            onTap: onTrailing ?? onDelete,
            enabled: enabled,
            size: keySize,
            semanticLabel: trailing == null ? 'Delete digit' : null,
            child: trailing ?? const Icon(Icons.backspace_outlined),
          ),
        ],
      ),
    ];

    return Padding(
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.lg,
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _PinPadRow extends StatelessWidget {
  const _PinPadRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: children,
    );
  }
}

/// Circular PIN keypad key with ripple, pressed feedback, and light haptics.
class PinKey extends StatefulWidget {
  const PinKey({
    required this.child,
    required this.onTap,
    super.key,
    this.enabled = true,
    this.size = AppSpacing.huge + AppSpacing.xl,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  final double size;
  final String? semanticLabel;

  @override
  State<PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<PinKey> {
  bool _pressed = false;

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.enabled;
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    final key = AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: AppDuration.fast,
      child: Material(
        color: _pressed
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: enabled ? _handleTap : null,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          containedInkWell: true,
          customBorder: const CircleBorder(),
          radius: widget.size / 2,
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: SizedBox.square(
                dimension: widget.size,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.semanticLabel == null) return key;
    return Semantics(button: true, label: widget.semanticLabel, child: key);
  }
}

/// Animated filled/empty PIN dots.
///
/// Set [hasError] to true to tint the dots and run a short shake animation.
class PinDotRow extends StatefulWidget {
  const PinDotRow({
    required this.filledCount,
    required this.total,
    super.key,
    this.hasError = false,
    this.dotSize = AppSpacing.lg,
  });

  final int filledCount;
  final int total;
  final bool hasError;
  final double dotSize;

  @override
  State<PinDotRow> createState() => _PinDotRowState();
}

class _PinDotRowState extends State<PinDotRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: AppDuration.normal,
    );
    if (widget.hasError) _shakeController.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant PinDotRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = context.semantic.danger;
    final activeColor = widget.hasError
        ? errorColor
        : theme.colorScheme.primary;
    final emptyColor = widget.hasError
        ? errorColor.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;
    final clampedFilled = widget.filledCount.clamp(0, widget.total);

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final value = _shakeController.value;
        final offset =
            math.sin(value * math.pi * 4) * AppSpacing.sm * (1 - value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.total, (index) {
          final filled = index < clampedFilled;
          final size = filled ? widget.dotSize : widget.dotSize - AppSpacing.xs;
          return AnimatedContainer(
            duration: AppDuration.fast,
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? activeColor : Colors.transparent,
              border: Border.all(
                color: filled ? activeColor : emptyColor,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }
}
