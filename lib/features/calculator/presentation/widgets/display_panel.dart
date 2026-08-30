import 'package:flutter/material.dart';

import '../../application/calculator_state.dart';
import '../theme/calculator_theme.dart';

/// Shows the typed expression plus the live preview (or error) beneath it.
class DisplayPanel extends StatelessWidget {
  const DisplayPanel({
    required this.state,
    required this.onHistoryTap,
    this.compact = false,
    super.key,
  });

  final CalculatorState state;
  final VoidCallback onHistoryTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryLine = state.hasError ? state.errorMessage! : state.preview;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, compact ? 12 : 18, 20, compact ? 12 : 16),
      decoration: BoxDecoration(
        color: CalculatorTheme.surface,
        borderRadius: BorderRadius.circular(CalculatorTheme.panelRadius),
        boxShadow: CalculatorTheme.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (state.memoryActive)
                Text(
                  'M',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: CalculatorTheme.accentPressed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Spacer(),
              Text(
                state.angleUnit.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: CalculatorTheme.mutedText,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onHistoryTap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'History',
                icon: const Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: CalculatorTheme.secondaryText,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Text(
              state.displayText,
              maxLines: 1,
              softWrap: false,
              style:
                  (compact
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.displaySmall)
                      ?.copyWith(
                        color: CalculatorTheme.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 22,
            child: secondaryLine.isEmpty
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        state.hasError ? secondaryLine : '= $secondaryLine',
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: state.hasError
                              ? CalculatorTheme.destructive
                              : CalculatorTheme.secondaryText,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
