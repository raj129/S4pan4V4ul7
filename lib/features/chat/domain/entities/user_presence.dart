import 'package:equatable/equatable.dart';

/// Online state of a user, as reported by a [PresenceRepository].
///
/// Deliberately *not* a field on `ChatUser`. Presence is the one part of the
/// chat that may later move to Realtime Database (for `onDisconnect()`), and if
/// it were stored on the user document every widget reading `user.isOnline`
/// would have to change on that day. Keeping it in its own value object means
/// the swap touches only the repository binding.
class UserPresence extends Equatable {
  const UserPresence({required this.isOnline, this.lastSeen});

  final bool isOnline;

  /// When the user was last active, or null when unknown or hidden by either
  /// side's "Show last seen" privacy setting.
  final DateTime? lastSeen;

  /// Fallback for a user who has never published presence.
  static const UserPresence offline = UserPresence(isOnline: false);

  /// This presence with the last-seen time removed (online state is kept).
  UserPresence withoutLastSeen() =>
      lastSeen == null ? this : UserPresence(isOnline: isOnline);

  @override
  List<Object?> get props => [isOnline, lastSeen];
}
