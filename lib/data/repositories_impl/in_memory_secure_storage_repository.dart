import '../../domain/repositories/secure_storage_repository.dart';

/// In-memory secure storage used during development and unit tests.
///
/// Replace with a [FlutterSecureStorage]-backed implementation for production.
/// Production implementation stores key-value pairs in Android Keystore
/// (via flutter_secure_storage with `encryptedSharedPreferences: true`).
class InMemorySecureStorageRepository implements SecureStorageRepository {
  final Map<String, Map<String, String>> _store = {};

  @override
  Future<void> storeWrappedVmk({
    required String vaultId,
    required String wrappedVmkBase64,
    required String nonceBase64,
    required String macBase64,
    required String saltBase64,
    required int encVersion,
  }) async {
    _store[vaultId] = {
      'wrappedVmk': wrappedVmkBase64,
      'nonce': nonceBase64,
      'mac': macBase64,
      'salt': saltBase64,
      'encVersion': encVersion.toString(),
    };
  }

  @override
  Future<Map<String, String>?> loadWrappedVmk(String vaultId) async =>
      _store[vaultId];

  @override
  Future<void> deleteVmkBlobs(String vaultId) async {
    _store.remove(vaultId);
  }

  /// Test-only helper: returns all vault IDs that have stored blobs.
  List<String> debugAllKeys() => _store.keys.toList();
}
