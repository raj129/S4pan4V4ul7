import 'package:flutter/material.dart';

/// Fills the viewport like a plain [Column] (so [Spacer]s still push the PIN
/// pad to the bottom), but scrolls instead of overflowing on short screens,
/// in landscape, or with large accessibility text.
class PinFlowBody extends StatelessWidget {
  const PinFlowBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}
