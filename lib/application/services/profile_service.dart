import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../data/repositories_impl/firebase_avatar_storage.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/profile_avatar.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/user_repository.dart';

/// The signed-in user's own chat identity (name + avatar).
class OwnProfile {
  const OwnProfile({required this.displayName, required this.avatar});

  final String displayName;
  final ProfileAvatar avatar;
}

/// Own profile and per-contact aliases.
///
/// Both live in the local database (as small settings entries) and travel in
/// the encrypted chat backup. Only the own profile is published to Firestore;
/// aliases are private to this user and never leave the device except inside
/// the encrypted backup.
class ProfileService extends ChangeNotifier {
  ProfileService({
    required MessageCacheRepository store,
    required UserRepository userRepository,
    required AvatarStorage avatarStorage,
  }) : _store = store,
       _users = userRepository,
       _avatars = avatarStorage;

  final MessageCacheRepository _store;
  final UserRepository _users;
  final AvatarStorage _avatars;

  static const _profileKey = 'profile_v1';
  static const _aliasKey = 'contact_aliases_v1';
  static const maxNameLength = 40;
  static const avatarSize = 256;

  /// Set after a local change so the backup service can schedule an upload.
  VoidCallback? onChanged;

  OwnProfile? _profile;
  Map<String, String> _aliases = {};
  bool _loaded = false;

  OwnProfile? get profile => _profile;
  Map<String, String> get aliases => Map.unmodifiable(_aliases);

  /// Loads local state. Safe to call repeatedly.
  Future<void> load() async {
    _profile = _decodeProfile(await _store.readSetting(_profileKey));
    _aliases = _decodeAliases(await _store.readSetting(_aliasKey));
    _loaded = true;
    notifyListeners();
  }

  /// The name to show for [user]: the alias the local user chose, if any.
  String nameFor(ChatUser user) => aliasFor(user.uid) ?? user.displayName;

  String? aliasFor(String uid) {
    final alias = _aliases[uid];
    return alias == null || alias.isEmpty ? null : alias;
  }

  Future<void> setAlias(String uid, String? alias) async {
    final trimmed = alias?.trim() ?? '';
    final next = Map<String, String>.of(_aliases);
    if (trimmed.isEmpty) {
      next.remove(uid);
    } else {
      next[uid] = trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed;
    }
    _aliases = next;
    await _store.writeSetting(_aliasKey, jsonEncode(next));
    notifyListeners();
    onChanged?.call();
  }

  /// Makes sure a local profile exists for [uid].
  ///
  /// The first time on a device the profile is adopted from the server (so a
  /// reinstall does not reset a chosen name), and only if that is empty is it
  /// seeded from [fallbackName]. Returns the effective profile.
  Future<OwnProfile> ensureProfile({
    required String uid,
    required String fallbackName,
  }) async {
    if (!_loaded) await load();
    final existing = _profile;
    if (existing != null) return existing;

    OwnProfile? adopted;
    try {
      final remote = await _users
          .getUserById(uid)
          .timeout(const Duration(seconds: 5));
      if (remote != null && remote.displayName != 'Chat user') {
        adopted = OwnProfile(
          displayName: remote.displayName,
          avatar: remote.avatar,
        );
      }
    } catch (_) {}
    final profile =
        adopted ??
        OwnProfile(
          displayName: fallbackName,
          avatar: const ProfileAvatar.initials(),
        );
    await _saveProfile(profile);
    return profile;
  }

  /// Saves and publishes a new name and/or avatar.
  Future<void> updateProfile({
    required ChatUser me,
    String? displayName,
    ProfileAvatar? avatar,
  }) async {
    final current =
        _profile ?? OwnProfile(displayName: me.displayName, avatar: me.avatar);
    final name = (displayName ?? current.displayName).trim();
    if (name.isEmpty) throw ArgumentError('Name cannot be empty.');
    final next = OwnProfile(
      displayName: name.length > maxNameLength
          ? name.substring(0, maxNameLength)
          : name,
      avatar: avatar ?? current.avatar,
    );
    await _saveProfile(next);
    await publish(me);
    if (current.avatar.kind == AvatarKind.photo &&
        next.avatar.kind != AvatarKind.photo) {
      await _avatars.delete(me.uid);
    }
  }

  /// Saves name and avatar in one go. When [photoBytes] is given it is
  /// compressed, uploaded, and becomes the avatar (overriding [avatar]).
  Future<void> saveProfile({
    required ChatUser me,
    required String displayName,
    ProfileAvatar? avatar,
    Uint8List? photoBytes,
  }) async {
    var nextAvatar = avatar;
    if (photoBytes != null) {
      final jpeg = await compute(compressAvatar, photoBytes);
      final url = await _avatars.upload(me.uid, jpeg);
      nextAvatar = ProfileAvatar.photo(url);
    }
    await updateProfile(me: me, displayName: displayName, avatar: nextAvatar);
  }

  /// Pushes the local profile to Firestore (best effort).
  Future<void> publish(ChatUser me) async {
    final p = _profile;
    if (p == null) return;
    await _users.upsertProfile(
      me.copyWith(displayName: p.displayName, avatar: p.avatar),
    );
  }

  /// [me] with the local profile applied.
  ChatUser applyTo(ChatUser me) {
    final p = _profile;
    return p == null
        ? me
        : me.copyWith(displayName: p.displayName, avatar: p.avatar);
  }

  // ---- backup ---------------------------------------------------------------

  Future<Map<String, dynamic>> exportForBackup() async {
    if (!_loaded) await load();
    return {
      if (_profile != null)
        'profile': {
          'name': _profile!.displayName,
          'avatar': _profile!.avatar.encode(),
        },
      'aliases': _aliases,
    };
  }

  /// Restores profile and aliases from a backup. Existing local aliases win
  /// over backed-up ones for the same contact.
  Future<void> importFromBackup(Map<String, dynamic> data) async {
    if (!_loaded) await load();
    final rawProfile = data['profile'];
    if (_profile == null && rawProfile is Map) {
      final name = rawProfile['name'];
      if (name is String && name.trim().isNotEmpty) {
        await _saveProfile(
          OwnProfile(
            displayName: name,
            avatar: ProfileAvatar.decode(rawProfile['avatar'] as String?),
          ),
        );
      }
    }
    final rawAliases = data['aliases'];
    if (rawAliases is Map) {
      final merged = Map<String, String>.of(_aliases);
      for (final e in rawAliases.entries) {
        if (e.key is String && e.value is String) {
          merged.putIfAbsent(e.key as String, () => e.value as String);
        }
      }
      _aliases = merged;
      await _store.writeSetting(_aliasKey, jsonEncode(merged));
    }
    notifyListeners();
  }

  Future<void> _saveProfile(OwnProfile p) async {
    _profile = p;
    await _store.writeSetting(
      _profileKey,
      jsonEncode({'name': p.displayName, 'avatar': p.avatar.encode()}),
    );
    notifyListeners();
    onChanged?.call();
  }

  static OwnProfile? _decodeProfile(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final name = map['name'];
      if (name is! String || name.isEmpty) return null;
      return OwnProfile(
        displayName: name,
        avatar: ProfileAvatar.decode(map['avatar'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _decodeAliases(String? raw) {
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          if (e.key is String && e.value is String) e.key as String: e.value,
      };
    } catch (_) {
      return {};
    }
  }
}

/// Largest profile photo we upload. Avatars are shown at a few dozen pixels,
/// so this is generous while keeping chat lists cheap to load.
const maxAvatarBytes = 40 * 1024;

/// Crops to a square, downsizes to [ProfileService.avatarSize] and re-encodes
/// as JPEG, lowering quality until the result fits [maxAvatarBytes].
Uint8List compressAvatar(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) throw const FormatException('Unsupported image.');
  final square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: ProfileService.avatarSize,
  );
  var quality = 80;
  var out = img.encodeJpg(square, quality: quality);
  while (out.length > maxAvatarBytes && quality > 30) {
    quality -= 10;
    out = img.encodeJpg(square, quality: quality);
  }
  return Uint8List.fromList(out);
}