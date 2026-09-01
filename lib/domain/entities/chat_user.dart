import 'package:equatable/equatable.dart';

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
    this.photoUrl,
    required this.publicKey,
    required this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  /// Base64-encoded ECDH public key used for key exchange.
  final String publicKey;

  final DateTime createdAt;

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (displayName.isNotEmpty) return displayName[0].toUpperCase();
    return email[0].toUpperCase();
  }

  ChatUser copyWith({
    String? displayName,
    String? photoUrl,
    String? publicKey,
  }) {
    return ChatUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'publicKey': publicKey,
        'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      };

  factory ChatUser.fromFirestore(Map<String, dynamic> data) => ChatUser(
        uid: data['uid'] as String,
        email: data['email'] as String,
        displayName: data['displayName'] as String? ?? data['email'] as String,
        photoUrl: data['photoUrl'] as String?,
        publicKey: data['publicKey'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['createdAt'] as int?) ?? 0,
          isUtc: true,
        ),
      );

  @override
  List<Object?> get props => [uid, email, displayName, photoUrl, publicKey];
}
