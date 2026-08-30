import 'dart:async';

import 'package:flutter/material.dart';

class CalculatorFeature extends StatefulWidget {
  const CalculatorFeature({required this.onVaultTriggerRequested, super.key});

  final VoidCallback onVaultTriggerRequested;

  @override
  State<CalculatorFeature> createState() => _CalculatorFeatureState();
}

class _CalculatorFeatureState extends State<CalculatorFeature> {
  static const Duration _triggerHoldDuration = Duration(milliseconds: 1200);
  static const Duration _triggerCooldown = Duration(milliseconds: 800);

  final List<String> _history = <String>[];
  final List<String> _memory = <String>[];

  String _display = '0';
  String _pendingOperator = '';
  String _storedValue = '0';
  bool _waitingForNextInput = false;
  bool _holdingSeven = false;
  bool _holdingEquals = false;
  bool _triggerLocked = false;
  Timer? _triggerTimer;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _appendDigit(String digit) {
    if (_waitingForNextInput || _display == '0') {
      _display = digit;
      _waitingForNextInput = false;
    } else {
      _display += digit;
    }
    setState(() {});
  }

  void _appendDecimal() {
    if (_waitingForNextInput) {
      _display = '0.';
      _waitingForNextInput = false;
    } else if (!_display.contains('.')) {
      _display = '$_display.';
    }
    setState(() {});
  }

  void _toggleSign() {
    final value = double.tryParse(_display) ?? 0;
    _display = _formatResult(-value);
    setState(() {});
  }

  void _applyPercent() {
    final value = double.tryParse(_display) ?? 0;
    _display = _formatResult(value / 100);
    setState(() {});
  }

  void _handleOperator(String operator) {
    if (_pendingOperator.isNotEmpty && !_waitingForNextInput) {
      _performCalculation();
    }
    _storedValue = _display;
    _pendingOperator = operator;
    _waitingForNextInput = true;
    setState(() {});
  }

  void _performCalculation() {
    if (_pendingOperator.isEmpty) return;
    final left = double.tryParse(_storedValue) ?? 0;
    final right = double.tryParse(_display) ?? 0;
    double result = 0;

    switch (_pendingOperator) {
      case '+':
        result = left + right;
      case '-':
        result = left - right;
      case '×':
        result = left * right;
      case '÷':
        if (right == 0) {
          _display = 'Error';
          _pendingOperator = '';
          _waitingForNextInput = false;
          setState(() {});
          return;
        }
        result = left / right;
      default:
        result = right;
    }

    final formatted = _formatResult(result);
    _history.add('$_storedValue $_pendingOperator $_display = $formatted');
    if (_history.length > 12) {
      _history.removeAt(0);
    }
    _display = formatted;
    _pendingOperator = '';
    _waitingForNextInput = false;
    setState(() {});
  }

  void _onEquals() {
    if (_pendingOperator.isEmpty) return;
    _performCalculation();
  }

  void _clearAll() {
    _display = '0';
    _storedValue = '0';
    _pendingOperator = '';
    _waitingForNextInput = false;
    setState(() {});
  }

  void _backspace() {
    if (_display.length <= 1) {
      _display = '0';
    } else {
      _display = _display.substring(0, _display.length - 1);
    }
    setState(() {});
  }

  void _memoryClear() {
    _memory.clear();
    setState(() {});
  }

  void _memoryRecall() {
    if (_memory.isEmpty) return;
    _display = _memory.last;
    setState(() {});
  }

  void _memoryAdd() {
    final current = double.tryParse(_display) ?? 0;
    final total = (_memory.isEmpty ? '0' : _memory.last);
    final value = (double.tryParse(total) ?? 0) + current;
    _memory.add(_formatResult(value));
    if (_memory.length > 5) {
      _memory.removeAt(0);
    }
    setState(() {});
  }

  void _memorySubtract() {
    final current = double.tryParse(_display) ?? 0;
    final total = (_memory.isEmpty ? '0' : _memory.last);
    final value = (double.tryParse(total) ?? 0) - current;
    _memory.add(_formatResult(value));
    if (_memory.length > 5) {
      _memory.removeAt(0);
    }
    setState(() {});
  }

  void _handleTriggerPressStart(_TriggerKey key) {
    if (_triggerLocked) return;
    setState(() {
      if (key == _TriggerKey.seven) {
        _holdingSeven = true;
      } else {
        _holdingEquals = true;
      }
    });
    if (!_holdingSeven || !_holdingEquals || _triggerTimer != null) return;
    _triggerTimer = Timer(_triggerHoldDuration, () {
      _triggerTimer = null;
      if (!_holdingSeven || !_holdingEquals || _triggerLocked) return;
      _triggerLocked = true;
      _holdingSeven = false;
      _holdingEquals = false;
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(_triggerCooldown, () {
        _triggerLocked = false;
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
      widget.onVaultTriggerRequested();
    });
  }

  void _handleTriggerPressEnd(_TriggerKey key) {
    _triggerTimer?.cancel();
    _triggerTimer = null;
    setState(() {
      if (key == _TriggerKey.seven) {
        _holdingSeven = false;
      } else {
        _holdingEquals = false;
      }
    });
  }

  String _formatResult(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';
    final isWhole = value == value.roundToDouble();
    if (isWhole) {
      return value.toInt().toString();
    }
    final formatted = value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'\.0+$'), '');
    return formatted
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171B25),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 22,
                        offset: Offset(0, 16),
                        color: Color(0x33000000),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_history.isNotEmpty) ...[
                        Text(
                          _history.last,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        _display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _CalcAction(label: 'MC', onTap: _memoryClear),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CalcAction(label: 'MR', onTap: _memoryRecall),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CalcAction(label: 'M+', onTap: _memoryAdd),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CalcAction(label: 'M−', onTap: _memorySubtract),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CalculatorKeypad(
                  isCompact: isCompact,
                  onDigitTap: _appendDigit,
                  onDecimalTap: _appendDecimal,
                  onOperatorTap: _handleOperator,
                  onEqualsTap: _onEquals,
                  onClear: _clearAll,
                  onBackspace: _backspace,
                  onPercent: _applyPercent,
                  onToggleSign: _toggleSign,
                  onTriggerPressStart: _handleTriggerPressStart,
                  onTriggerPressEnd: _handleTriggerPressEnd,
                  triggerActive: _holdingSeven || _holdingEquals,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _TriggerKey { seven, equals }

class _CalculatorKeypad extends StatelessWidget {
  const _CalculatorKeypad({
    required this.onDigitTap,
    required this.onDecimalTap,
    required this.onOperatorTap,
    required this.onEqualsTap,
    required this.onClear,
    required this.onBackspace,
    required this.onPercent,
    required this.onToggleSign,
    required this.onTriggerPressStart,
    required this.onTriggerPressEnd,
    required this.triggerActive,
    required this.isCompact,
  });

  final ValueChanged<String> onDigitTap;
  final VoidCallback onDecimalTap;
  final ValueChanged<String> onOperatorTap;
  final VoidCallback onEqualsTap;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final VoidCallback onPercent;
  final VoidCallback onToggleSign;
  final ValueChanged<_TriggerKey> onTriggerPressStart;
  final ValueChanged<_TriggerKey> onTriggerPressEnd;
  final bool triggerActive;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final rowSpacing = isCompact ? 8.0 : 12.0;
    final keyHeight = isCompact ? 62.0 : 72.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CalcKey(
                label: 'C',
                onTap: onClear,
                accent: true,
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '±',
                onTap: onToggleSign,
                accent: true,
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '%',
                onTap: onPercent,
                accent: true,
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '÷',
                onTap: () => onOperatorTap('÷'),
                accent: true,
                height: keyHeight,
              ),
            ),
          ],
        ),
        SizedBox(height: rowSpacing),
        Row(
          children: [
            Expanded(
              child: _CalcKey(
                label: '7',
                onTap: () => onDigitTap('7'),
                height: keyHeight,
                triggerKey: _TriggerKey.seven,
                onHoldStart: () => onTriggerPressStart(_TriggerKey.seven),
                onHoldEnd: () => onTriggerPressEnd(_TriggerKey.seven),
                highlighted: triggerActive,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '8',
                onTap: () => onDigitTap('8'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '9',
                onTap: () => onDigitTap('9'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '×',
                onTap: () => onOperatorTap('×'),
                accent: true,
                height: keyHeight,
              ),
            ),
          ],
        ),
        SizedBox(height: rowSpacing),
        Row(
          children: [
            Expanded(
              child: _CalcKey(
                label: '4',
                onTap: () => onDigitTap('4'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '5',
                onTap: () => onDigitTap('5'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '6',
                onTap: () => onDigitTap('6'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '-',
                onTap: () => onOperatorTap('-'),
                accent: true,
                height: keyHeight,
              ),
            ),
          ],
        ),
        SizedBox(height: rowSpacing),
        Row(
          children: [
            Expanded(
              child: _CalcKey(
                label: '1',
                onTap: () => onDigitTap('1'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '2',
                onTap: () => onDigitTap('2'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '3',
                onTap: () => onDigitTap('3'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '+',
                onTap: () => onOperatorTap('+'),
                accent: true,
                height: keyHeight,
              ),
            ),
          ],
        ),
        SizedBox(height: rowSpacing),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _CalcKey(
                label: '0',
                onTap: () => onDigitTap('0'),
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CalcKey(
                label: '.',
                onTap: onDecimalTap,
                height: keyHeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HoldableCalcKey(
                label: '=',
                onTap: onEqualsTap,
                onHoldStart: () => onTriggerPressStart(_TriggerKey.equals),
                onHoldEnd: () => onTriggerPressEnd(_TriggerKey.equals),
                highlighted: triggerActive,
                height: keyHeight,
                accent: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CalcAction extends StatelessWidget {
  const _CalcAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF232938),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _CalcKey extends StatelessWidget {
  const _CalcKey({
    required this.label,
    required this.onTap,
    this.accent = false,
    this.height = 72,
    this.triggerKey,
    this.onHoldStart,
    this.onHoldEnd,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool accent;
  final double height;
  final _TriggerKey? triggerKey;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: accent
            ? (highlighted ? const Color(0xFF6B8BFF) : const Color(0xFF4B6BFB))
            : (highlighted ? const Color(0xFF6B8BFF) : const Color(0xFF232938)),
        foregroundColor: Colors.white,
        minimumSize: Size.fromHeight(height),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    );

    if (onHoldStart == null || onHoldEnd == null) {
      return button;
    }

    return Listener(
      onPointerDown: (_) => onHoldStart!(),
      onPointerUp: (_) => onHoldEnd!(),
      onPointerCancel: (_) => onHoldEnd!(),
      child: button,
    );
  }
}

class _HoldableCalcKey extends StatelessWidget {
  const _HoldableCalcKey({
    required this.label,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.highlighted,
    this.height = 72,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool highlighted;
  final double height;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldEnd(),
      onPointerCancel: (_) => onHoldEnd(),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: accent
              ? (highlighted
                    ? const Color(0xFF6B8BFF)
                    : const Color(0xFF4B6BFB))
              : const Color(0xFF232938),
          foregroundColor: Colors.white,
          minimumSize: Size.fromHeight(height),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
