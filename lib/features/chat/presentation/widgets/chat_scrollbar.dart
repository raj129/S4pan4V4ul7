import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Draggable fast-scroll thumb for a chat timeline, positioned over the
/// *whole* cached history rather than only the messages in memory.
///
/// Fraction 0 is the first message and 1 the latest (the bottom). While the
/// thumb is dragged a bubble shows the date under it; releasing jumps there.
class ChatScrollbar extends StatefulWidget {
  const ChatScrollbar({
    super.key,
    required this.position,
    required this.visible,
    required this.dateAt,
    required this.onJump,
  });

  /// Current position of the viewport in the history, or null if unknown.
  final ValueListenable<double?> position;

  /// Whether the thumb should be shown (e.g. while the user scrolls).
  final ValueListenable<bool> visible;

  /// Resolves the send date at a fraction, for the drag bubble.
  final Future<DateTime?> Function(double fraction) dateAt;

  /// Called on release with the fraction the thumb was dropped at.
  final ValueChanged<double> onJump;

  @override
  State<ChatScrollbar> createState() => _ChatScrollbarState();
}

class _ChatScrollbarState extends State<ChatScrollbar> {
  static const _thumbHeight = 44.0;
  static const _hitWidth = 32.0;

  double? _dragFraction;
  DateTime? _dragDate;
  Timer? _dateThrottle;

  @override
  void dispose() {
    _dateThrottle?.cancel();
    super.dispose();
  }

  void _updateDrag(double dy, double trackHeight) {
    final usable = (trackHeight - _thumbHeight).clamp(1.0, double.infinity);
    final top = (dy - _thumbHeight / 2).clamp(0.0, usable);
    final fraction = 1 - top / usable;
    setState(() => _dragFraction = fraction);
    if (_dateThrottle?.isActive ?? false) return;
    _dateThrottle = Timer(const Duration(milliseconds: 80), () async {
      final f = _dragFraction;
      if (f == null) return;
      final date = await widget.dateAt(f);
      if (mounted && _dragFraction != null) setState(() => _dragDate = date);
    });
  }

  void _endDrag() {
    final f = _dragFraction;
    setState(() {
      _dragFraction = null;
      _dragDate = null;
    });
    if (f != null) widget.onJump(f);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: Listenable.merge([widget.position, widget.visible]),
          builder: (context, _) {
            final dragging = _dragFraction != null;
            final fraction = _dragFraction ?? widget.position.value;
            final shown = dragging || widget.visible.value;
            if (fraction == null) return const SizedBox.shrink();
            final usable = (height - _thumbHeight).clamp(0.0, double.infinity);
            final top = (1 - fraction) * usable;
            return IgnorePointer(
              ignoring: !shown,
              child: AnimatedOpacity(
                opacity: shown ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: 0,
                      top: top,
                      width: _hitWidth,
                      height: _thumbHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (d) =>
                            _updateDrag(top + d.localPosition.dy, height),
                        onVerticalDragUpdate: (d) => _updateDrag(
                          (1 - (_dragFraction ?? fraction)) * usable +
                              d.localPosition.dy,
                          height,
                        ),
                        onVerticalDragEnd: (_) => _endDrag(),
                        onVerticalDragCancel: _endDrag,
                        child: Semantics(
                          label: 'Fast scroll',
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: dragging ? 8 : 6,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(
                                  alpha: dragging ? 0.9 : 0.6,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (dragging && _dragDate != null)
                      Positioned(
                        right: _hitWidth + 4,
                        top: top + _thumbHeight / 2 - 16,
                        child: Material(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              DateFormat.yMMMd().format(_dragDate!.toLocal()),
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
