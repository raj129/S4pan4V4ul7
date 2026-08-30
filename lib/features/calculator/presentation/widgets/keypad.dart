import 'package:flutter/material.dart';

import '../theme/calculator_theme.dart';
import 'calc_button.dart';
import 'keypad_layouts.dart';

/// Renders rows of [CalcKey]s as an evenly spaced grid.
class Keypad extends StatelessWidget {
  const Keypad({
    required this.rows,
    required this.onKeyTap,
    required this.keyHeight,
    this.onKeyPressStart,
    this.onKeyPressEnd,
    this.spacing = CalculatorTheme.keySpacing,
    super.key,
  });

  final List<List<CalcKey>> rows;
  final ValueChanged<CalcKey> onKeyTap;
  final ValueChanged<CalcKey>? onKeyPressStart;
  final ValueChanged<CalcKey>? onKeyPressEnd;
  final double keyHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...<Widget>[
          if (rowIndex > 0) SizedBox(height: spacing),
          Row(
            children: <Widget>[
              for (
                var keyIndex = 0;
                keyIndex < rows[rowIndex].length;
                keyIndex++
              ) ...<Widget>[
                if (keyIndex > 0) SizedBox(width: spacing),
                Expanded(
                  flex: rows[rowIndex][keyIndex].flex,
                  child: _buildKey(rows[rowIndex][keyIndex]),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildKey(CalcKey key) {
    return CalcButton(
      key: ValueKey<String>(key.id),
      label: key.label,
      style: key.style,
      height: keyHeight,
      onTap: () => onKeyTap(key),
      onPressStart: onKeyPressStart == null
          ? null
          : () => onKeyPressStart!(key),
      onPressEnd: onKeyPressEnd == null ? null : () => onKeyPressEnd!(key),
    );
  }
}
