import 'dart:convert';

import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

/// Versioned, forward-and-backward-compatible snapshot of portable app
/// settings for local and Google Drive backup/restore.
///
/// Device-specific or ephemeral state (vault ID, unlock failures, last backup
/// timestamps, mock location state) is intentionally excluded.
class SettingsBackupSnapshot {
  const SettingsBackupSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.createdAt,
    this.themePaletteId,
    this.themeMode,
    this.autoLockOnBackground,
    this.autoLockTimeoutSeconds,
    this.secretEntryConfig,
    this.showLastSeen,
    this.screenshotProtectionEnabled,
    this.hdrPhotoPreviewEnabled,
    this.incomingChatAlertTitle,
    this.incomingChatAlertText,
    this.incomingChatAlertPreferences,
    this.backgroundLocationAlertTitle,
    this.backgroundLocationAlertText,
    this.backupChatsEnabled,
    this.backupVaultPhotosEnabled,
    this.backupCloudEnabled,
    this.backupWifiOnly,
    this.backupSettingsEnabled,
    this.externalStorageMirrorEnabled,
    this.chatImageQuality,
    this.savedPlacesJson,
    this.placeTagsJson,
    this.unknownFields = const {},
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime createdAt;

  // Appearance
  final String? themePaletteId;
  final String? themeMode;

  // Security
  final bool? autoLockOnBackground;
  final int? autoLockTimeoutSeconds;
  final SecretEntryConfig? secretEntryConfig;

  // Privacy
  final bool? showLastSeen;
  final bool? screenshotProtectionEnabled;

  // Media preview
  final bool? hdrPhotoPreviewEnabled;

  // Notifications
  final String? incomingChatAlertTitle;
  final String? incomingChatAlertText;
  final IncomingChatAlertPreferences? incomingChatAlertPreferences;
  final String? backgroundLocationAlertTitle;
  final String? backgroundLocationAlertText;

  // Backup preferences
  final bool? backupChatsEnabled;
  final bool? backupVaultPhotosEnabled;
  final bool? backupCloudEnabled;
  final bool? backupWifiOnly;
  final bool? backupSettingsEnabled;
  final bool? externalStorageMirrorEnabled;

  // Chat
  final String? chatImageQuality;

  // My locations (Saved places & tags JSON)
  final String? savedPlacesJson;
  final String? placeTagsJson;

  /// Preserves unrecognised keys from newer app versions without failing.
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson() {
    final settings = <String, dynamic>{
      if (themePaletteId != null) 'themePaletteId': themePaletteId,
      if (themeMode != null) 'themeMode': themeMode,
      if (autoLockOnBackground != null)
        'autoLockOnBackground': autoLockOnBackground,
      if (autoLockTimeoutSeconds != null)
        'autoLockTimeoutSeconds': autoLockTimeoutSeconds,
      if (secretEntryConfig != null)
        'secretEntryConfig': secretEntryConfig!.toJson(),
      if (showLastSeen != null) 'showLastSeen': showLastSeen,
      if (screenshotProtectionEnabled != null)
        'screenshotProtectionEnabled': screenshotProtectionEnabled,
      if (hdrPhotoPreviewEnabled != null)
        'hdrPhotoPreviewEnabled': hdrPhotoPreviewEnabled,
      if (incomingChatAlertTitle != null)
        'incomingChatAlertTitle': incomingChatAlertTitle,
      if (incomingChatAlertText != null)
        'incomingChatAlertText': incomingChatAlertText,
      if (incomingChatAlertPreferences != null)
        'incomingChatAlertPreferences': incomingChatAlertPreferences!.toJson(),
      if (backgroundLocationAlertTitle != null)
        'backgroundLocationAlertTitle': backgroundLocationAlertTitle,
      if (backgroundLocationAlertText != null)
        'backgroundLocationAlertText': backgroundLocationAlertText,
      if (backupChatsEnabled != null) 'backupChatsEnabled': backupChatsEnabled,
      if (backupVaultPhotosEnabled != null)
        'backupVaultPhotosEnabled': backupVaultPhotosEnabled,
      if (backupCloudEnabled != null) 'backupCloudEnabled': backupCloudEnabled,
      if (backupWifiOnly != null) 'backupWifiOnly': backupWifiOnly,
      if (backupSettingsEnabled != null)
        'backupSettingsEnabled': backupSettingsEnabled,
      if (externalStorageMirrorEnabled != null)
        'externalStorageMirrorEnabled': externalStorageMirrorEnabled,
      if (chatImageQuality != null) 'chatImageQuality': chatImageQuality,
      if (savedPlacesJson != null) 'savedPlacesJson': savedPlacesJson,
      if (placeTagsJson != null) 'placeTagsJson': placeTagsJson,
      ...unknownFields,
    };

    return {
      'schemaVersion': schemaVersion,
      'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      'settings': settings,
    };
  }

  String encode() => jsonEncode(toJson());

  static SettingsBackupSnapshot decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Settings backup root must be a JSON object.');
    }
    return SettingsBackupSnapshot.fromJson(decoded);
  }

  /// Resilient parser that tolerates missing keys, type drift, renamed legacy
  /// keys, invalid enum values, and unknown future keys.
  factory SettingsBackupSnapshot.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _asInt(json['schemaVersion']) ?? 1;
    final createdMs = _asInt(json['createdAt']);
    final createdAt = createdMs != null
        ? DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true)
        : DateTime.now().toUtc();

    final rawSettings = json['settings'];
    final map = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : Map<String, dynamic>.from(json);

    // Known keys set so anything new/unknown can be retained safely.
    const knownKeys = <String>{
      'schemaVersion',
      'createdAt',
      'themePaletteId',
      'themeMode',
      'autoLockOnBackground',
      'autoLockTimeoutSeconds',
      'autoLockTimeoutMinutes',
      'secretEntryConfig',
      'showLastSeen',
      'screenshotProtectionEnabled',
      'hdrPhotoPreviewEnabled',
      'incomingChatAlertTitle',
      'incomingChatAlertText',
      'incomingChatAlertPreferences',
      'backgroundLocationAlertTitle',
      'backgroundLocationAlertText',
      'backupChatsEnabled',
      'backupVaultPhotosEnabled',
      'photoSyncEnabled',
      'backupCloudEnabled',
      'driveEncryptedBackupEnabled',
      'backupWifiOnly',
      'backupSettingsEnabled',
      'externalStorageMirrorEnabled',
      'chatImageQuality',
      'savedPlacesJson',
      'placeTagsJson',
    };

    final unknown = <String, dynamic>{};
    for (final entry in map.entries) {
      if (!knownKeys.contains(entry.key)) {
        unknown[entry.key] = entry.value;
      }
    }

    // Theme palette: validate against known palettes, fallback to royalIndigo.
    final rawPalette = _asString(map['themePaletteId']);
    final themePaletteId = rawPalette == null
        ? null
        : AppThemePalette.fromId(rawPalette).id;

    // Theme mode: validate 'system' | 'light' | 'dark'.
    final rawMode = _asString(map['themeMode']);
    final themeMode = switch (rawMode) {
      'system' || 'light' || 'dark' => rawMode,
      _ => null,
    };

    // Auto-lock timeout: migrate legacy minutes if seconds absent, and snap
    // unsupported values to the nearest valid option or default.
    int? autoLockTimeoutSeconds = _asInt(map['autoLockTimeoutSeconds']);
    if (autoLockTimeoutSeconds == null) {
      final legacyMinutes = _asInt(map['autoLockTimeoutMinutes']);
      if (legacyMinutes != null && legacyMinutes > 0) {
        autoLockTimeoutSeconds = 60;
      }
    }
    if (autoLockTimeoutSeconds != null &&
        !SettingsRepository.autoLockTimeoutOptionsSeconds.contains(
          autoLockTimeoutSeconds,
        )) {
      autoLockTimeoutSeconds = _nearestAutoLockOption(autoLockTimeoutSeconds);
    }

    SecretEntryConfig? secretEntryConfig;
    if (map['secretEntryConfig'] is Map) {
      try {
        secretEntryConfig = SecretEntryConfig.fromJson(
          Map<String, dynamic>.from(map['secretEntryConfig'] as Map),
        );
      } catch (_) {
        secretEntryConfig = null;
      }
    }

    IncomingChatAlertPreferences? incomingChatAlertPreferences;
    if (map['incomingChatAlertPreferences'] != null) {
      try {
        incomingChatAlertPreferences = IncomingChatAlertPreferences.fromJson(
          map['incomingChatAlertPreferences'],
        );
      } catch (_) {
        incomingChatAlertPreferences = null;
      }
    }

    // Legacy migrations for backup toggles.
    final backupVaultPhotosEnabled =
        _asBool(map['backupVaultPhotosEnabled']) ??
        _asBool(map['photoSyncEnabled']);
    final backupCloudEnabled =
        _asBool(map['backupCloudEnabled']) ??
        _asBool(map['driveEncryptedBackupEnabled']);

    return SettingsBackupSnapshot(
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      themePaletteId: themePaletteId,
      themeMode: themeMode,
      autoLockOnBackground: _asBool(map['autoLockOnBackground']),
      autoLockTimeoutSeconds: autoLockTimeoutSeconds,
      secretEntryConfig: secretEntryConfig,
      showLastSeen: _asBool(map['showLastSeen']),
      screenshotProtectionEnabled: _asBool(map['screenshotProtectionEnabled']),
      hdrPhotoPreviewEnabled: _asBool(map['hdrPhotoPreviewEnabled']),
      incomingChatAlertTitle: _asString(map['incomingChatAlertTitle']),
      incomingChatAlertText: _asString(map['incomingChatAlertText']),
      incomingChatAlertPreferences: incomingChatAlertPreferences,
      backgroundLocationAlertTitle: _asString(
        map['backgroundLocationAlertTitle'],
      ),
      backgroundLocationAlertText: _asString(
        map['backgroundLocationAlertText'],
      ),
      backupChatsEnabled: _asBool(map['backupChatsEnabled']),
      backupVaultPhotosEnabled: backupVaultPhotosEnabled,
      backupCloudEnabled: backupCloudEnabled,
      backupWifiOnly: _asBool(map['backupWifiOnly']),
      backupSettingsEnabled: _asBool(map['backupSettingsEnabled']),
      externalStorageMirrorEnabled: _asBool(
        map['externalStorageMirrorEnabled'],
      ),
      chatImageQuality: _asString(map['chatImageQuality']),
      savedPlacesJson: _asString(map['savedPlacesJson']),
      placeTagsJson: _asString(map['placeTagsJson']),
      unknownFields: unknown,
    );
  }

  static int _nearestAutoLockOption(int value) {
    const options = SettingsRepository.autoLockTimeoutOptionsSeconds;
    var best = SettingsRepository.defaultAutoLockTimeoutSeconds;
    var bestDiff = (best - value).abs();
    for (final option in options) {
      final diff = (option - value).abs();
      if (diff < bestDiff) {
        best = option;
        bestDiff = diff;
      }
    }
    return best;
  }

  static bool? _asBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is String) {
      if (raw == 'true') return true;
      if (raw == 'false') return false;
    }
    return null;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  static String? _asString(Object? raw) => raw is String ? raw : null;
}
