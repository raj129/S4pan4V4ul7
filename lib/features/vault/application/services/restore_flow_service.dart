import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';

class RestorePhotosSummary {
  const RestorePhotosSummary({
    required this.foundBackup,
    required this.restored,
    required this.alreadyPresent,
    required this.unavailable,
    this.failures = const [],
  });

  final bool foundBackup;
  final int restored;
  final int alreadyPresent;
  final int unavailable;
  final List<String> failures;
}

abstract class RestoreFlowService {
  Future<List<String>> listVaultIds();

  Future<String?> activeVaultId();

  Future<void> restoreVault({
    required String vaultId,
    required String originalPin,
    required String newPin,
  });

  Future<RestorePhotosSummary> restorePhotos({required bool includePhotos});

  Future<int> restoreChat({
    required bool includeChat,
    void Function(ChatRestoreProgress)? onProgress,
  }) async => 0;

  Future<void> skipChatRestore() async {}
}
