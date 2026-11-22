import 'package:photo_vault/core/domain/repositories/auth_repository.dart';

/// Translates verbose platform/cloud exceptions into short, user-readable messages.
class BackupErrorFormatter {
  const BackupErrorFormatter._();

  static String brief(Object error) {
    if (error is AuthException) {
      return _clamp(error.message);
    }
    var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceFirst(
      RegExp(r'^(Bad state|Exception|FormatException):\s*'),
      '',
    );
    if (text.contains('Google Drive API has not been used') ||
        text.contains('drive.googleapis.com/overview')) {
      return 'Google Drive API is disabled for this project. Enable '
          'drive.googleapis.com in Google Cloud, then retry.';
    }
    if (text.contains('insufficientPermissions') ||
        text.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT')) {
      return 'Google Drive permission is missing. Re-enable Google Drive in '
          'Backup & restore and try again.';
    }
    if (text.contains('storageQuotaExceeded')) {
      return 'Your Google Drive storage is full. Free up space and retry.';
    }
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable')) {
      return 'No internet connection. Changes are saved on this device and '
          'will upload when online.';
    }
    return _clamp(text);
  }

  static String _clamp(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;
}
