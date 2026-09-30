import 'package:equatable/equatable.dart';

enum AvatarKind { initials, preset, emoji, photo }

/// A chat profile picture: initials, a default preset, an emoji or a photo.
///
/// Serialised as a single string (`initials`, `preset:3`, `emoji:😀`,
/// `photo:<url>`) so it fits one Firestore field and one backup entry.
class ProfileAvatar extends Equatable {
  const ProfileAvatar._(this.kind, this.value);

  const ProfileAvatar.initials() : this._(AvatarKind.initials, '');
  const ProfileAvatar.preset(int index) : this._(AvatarKind.preset, '$index');
  const ProfileAvatar.emoji(String emoji) : this._(AvatarKind.emoji, emoji);
  const ProfileAvatar.photo(String url) : this._(AvatarKind.photo, url);

  final AvatarKind kind;
  final String value;

  int get presetIndex => int.tryParse(value) ?? 0;

  String encode() => switch (kind) {
    AvatarKind.initials => 'initials',
    AvatarKind.preset => 'preset:$value',
    AvatarKind.emoji => 'emoji:$value',
    AvatarKind.photo => 'photo:$value',
  };

  /// Unknown or malformed input falls back to initials.
  static ProfileAvatar decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ProfileAvatar.initials();
    final i = raw.indexOf(':');
    if (i < 0) return const ProfileAvatar.initials();
    final tag = raw.substring(0, i);
    final value = raw.substring(i + 1);
    if (value.isEmpty) return const ProfileAvatar.initials();
    switch (tag) {
      case 'preset':
        return ProfileAvatar.preset(int.tryParse(value) ?? 0);
      case 'emoji':
        return ProfileAvatar.emoji(value);
      case 'photo':
        return value.startsWith('https://')
            ? ProfileAvatar.photo(value)
            : const ProfileAvatar.initials();
      default:
        return const ProfileAvatar.initials();
    }
  }

  @override
  List<Object?> get props => [kind, value];
}
