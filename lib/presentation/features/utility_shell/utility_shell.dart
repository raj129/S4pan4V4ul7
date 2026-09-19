import 'package:flutter/material.dart';

import '../../../features/calculator/presentation/theme/calculator_theme.dart';

/// Chrome for the facade's utility pages.
///
/// Deliberately styled from [CalculatorTheme] rather than the app theme: this
/// surface is part of the disguise and must never inherit the vault's look.
class UtilityShell extends StatelessWidget {
  const UtilityShell({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CalculatorTheme.shellBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: CalculatorTheme.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
