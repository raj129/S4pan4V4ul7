import 'dart:convert';
import 'package:equatable/equatable.dart';

enum NoteType { textNote, checklist }

/// An individual item in a checklist with Google Keep-style strike-through behavior.
class ChecklistItem extends Equatable {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.isDone = false,
    this.completedAt,
    this.completedBy,
  });

  final String id;
  final String text;
  final bool isDone;
  final DateTime? completedAt;
  final String? completedBy;

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isDone,
    DateTime? completedAt,
    String? completedBy,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
      completedAt: isDone == false ? null : (completedAt ?? this.completedAt),
      completedBy: isDone == false ? null : (completedBy ?? this.completedBy),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isDone': isDone,
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().millisecondsSinceEpoch,
    if (completedBy != null) 'completedBy': completedBy,
  };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    isDone: json['isDone'] as bool? ?? false,
    completedAt: json['completedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['completedAt'] as num).toInt(),
            isUtc: true,
          )
        : null,
    completedBy: json['completedBy'] as String?,
  );

  @override
  List<Object?> get props => [id, text, isDone, completedAt, completedBy];
}

/// A note or checklist, which can either belong to a shared chat thread or
/// be completely private in the user's encrypted vault.
class AppNote extends Equatable {
  const AppNote({
    required this.id,
    this.threadId,
    required this.creatorId,
    required this.type,
    required this.title,
    this.content = '',
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.lastEditedBy,
    this.isPinned = false,
    this.colorIndex = 0,
  });

  final String id;

  /// Nullable: non-null means shared within a chat thread; null means private vault note.
  final String? threadId;

  /// User ID who created the note.
  final String creatorId;

  final NoteType type;
  final String title;

  /// Body text for [NoteType.textNote].
  final String content;

  /// Ordered checklist items for [NoteType.checklist].
  final List<ChecklistItem> items;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastEditedBy;
  final bool isPinned;
  final int colorIndex;

  bool get isShared => threadId != null && threadId!.isNotEmpty;
  bool get isChecklist => type == NoteType.checklist;

  int get completedCount => items.where((item) => item.isDone).length;
  int get totalCount => items.length;

  AppNote copyWith({
    String? id,
    String? threadId,
    String? creatorId,
    NoteType? type,
    String? title,
    String? content,
    List<ChecklistItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastEditedBy,
    bool? isPinned,
    int? colorIndex,
  }) {
    return AppNote(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      creatorId: creatorId ?? this.creatorId,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastEditedBy: lastEditedBy ?? this.lastEditedBy,
      isPinned: isPinned ?? this.isPinned,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (threadId != null) 'threadId': threadId,
    'creatorId': creatorId,
    'type': type.name,
    'title': title,
    'content': content,
    'items': items.map((i) => i.toJson()).toList(),
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
    'updatedAt': updatedAt.toUtc().millisecondsSinceEpoch,
    if (lastEditedBy != null) 'lastEditedBy': lastEditedBy,
    'isPinned': isPinned,
    'colorIndex': colorIndex,
  };

  factory AppNote.fromJson(Map<String, dynamic> json) => AppNote(
    id: json['id'] as String? ?? '',
    threadId: json['threadId'] as String?,
    creatorId: json['creatorId'] as String? ?? '',
    type: NoteType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => NoteType.textNote,
    ),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    items: (json['items'] as List?)
            ?.map((i) => ChecklistItem.fromJson(i as Map<String, dynamic>))
            .toList() ??
        const [],
    createdAt: json['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt(),
            isUtc: true,
          )
        : DateTime.now().toUtc(),
    updatedAt: json['updatedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['updatedAt'] as num).toInt(),
            isUtc: true,
          )
        : DateTime.now().toUtc(),
    lastEditedBy: json['lastEditedBy'] as String?,
    isPinned: json['isPinned'] as bool? ?? false,
    colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
  );

  String serialize() => jsonEncode(toJson());

  static AppNote deserialize(String rawJson) =>
      AppNote.fromJson(jsonDecode(rawJson) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
    id,
    threadId,
    creatorId,
    type,
    title,
    content,
    items,
    createdAt,
    updatedAt,
    lastEditedBy,
    isPinned,
    colorIndex,
  ];
}
