class VaultPhoto {
  const VaultPhoto({
    required this.id,
    required this.originalFilename,
    required this.encryptedFilePath,
    required this.thumbnailPath,
    required this.wrappedDek,
    required this.photoNonce,
    required this.thumbnailNonce,
    required this.encryptionVersion,
    required this.checksumSha256,
    required this.fileSize,
    required this.mimeType,
    required this.createdTimeMs,
    required this.importedTimeMs,
    required this.modifiedTimeMs,
    required this.favorite,
    required this.isTrashed,
    this.albumId,
    this.trashExpiresAtMs,
  });

  final String id;
  final String originalFilename;
  final String encryptedFilePath;
  final String thumbnailPath;
  final String wrappedDek;
  final String photoNonce;
  final String thumbnailNonce;
  final int encryptionVersion;
  final String checksumSha256;
  final int fileSize;
  final String mimeType;
  final int createdTimeMs;
  final int importedTimeMs;
  final int modifiedTimeMs;
  final bool favorite;
  final bool isTrashed;
  final String? albumId;
  final int? trashExpiresAtMs;
}
