import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/repositories/secure_storage_repository.dart';

class SecureStorageFlutterRepository implements SecureStorageRepository {
  SecureStorageFlutterRepository(this._storage);

  final FlutterSecureStorage _storage;

  static String _kWrappedVmk(String vaultId) => 'vault.$vaultId.wrapped_vmk';
  static String _kNonce(String vaultId) => 'vault.$vaultId.nonce';
  static String _kMac(String vaultId) => 'vault.$vaultId.mac';
  static String _kSalt(String vaultId) => 'vault.$vaultId.salt';
  static String _kEncVersion(String vaultId) => 'vault.$vaultId.enc_version';

  @override
  Future<void> storeWrappedVmk({
    required String vaultId,
    required String wrappedVmkBase64,
    required String nonceBase64,
    required String macBase64,
    required String saltBase64,
    required int encVersion,
  }) async {
    await _storage.write(key: _kWrappedVmk(vaultId), value: wrappedVmkBase64);
    await _storage.write(key: _kNonce(vaultId), value: nonceBase64);
    await _storage.write(key: _kMac(vaultId), value: macBase64);
    await _storage.write(key: _kSalt(vaultId), value: saltBase64);
    await _storage.write(key: _kEncVersion(vaultId), value: encVersion.toString());
  }

  @override
  Future<Map<String, String>?> loadWrappedVmk(String vaultId) async {
    final wrappedVmk = await _storage.read(key: _kWrappedVmk(vaultId));
    final nonce = await _storage.read(key: _kNonce(vaultId));
    final mac = await _storage.read(key: _kMac(vaultId));
    final salt = await _storage.read(key: _kSalt(vaultId));
    final encVersion = await _storage.read(key: _kEncVersion(vaultId));

    if (wrappedVmk == null ||
        nonce == null ||
        mac == null ||
        salt == null ||
        encVersion == null) {
      return null;
    }

    return {
      'wrappedVmk': wrappedVmk,
      'nonce': nonce,
      'mac': mac,
      'salt': salt,
      'encVersion': encVersion,
    };
  }

  @override
  Future<void> deleteVmkBlobs(String vaultId) async {
    await _storage.delete(key: _kWrappedVmk(vaultId));
    await _storage.delete(key: _kNonce(vaultId));
    await _storage.delete(key: _kMac(vaultId));
    await _storage.delete(key: _kSalt(vaultId));
    await _storage.delete(key: _kEncVersion(vaultId));
  }
}
