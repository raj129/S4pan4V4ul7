import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Pure thumb geometry for [ChatScrollbar], kept separate so it can be tested
/// without a widget tree.
///
/// Fraction 0 is the oldest message and 1 the latest. The chat draws the
/// latest message at the bottom, so the thumb does too: fraction 1 puts the
/// thumb at the bottom of the track.
@immutable
class ChatScrollbarGeometry {
  const ChatScrollbarGeometry({
    required this.trackHeight,
    this.thumbHeight = 44,
  });

  final double trackHeight;
  final double thumbHeight;

  /// Distance the thumb can travel. Zero when the track is too short.
  double get usable =>
      (trackHeight - thumbHeight).clamp(0.0, double.infinity).toDouble();

  /// Top edge of the thumb for [fraction].
  double thumbTop(double fraction) => fraction.clamp(0.0, 1.0) * usable;

  /// Fraction for a thumb whose top edge is at [top].
  double fractionAt(double top) {
    if (usable <= 0) return 1;
    return (top / usable).clamp(0.0, 1.0);
  }
}

/// Draggable fast-scroll thumb for a chat timeline, positioned over the
/// *whole* cached history rather than only the messages in memory.
///
/// While dragging, a bubble shows the date under the thumb and
/// [onDragPreview] is called (throttled) so the list can follow the finger;
/// [onJump] fires once on release with the final position.
class ChatScrollbar extends StatefulWidget {
  const ChatScrollbar({
    super.key,
    required this.position,
    required this.visible,
    required this.dateAt,
    required this.onJump,
    this.onDragPreview,
  });

  /// Current position of the viewport in the history (0 oldest .. 1 latest),
  /// or null if unknown.
  final ValueListenable<double?> position;

  /// Whether the thumb should be shown (e.g. while the user scrolls).
  final ValueListenable<bool> visible;

  /// Resolves the send date at a fraction, for the drag bubble.
  final Future<DateTime?> Function(double fraction) dateAt;

  /// Called on release with the fraction the thumb was dropped at.
  final ValueChanged<double> onJump;

  /// Called while dragging, at most every [previewInterval].
  final ValueChanged<double>? onDragPreview;

  static const previewInterval = Duration(milliseconds: 150);

  /// Width of the touch target. Material's minimum is 48dp; the visible bar
  /// stays slim inside it.
  static const hitWidth = 48.0;

  @override
  State<ChatScrollbar> createState() => _ChatScrollbarState();
}

class _ChatScrollbarState extends State<ChatScrollbar> {
  static const _thumbHeight = 44.0;

  /// Vertical slack around the thumb so it is easy to grab.
  static const _hitPadding = 12.0;

  double? _dragFraction;
  double _grabOffset = 0;
  DateTime? _dragDate;
  Timer? _dateThrottle;
  Timer? _previewThrottle;
  double? _pendingPreview;
  double? _lastPreview;

  @override
  void dispose() {
    _dateThrottle?.cancel();
    _previewThrottle?.cancel();
    super.dispose();
  }

  /// Pointer position in track coordinates. Using the global position avoids
  /// the drift of `localPosition`, which is relative to the moving thumb.
  double _trackY(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? 0 : box.globalToLocal(global).dy;
  }

  void _startDrag(DragStartDetails d, ChatScrollbarGeometry geo, double from) {
    _grabOffset = _trackY(d.globalPosition) - geo.thumbTop(from);
    _setDrag(from);
  }

  void _updateDrag(DragUpdateDetails d, ChatScrollbarGeometry geo) {
    final top = _trackY(d.globalPosition) - _grabOffset;
    _setDrag(geo.fractionAt(top));
  }

  void _setDrag(double fraction) {
    setState(() => _dragFraction = fraction);
    _schedulePreview(fraction);
    if (_dateThrottle?.isActive ?? false) return;
    _dateThrottle = Timer(const Duration(milliseconds: 80), () async {
      final f = _dragFraction;
      if (f == null) return;
      final date = await widget.dateAt(f);
      if (mounted && _dragFraction != null) setState(() => _dragDate = date);
    });
  }

  /// Leading + trailing throttle: the first move previews at once, then at
  /// most one preview per interval, always ending on the latest position.
  void _schedulePreview(double fraction) {
    final preview = widget.onDragPreview;
    if (preview == null) return;
    _pendingPreview = fraction;
    if (_previewThrottle?.isActive ?? false) return;
    _sendPreview();
  }

  void _sendPreview() {
    final f = _pendingPreview;
    _pendingPreview = null;
    if (f == null || f == _lastPreview) return;
    _lastPreview = f;
    widget.onDragPreview?.call(f);
    _previewThrottle = Timer(ChatScrollbar.previewInterval, () {
      if (mounted && _dragFraction != null) _sendPreview();
    });
  }

  void _endDrag() {
    final f = _dragFraction;
    _previewThrottle?.cancel();
    _pendingPreview = null;
    _lastPreview = null;
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
        final geo = ChatScrollbarGeometry(
          trackHeight: constraints.maxHeight,
          thumbHeight: _thumbHeight,
        );
        return AnimatedBuilder(
          animation: Listenable.merge([widget.position, widget.visible]),
          builder: (context, _) {
            final dragging = _dragFraction != null;
            final fraction = _dragFraction ?? widget.position.value;
            final shown = dragging || widget.visible.value;
            if (fraction == null || geo.usable <= 0) {
              return const SizedBox.shrink();
            }
            final top = geo.thumbTop(fraction);
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
                      top: top - _hitPadding,
                      width: ChatScrollbar.hitWidth,
                      height: _thumbHeight + _hitPadding * 2,
                      child: Semantics(
                        slider: true,
                        label: 'Fast scroll',
                        value: '${(fraction * 100).round()}%',
                        increasedValue:
                            '${((fraction + 0.1).clamp(0.0, 1.0) * 100).round()}%',
                        decreasedValue:
                            '${((fraction - 0.1).clamp(0.0, 1.0) * 100).round()}%',
                        onIncrease: () =>
                            widget.onJump((fraction + 0.1).clamp(0.0, 1.0)),
                        onDecrease: () =>
                            widget.onJump((fraction - 0.1).clamp(0.0, 1.0)),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (d) =>
                              _startDrag(d, geo, fraction),
                          onVerticalDragUpdate: (d) => _updateDrag(d, geo),
                          onVerticalDragEnd: (_) => _endDrag(),
                          onVerticalDragCancel: _endDrag,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: dragging ? 8 : 6,
                              height: _thumbHeight,
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
                        right: ChatScrollbar.hitWidth,
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
