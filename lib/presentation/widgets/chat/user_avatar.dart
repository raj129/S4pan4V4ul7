import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/profile_avatar.dart';

/// Background colours for the default avatars.
const avatarPresetColors = <Color>[
  Color(0xFF5C6BC0),
  Color(0xFF26A69A),
  Color(0xFFEF5350),
  Color(0xFFFFA726),
  Color(0xFF8D6E63),
  Color(0xFF7E57C2),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFEC407A),
  Color(0xFF78909C),
  Color(0xFFFFCA28),
  Color(0xFF26C6DA),
];

/// Round profile picture: initials, default preset, emoji or photo.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.avatar,
    required this.name,
    this.radius = 24,
  });

  final ProfileAvatar avatar;

  /// Used to derive initials.
  final String name;
  final double radius;

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) {
      return '${parts[0].characters.first}${parts[1].characters.first}'
          .toUpperCase();
    }
    return parts[0].characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fontSize = radius * 0.8;
    switch (avatar.kind) {
      case AvatarKind.photo:
        return CircleAvatar(
          radius: radius,
          backgroundColor: cs.primaryContainer,
          backgroundImage: CachedNetworkImageProvider(avatar.value),
          onBackgroundImageError: (_, _) {},
        );
      case AvatarKind.emoji:
        return CircleAvatar(
          radius: radius,
          backgroundColor: cs.secondaryContainer,
          child: Text(avatar.value, style: TextStyle(fontSize: fontSize)),
        );
      case AvatarKind.preset:
        return CircleAvatar(
          radius: radius,
          backgroundColor:
              avatarPresetColors[avatar.presetIndex %
                  avatarPresetColors.length],
          child: Icon(
            Icons.person_rounded,
            size: radius * 1.2,
            color: Colors.white,
          ),
        );
      case AvatarKind.initials:
        return CircleAvatar(
          radius: radius,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initialsOf(name),
            style: TextStyle(
              fontSize: fontSize * 0.75,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        );
    }
  }
}
