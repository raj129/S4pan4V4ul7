import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/chat_theme.dart';
import 'chat_bubble_shape.dart';

/// Animated "…" bubble shown while the other participant is typing.
///
/// Rendered in the incoming-bubble style so it reads as a message that has not
/// arrived yet, rather than as a status line bolted onto the composer.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.visible = true});

  final bool visible;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.chatColors;

    return AnimatedSize(
      duration: AppDuration.normal,
      curve: Curves.easeOut,
      alignment: Alignment.bottomLeft,
      child: !widget.visible
          ? const SizedBox(width: double.infinity, height: 0)
          : Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xxs,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Material(
                  color: chat.bubbleTheirs,
                  shape: const ChatBubbleShape(isMine: false),
                  elevation: AppElevation.raised,
                  shadowColor: chat.bubbleShadow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          _Dot(
                            controller: _controller,
                            index: i,
                            color: chat.onBubbleTheirs,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.controller,
    required this.index,
    required this.color,
  });

  final AnimationController controller;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Each dot runs the same curve, offset by a third of the cycle.
    final begin = index * 0.2;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, begin + 0.5, curve: Curves.easeInOut),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(
          // Ping-pong so the dot rises and falls within its slot.
          animation.value <= 0.5
              ? animation.value * 2
              : (1 - animation.value) * 2,
        );
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 7,
          height: 7,
          transform: Matrix4.translationValues(0, -3 * t, 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.4 + 0.5 * t),
          ),
        );
      },
    );
  }
}
