class WrappedKey {
  const WrappedKey({
    required this.keyId,
    required this.wrappedBytes,
    required this.nonce,
    required this.mac,
    required this.encryptionVersion,
  });

  final String keyId;
  final List<int> wrappedBytes;
  final List<int> nonce;
  final List<int> mac;
  final int encryptionVersion;
}
