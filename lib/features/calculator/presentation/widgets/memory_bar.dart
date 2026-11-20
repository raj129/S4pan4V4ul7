import 'package:flutter/material.dart';

import '../theme/calculator_theme.dart';
import 'keypad_layouts.dart';

/// The `MC / MR / M+ / M−` row plus the scientific-pad toggle.
class MemoryBar extends StatelessWidget {
  const MemoryBar({
    required this.onMemoryClear,
    required this.onMemoryRecall,
    required this.onMemoryAdd,
    required this.onMemorySubtract,
    required this.onToggleScientific,
    required this.scientificExpanded,
    required this.memoryActive,
    this.onKeyPressStart,
    this.onKeyPressEnd,
    this.onKeyTap,
    super.key,
  });

  final VoidCallback onMemoryClear;
  final VoidCallback onMemoryRecall;
  final VoidCallback onMemoryAdd;
  final VoidCallback onMemorySubtract;
  final VoidCallback onToggleScientific;
  final bool scientificExpanded;
  final bool memoryActive;
  final ValueChanged<String>? onKeyPressStart;
  final ValueChanged<String>? onKeyPressEnd;
  final ValueChanged<String>? onKeyTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _MemoryChip(
          key: const ValueKey<String>(kMemoryClearKeyId),
          keyId: kMemoryClearKeyId,
          label: 'MC',
          onTap: onMemoryClear,
          enabled: memoryActive,
          onPressStart: onKeyPressStart,
          onPressEnd: onKeyPressEnd,
          onRawTap: onKeyTap,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(
          key: const ValueKey<String>(kMemoryRecallKeyId),
          keyId: kMemoryRecallKeyId,
          label: 'MR',
          onTap: onMemoryRecall,
          enabled: memoryActive,
          onPressStart: onKeyPressStart,
          onPressEnd: onKeyPressEnd,
          onRawTap: onKeyTap,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(
          key: const ValueKey<String>(kMemoryAddKeyId),
          keyId: kMemoryAddKeyId,
          label: 'M+',
          onTap: onMemoryAdd,
          enabled: true,
          onPressStart: onKeyPressStart,
          onPressEnd: onKeyPressEnd,
          onRawTap: onKeyTap,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(
          key: const ValueKey<String>(kMemorySubtractKeyId),
          keyId: kMemorySubtractKeyId,
          label: 'M−',
          onTap: onMemorySubtract,
          enabled: true,
          onPressStart: onKeyPressStart,
          onPressEnd: onKeyPressEnd,
          onRawTap: onKeyTap,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        Expanded(
          child: TextButton.icon(
            onPressed: onToggleScientific,
            style: TextButton.styleFrom(
              foregroundColor: CalculatorTheme.secondaryText,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(
              scientificExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 20,
            ),
            label: const Text('fx', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _MemoryChip extends StatelessWidget {
  const _MemoryChip({
    required this.keyId,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.onPressStart,
    this.onPressEnd,
    this.onRawTap,
    super.key,
  });

  final String keyId;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final ValueChanged<String>? onPressStart;
  final ValueChanged<String>? onPressEnd;
  final ValueChanged<String>? onRawTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPressStart?.call(keyId),
      onPointerUp: (_) {
        onPressEnd?.call(keyId);
        onRawTap?.call(keyId);
      },
      onPointerCancel: (_) => onPressEnd?.call(keyId),
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
          foregroundColor: CalculatorTheme.secondaryText,
          disabledForegroundColor: CalculatorTheme.mutedText,
          minimumSize: const Size(40, 34),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        child: Text(label),
      ),
    );
  }
}
