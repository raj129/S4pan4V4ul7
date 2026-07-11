import 'package:flutter/material.dart';

/// A row of PIN dot indicators.
/// [filledCount] dots are filled; the rest are empty circles.
/// PIN digits themselves are never displayed.
class PinDotRow extends StatelessWidget {
  const PinDotRow({required this.filledCount, required this.total, super.key});

  final int filledCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final filled = i < filledCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}
