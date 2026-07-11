import 'crypto_service.dart';

class VaultKeyManager {
  VaultKeyManager(this._cryptoService);

  final CryptoService _cryptoService;

  Future<List<int>> createVaultMasterKey() {
    return _cryptoService.generateSymmetricKey();
  }

  Future<List<int>> createDataEncryptionKey() {
    return _cryptoService.generateSymmetricKey();
  }
}
