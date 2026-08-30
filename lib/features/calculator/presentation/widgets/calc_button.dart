import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/calculator_theme.dart';

/// Visual roles a calculator key can take.
enum CalcKeyStyle { digit, operator, function, destructive, accent }

/// A single calculator key with light haptic feedback.
///
/// [onPressStart]/[onPressEnd] expose raw pointer transitions so callers can
/// observe press-and-hold gestures without interfering with the tap handler.
class CalcButton extends StatefulWidget {
  const CalcButton({
    required this.label,
    required this.onTap,
    this.style = CalcKeyStyle.digit,
    this.height = 64,
    this.fontSize,
    this.onPressStart,
    this.onPressEnd,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final CalcKeyStyle style;
  final double height;
  final double? fontSize;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;
  final String? semanticLabel;

  @override
  State<CalcButton> createState() => _CalcButtonState();
}

class _CalcButtonState extends State<CalcButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  Color get _background {
    switch (widget.style) {
      case CalcKeyStyle.digit:
        return CalculatorTheme.keyBackground;
      case CalcKeyStyle.operator:
        return CalculatorTheme.accent;
      case CalcKeyStyle.function:
        return CalculatorTheme.keyMuted;
      case CalcKeyStyle.destructive:
        return CalculatorTheme.destructive;
      case CalcKeyStyle.accent:
        return CalculatorTheme.accentPressed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = _pressed
        ? Color.alphaBlend(Colors.white24, _background)
        : _background;

    return Listener(
      onPointerDown: (_) {
        _setPressed(true);
        widget.onPressStart?.call();
      },
      onPointerUp: (_) {
        _setPressed(false);
        widget.onPressEnd?.call();
      },
      onPointerCancel: (_) {
        _setPressed(false);
        widget.onPressEnd?.call();
      },
      child: Semantics(
        button: true,
        label: widget.semanticLabel ?? widget.label,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(CalculatorTheme.keyRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(CalculatorTheme.keyRadius),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: SizedBox(
              height: widget.height,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: CalculatorTheme.primaryText,
                        fontSize:
                            widget.fontSize ??
                            (widget.style == CalcKeyStyle.function ? 17 : 22),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
