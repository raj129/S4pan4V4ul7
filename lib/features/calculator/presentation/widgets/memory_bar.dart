import 'package:flutter/material.dart';

import '../theme/calculator_theme.dart';

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
    super.key,
  });

  final VoidCallback onMemoryClear;
  final VoidCallback onMemoryRecall;
  final VoidCallback onMemoryAdd;
  final VoidCallback onMemorySubtract;
  final VoidCallback onToggleScientific;
  final bool scientificExpanded;
  final bool memoryActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _MemoryChip(
          label: 'MC',
          onTap: onMemoryClear,
          enabled: memoryActive,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(
          label: 'MR',
          onTap: onMemoryRecall,
          enabled: memoryActive,
        ),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(label: 'M+', onTap: onMemoryAdd, enabled: true),
        const SizedBox(width: CalculatorTheme.keySpacing),
        _MemoryChip(label: 'M−', onTap: onMemorySubtract, enabled: true),
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
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(
        foregroundColor: CalculatorTheme.secondaryText,
        disabledForegroundColor: CalculatorTheme.mutedText,
        minimumSize: const Size(40, 34),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: Text(label),
    );
  }
}
