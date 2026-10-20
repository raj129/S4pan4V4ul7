class EncryptedPayload {
  const EncryptedPayload({
    required this.nonce,
    required this.cipherText,
    required this.mac,
    required this.encryptionVersion,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;
  final int encryptionVersion;
}
