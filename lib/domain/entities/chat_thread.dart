import 'package:equatable/equatable.dart';

class ChatThread extends Equatable {
  const ChatThread({
    required this.threadId,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCounts,
    required this.createdAt,
  });

  /// Deterministic ID: sorted participant UIDs joined with '_'.
  final String threadId;
  final List<String> participantIds;

  /// Preview text shown in chat list (placeholder, actual content is encrypted).
  final String lastMessage;
  final DateTime lastMessageAt;

  /// Map of uid → unread count.
  final Map<String, int> unreadCounts;
  final DateTime createdAt;

  int unreadCountFor(String uid) => unreadCounts[uid] ?? 0;

  String otherParticipantId(String myUid) =>
      participantIds.firstWhere((id) => id != myUid, orElse: () => '');

  /// Builds a deterministic thread ID for two users.
  static String buildId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  ChatThread copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    Map<String, int>? unreadCounts,
  }) {
    return ChatThread(
      threadId: threadId,
      participantIds: participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'threadId': threadId,
        'participantIds': participantIds,
        'lastMessage': lastMessage,
        'lastMessageAt': lastMessageAt.toUtc().millisecondsSinceEpoch,
        'unreadCounts': unreadCounts,
        'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      };

  factory ChatThread.fromFirestore(Map<String, dynamic> data) => ChatThread(
        threadId: data['threadId'] as String,
        participantIds: List<String>.from(data['participantIds'] as List),
        lastMessage: data['lastMessage'] as String? ?? '',
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
          (data['lastMessageAt'] as int?) ?? 0,
          isUtc: true,
        ),
        unreadCounts: Map<String, int>.from(
          (data['unreadCounts'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, (v as num).toInt()),
              ) ??
              {},
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['createdAt'] as int?) ?? 0,
          isUtc: true,
        ),
      );

  @override
  List<Object?> get props =>
      [threadId, participantIds, lastMessage, lastMessageAt, unreadCounts];
}
