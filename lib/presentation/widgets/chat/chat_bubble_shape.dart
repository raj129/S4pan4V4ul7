import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Speech-bubble outline with an optional tail on the outer top corner.
///
/// Implemented as a [ShapeBorder] rather than a clipped decoration so that
/// [Material] can cast a shadow that follows the tail instead of the bounding
/// box.
///
/// Only the first bubble of a consecutive run draws a tail; the rest of the run
/// uses a tighter radius on the tail side so the group reads as one block.
class ChatBubbleShape extends ShapeBorder {
  const ChatBubbleShape({
    required this.isMine,
    this.withTail = true,
    this.radius = 18,
    this.tightRadius = 6,
    this.tailSize = 8,
  });

  final bool isMine;
  final bool withTail;
  final double radius;

  /// Radius used on the tail-side corner for continuation bubbles.
  final double tightRadius;

  final double tailSize;

  /// Space the tail occupies outside the bubble body.
  EdgeInsets get tailInsets => withTail
      ? (isMine
            ? EdgeInsets.only(right: tailSize)
            : EdgeInsets.only(left: tailSize))
      : EdgeInsets.zero;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // The body is inset on the tail side so the tail can protrude into the
    // space reserved by [tailInsets].
    final body = Rect.fromLTRB(
      rect.left + (withTail && !isMine ? tailSize : 0),
      rect.top,
      rect.right - (withTail && isMine ? tailSize : 0),
      rect.bottom,
    );

    // Guard against degenerate sizes during layout transitions.
    final r = math.min(radius, math.min(body.width, body.height) / 2);
    final tight = math.min(tightRadius, r);

    final outerTop = withTail ? Radius.zero : Radius.circular(tight);

    final rrect = RRect.fromRectAndCorners(
      body,
      topLeft: isMine ? Radius.circular(r) : outerTop,
      topRight: isMine ? outerTop : Radius.circular(r),
      bottomLeft: Radius.circular(r),
      bottomRight: Radius.circular(r),
    );

    final path = Path()..addRRect(rrect);
    if (!withTail) return path;

    // A small curved flick off the top outer corner.
    final tail = Path();
    if (isMine) {
      tail
        ..moveTo(body.right, body.top)
        ..quadraticBezierTo(
          body.right + tailSize,
          body.top,
          body.right + tailSize,
          body.top + tailSize * 0.25,
        )
        ..quadraticBezierTo(
          body.right + tailSize * 0.4,
          body.top + tailSize * 0.9,
          body.right,
          body.top + tailSize * 1.4,
        )
        ..close();
    } else {
      tail
        ..moveTo(body.left, body.top)
        ..quadraticBezierTo(
          body.left - tailSize,
          body.top,
          body.left - tailSize,
          body.top + tailSize * 0.25,
        )
        ..quadraticBezierTo(
          body.left - tailSize * 0.4,
          body.top + tailSize * 0.9,
          body.left,
          body.top + tailSize * 1.4,
        )
        ..close();
    }

    return Path.combine(PathOperation.union, path, tail);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ChatBubbleShape(
    isMine: isMine,
    withTail: withTail,
    radius: radius * t,
    tightRadius: tightRadius * t,
    tailSize: tailSize * t,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatBubbleShape &&
      other.isMine == isMine &&
      other.withTail == withTail &&
      other.radius == radius &&
      other.tightRadius == tightRadius &&
      other.tailSize == tailSize;

  @override
  int get hashCode =>
      Object.hash(isMine, withTail, radius, tightRadius, tailSize);
}
