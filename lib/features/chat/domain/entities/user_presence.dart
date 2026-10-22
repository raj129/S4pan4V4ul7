import 'package:equatable/equatable.dart';

/// Online state of a user, as reported by a [PresenceRepository].
///
/// Deliberately *not* a field on `ChatUser`. Presence is the one part of the
/// chat that may later move to Realtime Database (for `onDisconnect()`), and if
/// it were stored on the user document every widget reading `user.isOnline`
/// would have to change on that day. Keeping it in its own value object means
/// the swap touches only the repository binding.
class UserPresence extends Equatable {
  const UserPresence({required this.isOnline, required this.lastSeen});

  final bool isOnline;
  final DateTime lastSeen;

  /// Fallback for a user who has never published presence.
  static final UserPresence offline = UserPresence(
    isOnline: false,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  @override
  List<Object?> get props => [isOnline, lastSeen];
}
