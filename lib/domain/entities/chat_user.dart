import 'package:equatable/equatable.dart';

import 'profile_avatar.dart';

/// A chat participant's public identity.
///
/// Deliberately excludes online state: presence is served by
/// `PresenceRepository` instead, so that moving it to another backing store
/// never ripples through this entity or its consumers.
class ChatUser extends Equatable {
  const ChatUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.avatar = const ProfileAvatar.initials(),
    required this.publicKey,
    required this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final ProfileAvatar avatar;

  /// Base64-encoded ECDH public key used for key exchange.
  final String publicKey;

  final DateTime createdAt;

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (displayName.isNotEmpty) return displayName[0].toUpperCase();
    return '?';
  }

  ChatUser copyWith({
    String? displayName,
    ProfileAvatar? avatar,
    String? publicKey,
  }) {
    return ChatUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'avatar': avatar.encode(),
        'publicKey': publicKey,
        'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      };

  factory ChatUser.fromFirestore(Map<String, dynamic> data) => ChatUser(
        uid: data['uid'] as String,
        email: data['email'] as String,
        displayName: data['displayName'] as String? ?? 'Chat user',
        avatar: ProfileAvatar.decode(data['avatar'] as String?),
        publicKey: data['publicKey'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['createdAt'] as int?) ?? 0,
          isUtc: true,
        ),
      );

  @override
  List<Object?> get props => [uid, email, displayName, avatar, publicKey];
}
