import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CalculatorShellScreen extends StatefulWidget {
  const CalculatorShellScreen({
    required this.onVaultTriggerRequested,
    required this.onShowVaultEntryHelp,
    required this.showOnboardingCard,
    super.key,
  });

  final VoidCallback onVaultTriggerRequested;
  final VoidCallback onShowVaultEntryHelp;
  final bool showOnboardingCard;

  @override
  State<CalculatorShellScreen> createState() => _CalculatorShellScreenState();
}

class _CalculatorShellScreenState extends State<CalculatorShellScreen> {
  static const Duration _triggerHoldDuration = Duration(milliseconds: 1200);
  static const Duration _triggerCooldown = Duration(milliseconds: 900);

  final List<String> _expressionTokens = <String>[];
  String _display = '0';
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

  void _onDigitTap(String digit) {
    if (_display == '0' || _wasLastActionEquals) {
      _display = digit;
      if (_wasLastActionEquals) {
        _expressionTokens.clear();
      }
    } else {
      _display += digit;
    }
    setState(() {});
  }

  void _onDecimalTap() {
    if (_wasLastActionEquals) {
      _expressionTokens.clear();
      _display = '0.';
    } else if (!_display.contains('.')) {
      _display = '$_display.';
    }
    setState(() {});
  }

  void _onOperatorTap(String operator) {
    if (_expressionTokens.isEmpty && _display == 'Error') {
      _clearAll();
      return;
    }
    if (_expressionTokens.isNotEmpty && _isOperator(_expressionTokens.last)) {
      _expressionTokens[_expressionTokens.length - 1] = operator;
    } else {
      _expressionTokens.add(_display);
      _expressionTokens.add(operator);
    }
    _display = '0';
    setState(() {});
  }

  void _onEqualsTap() {
    if (_display == 'Error') {
      _clearAll();
      return;
    }
    if (_expressionTokens.isEmpty) return;
    if (!_isOperator(_expressionTokens.last)) {
      _expressionTokens.add(_display);
    } else {
      _expressionTokens.add(_display);
    }
    final result = _evaluateExpression(_expressionTokens);
    _expressionTokens
      ..clear()
      ..add(result);
    _display = result;
    setState(() {});
  }

  void _onBackspace() {
    if (_wasLastActionEquals) {
      _display = '0';
      _expressionTokens.clear();
    } else if (_display.length > 1) {
      _display = _display.substring(0, _display.length - 1);
    } else {
      _display = '0';
    }
    setState(() {});
  }

  void _clearAll() {
    _expressionTokens.clear();
    _display = '0';
    setState(() {});
  }

  bool get _wasLastActionEquals =>
      _expressionTokens.length == 1 && !_isOperator(_expressionTokens.single);

  void _handleTriggerPressStart(_TriggerKey key) {
    if (_triggerLocked) return;
    setState(() {
      if (key == _TriggerKey.seven) {
        _holdingSeven = true;
      } else {
        _holdingEquals = true;
      }
    });
    _startTriggerTimerIfNeeded();
  }

  void _handleTriggerPressEnd(_TriggerKey key) {
    _triggerTimer?.cancel();
    setState(() {
      if (key == _TriggerKey.seven) {
        _holdingSeven = false;
      } else {
        _holdingEquals = false;
      }
    });
  }

  void _startTriggerTimerIfNeeded() {
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
      });
      if (mounted) {
        setState(() {});
      }
      widget.onVaultTriggerRequested();
    });
  }

  String _evaluateExpression(List<String> tokens) {
    try {
      if (tokens.isEmpty) return _display;
      final queue = List<String>.from(tokens);
      double result = double.parse(queue.removeAt(0));
      while (queue.length >= 2) {
        final operator = queue.removeAt(0);
        final operand = double.parse(queue.removeAt(0));
        switch (operator) {
          case '+':
            result += operand;
          case '-':
            result -= operand;
          case 'x':
            result *= operand;
          case '÷':
            if (operand == 0) return 'Error';
            result /= operand;
          default:
            return 'Error';
        }
      }
      final isWholeNumber = result == result.roundToDouble();
      return isWholeNumber ? result.toInt().toString() : result.toString();
    } catch (_) {
      return 'Error';
    }
  }

  bool _isOperator(String value) =>
      value == '+' || value == '-' || value == 'x' || value == '÷';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expressionText = _expressionTokens.isEmpty
        ? 'Standard calculator'
        : _expressionTokens.join(' ');

    return Scaffold(
      backgroundColor: const Color(0xFF10131B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                        'Calculator',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fast calculations, with optional private vault access',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onShowVaultEntryHelp,
                    tooltip: 'Vault entry help',
                    icon: const Icon(Icons.lock_outline_rounded, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    tooltip: 'Settings',
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (widget.showOnboardingCard) ...[
                        const SizedBox(height: 20),
                        _EntryHintCard(onDismiss: widget.onShowVaultEntryHelp),
                      ] else
                        const SizedBox(height: 12),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171B25),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 24,
                              offset: Offset(0, 18),
                              color: Color(0x33000000),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              expressionText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _CalculatorKeypad(
                        onClear: _clearAll,
                        onBackspace: _onBackspace,
                        onDigitTap: _onDigitTap,
                        onDecimalTap: _onDecimalTap,
                        onOperatorTap: _onOperatorTap,
                        onEqualsTap: _onEqualsTap,
                        onTriggerPressStart: _handleTriggerPressStart,
                        onTriggerPressEnd: _handleTriggerPressEnd,
                        triggerActive: _holdingSeven || _holdingEquals,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TriggerKey { seven, equals }

class _EntryHintCard extends StatelessWidget {
  const _EntryHintCard({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2431),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Private vault entry',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Hold 7 and = together for a moment to open the passcode screen.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDismiss,
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalculatorKeypad extends StatelessWidget {
  const _CalculatorKeypad({
    required this.onClear,
    required this.onBackspace,
    required this.onDigitTap,
    required this.onDecimalTap,
    required this.onOperatorTap,
    required this.onEqualsTap,
    required this.onTriggerPressStart,
    required this.onTriggerPressEnd,
    required this.triggerActive,
  });

  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final ValueChanged<String> onDigitTap;
  final VoidCallback onDecimalTap;
  final ValueChanged<String> onOperatorTap;
  final VoidCallback onEqualsTap;
  final ValueChanged<_TriggerKey> onTriggerPressStart;
  final ValueChanged<_TriggerKey> onTriggerPressEnd;
  final bool triggerActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _CalcKey(label: 'AC', onTap: onClear, accent: true)),
            const SizedBox(width: 12),
            Expanded(
              child: _CalcKey(
                label: '⌫',
                onTap: onBackspace,
                accent: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CalcKey(
                label: '÷',
                onTap: () => onOperatorTap('÷'),
                accent: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CalcKey(
                label: 'x',
                onTap: () => onOperatorTap('x'),
                accent: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _digitRow(context, ['7', '8', '9'], operator: '-'),
        const SizedBox(height: 12),
        _digitRow(context, ['4', '5', '6'], operator: '+'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CalcKey(label: '1', onTap: () => onDigitTap('1')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CalcKey(label: '2', onTap: () => onDigitTap('2')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CalcKey(label: '3', onTap: () => onDigitTap('3')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HoldableCalcKey(
                label: '=',
                highlighted: triggerActive,
                onTap: onEqualsTap,
                onHoldStart: () => onTriggerPressStart(_TriggerKey.equals),
                onHoldEnd: () => onTriggerPressEnd(_TriggerKey.equals),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _CalcKey(label: '0', onTap: () => onDigitTap('0')),
            ),
            const SizedBox(width: 12),
            Expanded(child: _CalcKey(label: '.', onTap: onDecimalTap)),
          ],
        ),
      ],
    );
  }

  Widget _digitRow(
    BuildContext context,
    List<String> digits, {
    required String operator,
  }) {
    return Row(
      children: [
        for (var index = 0; index < digits.length; index++) ...[
          Expanded(
            child: digits[index] == '7'
                ? _HoldableCalcKey(
                    label: '7',
                    highlighted: triggerActive,
                    onTap: () => onDigitTap('7'),
                    onHoldStart: () => onTriggerPressStart(_TriggerKey.seven),
                    onHoldEnd: () => onTriggerPressEnd(_TriggerKey.seven),
                  )
                : _CalcKey(
                    label: digits[index],
                    onTap: () => onDigitTap(digits[index]),
                  ),
          ),
          if (index < digits.length - 1) const SizedBox(width: 12),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: _CalcKey(
            label: operator,
            onTap: () => onOperatorTap(operator),
            accent: true,
          ),
        ),
      ],
    );
  }
}

class _CalcKey extends StatelessWidget {
  const _CalcKey({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: accent ? const Color(0xFF4B6BFB) : const Color(0xFF232938),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
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
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldEnd(),
      onPointerCancel: (_) => onHoldEnd(),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: highlighted
              ? const Color(0xFF6B8BFF)
              : const Color(0xFF232938),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(72),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
