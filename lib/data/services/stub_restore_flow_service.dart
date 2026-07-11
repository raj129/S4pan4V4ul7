import '../../application/services/restore_flow_service.dart';

class StubRestoreFlowService implements RestoreFlowService {
  const StubRestoreFlowService({this.backupAvailable = true});

  final bool backupAvailable;

  @override
  Future<bool> hasBackupManifest() async => backupAvailable;

  @override
  Future<void> fetchBackupManifest() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<void> restoreEncryptedVmk() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> restoreMetadataAndPhotos({required bool includePhotos}) async {
    await Future<void>.delayed(
      Duration(milliseconds: includePhotos ? 1200 : 600),
    );
  }
}
