import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

/// A start-to-end reply gesture with progressively resisted visual travel.
class ReplySwipe extends StatefulWidget {
  const ReplySwipe({super.key, required this.child, this.onReply});

  final Widget child;
  final VoidCallback? onReply;

  @override
  State<ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<ReplySwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _distance = 0;
  double _visualDistance = 0;
  bool _dragging = false;
  bool _hapticSent = false;

  double get _width => context.size?.width ?? 0;
  static const double _limit = 96;

  @override
  void didUpdateWidget(covariant ReplySwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onReply == null) {
      _dragging = false;
      _distance = 0;
      _visualDistance = 0;
      _offset.stop();
      _offset.value = 0;
    }
  }

  void _returnToRest() {
    _dragging = false;
    _distance = 0;
    _visualDistance = 0;
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sign = Directionality.of(context) == TextDirection.ltr ? 1.0 : -1.0;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Listener(
          // Flutter can report an accepted drag's cancellation as a drag end.
          onPointerCancel: (_) {
            if (_dragging) _returnToRest();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.onReply == null
                ? null
                : (_) {
                    _offset.stop();
                    _dragging = true;
                    _hapticSent = false;
                    _distance = 0;
                    // Resume an interrupted return without jumping to the finger.
                    _visualDistance =
                        -_limit *
                        math.log(
                          1 - (_offset.value / _limit).clamp(0, 0.999999),
                        );
                  },
            onHorizontalDragUpdate: widget.onReply == null
                ? null
                : (details) {
                    if (!_dragging) return;
                    final delta = details.delta.dx * sign;
                    _distance = math.max(0, _distance + delta);
                    _visualDistance = math.max(0, _visualDistance + delta);
                    _offset.value =
                        _limit * (1 - math.exp(-_visualDistance / _limit));
                    if (_distance >= _width * 0.25 && !_hapticSent) {
                      _hapticSent = true;
                      HapticFeedback.lightImpact();
                    }
                  },
            onHorizontalDragEnd: widget.onReply == null
                ? null
                : (_) {
                    if (!_dragging) return;
                    final reply = _width > 0 && _distance >= _width * 0.25
                        ? widget.onReply
                        : null;
                    _returnToRest();
                    reply?.call();
                  },
            onHorizontalDragCancel: widget.onReply == null
                ? null
                : _returnToRest,
            child: AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) => Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: _offset.value,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: AlignmentDirectional.centerStart,
                        minWidth: width,
                        maxWidth: width,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.primary.withValues(alpha: 0.15),
                              ),
                              child: Icon(
                                Icons.reply_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(_offset.value * sign, 0),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
