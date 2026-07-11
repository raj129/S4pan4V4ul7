// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_database.dart';

// ignore_for_file: type=lint
class $PhotosTable extends Photos with TableInfo<$PhotosTable, VaultPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalFilenameMeta = const VerificationMeta(
    'originalFilename',
  );
  @override
  late final GeneratedColumn<String> originalFilename = GeneratedColumn<String>(
    'original_filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdTimeMsMeta = const VerificationMeta(
    'createdTimeMs',
  );
  @override
  late final GeneratedColumn<int> createdTimeMs = GeneratedColumn<int>(
    'created_time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedTimeMsMeta = const VerificationMeta(
    'importedTimeMs',
  );
  @override
  late final GeneratedColumn<int> importedTimeMs = GeneratedColumn<int>(
    'imported_time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedTimeMsMeta = const VerificationMeta(
    'modifiedTimeMs',
  );
  @override
  late final GeneratedColumn<int> modifiedTimeMs = GeneratedColumn<int>(
    'modified_time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<int> favorite = GeneratedColumn<int>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _encryptedFilePathMeta = const VerificationMeta(
    'encryptedFilePath',
  );
  @override
  late final GeneratedColumn<String> encryptedFilePath =
      GeneratedColumn<String>(
        'encrypted_file_path',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailNonceMeta = const VerificationMeta(
    'thumbnailNonce',
  );
  @override
  late final GeneratedColumn<String> thumbnailNonce = GeneratedColumn<String>(
    'thumbnail_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoNonceMeta = const VerificationMeta(
    'photoNonce',
  );
  @override
  late final GeneratedColumn<String> photoNonce = GeneratedColumn<String>(
    'photo_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedDekMeta = const VerificationMeta(
    'wrappedDek',
  );
  @override
  late final GeneratedColumn<String> wrappedDek = GeneratedColumn<String>(
    'wrapped_dek',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptionVersionMeta = const VerificationMeta(
    'encryptionVersion',
  );
  @override
  late final GeneratedColumn<int> encryptionVersion = GeneratedColumn<int>(
    'encryption_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backupStatusMeta = const VerificationMeta(
    'backupStatus',
  );
  @override
  late final GeneratedColumn<String> backupStatus = GeneratedColumn<String>(
    'backup_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumSha256Meta = const VerificationMeta(
    'checksumSha256',
  );
  @override
  late final GeneratedColumn<String> checksumSha256 = GeneratedColumn<String>(
    'checksum_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isTrashedMeta = const VerificationMeta(
    'isTrashed',
  );
  @override
  late final GeneratedColumn<int> isTrashed = GeneratedColumn<int>(
    'is_trashed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _trashExpiresAtMsMeta = const VerificationMeta(
    'trashExpiresAtMs',
  );
  @override
  late final GeneratedColumn<int> trashExpiresAtMs = GeneratedColumn<int>(
    'trash_expires_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedTombstoneAtMsMeta =
      const VerificationMeta('deletedTombstoneAtMs');
  @override
  late final GeneratedColumn<int> deletedTombstoneAtMs = GeneratedColumn<int>(
    'deleted_tombstone_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    originalFilename,
    createdTimeMs,
    importedTimeMs,
    modifiedTimeMs,
    source,
    albumId,
    favorite,
    encryptedFilePath,
    thumbnailPath,
    thumbnailNonce,
    photoNonce,
    wrappedDek,
    encryptionVersion,
    syncStatus,
    backupStatus,
    checksumSha256,
    fileSize,
    mimeType,
    isTrashed,
    trashExpiresAtMs,
    deletedTombstoneAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('original_filename')) {
      context.handle(
        _originalFilenameMeta,
        originalFilename.isAcceptableOrUnknown(
          data['original_filename']!,
          _originalFilenameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalFilenameMeta);
    }
    if (data.containsKey('created_time_ms')) {
      context.handle(
        _createdTimeMsMeta,
        createdTimeMs.isAcceptableOrUnknown(
          data['created_time_ms']!,
          _createdTimeMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdTimeMsMeta);
    }
    if (data.containsKey('imported_time_ms')) {
      context.handle(
        _importedTimeMsMeta,
        importedTimeMs.isAcceptableOrUnknown(
          data['imported_time_ms']!,
          _importedTimeMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importedTimeMsMeta);
    }
    if (data.containsKey('modified_time_ms')) {
      context.handle(
        _modifiedTimeMsMeta,
        modifiedTimeMs.isAcceptableOrUnknown(
          data['modified_time_ms']!,
          _modifiedTimeMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modifiedTimeMsMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('encrypted_file_path')) {
      context.handle(
        _encryptedFilePathMeta,
        encryptedFilePath.isAcceptableOrUnknown(
          data['encrypted_file_path']!,
          _encryptedFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedFilePathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbnailPathMeta);
    }
    if (data.containsKey('thumbnail_nonce')) {
      context.handle(
        _thumbnailNonceMeta,
        thumbnailNonce.isAcceptableOrUnknown(
          data['thumbnail_nonce']!,
          _thumbnailNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbnailNonceMeta);
    }
    if (data.containsKey('photo_nonce')) {
      context.handle(
        _photoNonceMeta,
        photoNonce.isAcceptableOrUnknown(data['photo_nonce']!, _photoNonceMeta),
      );
    } else if (isInserting) {
      context.missing(_photoNonceMeta);
    }
    if (data.containsKey('wrapped_dek')) {
      context.handle(
        _wrappedDekMeta,
        wrappedDek.isAcceptableOrUnknown(data['wrapped_dek']!, _wrappedDekMeta),
      );
    } else if (isInserting) {
      context.missing(_wrappedDekMeta);
    }
    if (data.containsKey('encryption_version')) {
      context.handle(
        _encryptionVersionMeta,
        encryptionVersion.isAcceptableOrUnknown(
          data['encryption_version']!,
          _encryptionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptionVersionMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStatusMeta);
    }
    if (data.containsKey('backup_status')) {
      context.handle(
        _backupStatusMeta,
        backupStatus.isAcceptableOrUnknown(
          data['backup_status']!,
          _backupStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_backupStatusMeta);
    }
    if (data.containsKey('checksum_sha256')) {
      context.handle(
        _checksumSha256Meta,
        checksumSha256.isAcceptableOrUnknown(
          data['checksum_sha256']!,
          _checksumSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checksumSha256Meta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('is_trashed')) {
      context.handle(
        _isTrashedMeta,
        isTrashed.isAcceptableOrUnknown(data['is_trashed']!, _isTrashedMeta),
      );
    }
    if (data.containsKey('trash_expires_at_ms')) {
      context.handle(
        _trashExpiresAtMsMeta,
        trashExpiresAtMs.isAcceptableOrUnknown(
          data['trash_expires_at_ms']!,
          _trashExpiresAtMsMeta,
        ),
      );
    }
    if (data.containsKey('deleted_tombstone_at_ms')) {
      context.handle(
        _deletedTombstoneAtMsMeta,
        deletedTombstoneAtMs.isAcceptableOrUnknown(
          data['deleted_tombstone_at_ms']!,
          _deletedTombstoneAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      originalFilename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_filename'],
      )!,
      createdTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_time_ms'],
      )!,
      importedTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_time_ms'],
      )!,
      modifiedTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_time_ms'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorite'],
      )!,
      encryptedFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_file_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      )!,
      thumbnailNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_nonce'],
      )!,
      photoNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_nonce'],
      )!,
      wrappedDek: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wrapped_dek'],
      )!,
      encryptionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}encryption_version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      backupStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_status'],
      )!,
      checksumSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum_sha256'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      isTrashed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_trashed'],
      )!,
      trashExpiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}trash_expires_at_ms'],
      ),
      deletedTombstoneAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_tombstone_at_ms'],
      ),
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }
}

class VaultPhoto extends DataClass implements Insertable<VaultPhoto> {
  final String id;
  final String originalFilename;
  final int createdTimeMs;
  final int importedTimeMs;
  final int modifiedTimeMs;
  final String source;
  final String? albumId;
  final int favorite;
  final String encryptedFilePath;
  final String thumbnailPath;
  final String thumbnailNonce;
  final String photoNonce;
  final String wrappedDek;
  final int encryptionVersion;
  final String syncStatus;
  final String backupStatus;
  final String checksumSha256;
  final int fileSize;
  final String mimeType;
  final int isTrashed;
  final int? trashExpiresAtMs;
  final int? deletedTombstoneAtMs;
  const VaultPhoto({
    required this.id,
    required this.originalFilename,
    required this.createdTimeMs,
    required this.importedTimeMs,
    required this.modifiedTimeMs,
    required this.source,
    this.albumId,
    required this.favorite,
    required this.encryptedFilePath,
    required this.thumbnailPath,
    required this.thumbnailNonce,
    required this.photoNonce,
    required this.wrappedDek,
    required this.encryptionVersion,
    required this.syncStatus,
    required this.backupStatus,
    required this.checksumSha256,
    required this.fileSize,
    required this.mimeType,
    required this.isTrashed,
    this.trashExpiresAtMs,
    this.deletedTombstoneAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['original_filename'] = Variable<String>(originalFilename);
    map['created_time_ms'] = Variable<int>(createdTimeMs);
    map['imported_time_ms'] = Variable<int>(importedTimeMs);
    map['modified_time_ms'] = Variable<int>(modifiedTimeMs);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    map['favorite'] = Variable<int>(favorite);
    map['encrypted_file_path'] = Variable<String>(encryptedFilePath);
    map['thumbnail_path'] = Variable<String>(thumbnailPath);
    map['thumbnail_nonce'] = Variable<String>(thumbnailNonce);
    map['photo_nonce'] = Variable<String>(photoNonce);
    map['wrapped_dek'] = Variable<String>(wrappedDek);
    map['encryption_version'] = Variable<int>(encryptionVersion);
    map['sync_status'] = Variable<String>(syncStatus);
    map['backup_status'] = Variable<String>(backupStatus);
    map['checksum_sha256'] = Variable<String>(checksumSha256);
    map['file_size'] = Variable<int>(fileSize);
    map['mime_type'] = Variable<String>(mimeType);
    map['is_trashed'] = Variable<int>(isTrashed);
    if (!nullToAbsent || trashExpiresAtMs != null) {
      map['trash_expires_at_ms'] = Variable<int>(trashExpiresAtMs);
    }
    if (!nullToAbsent || deletedTombstoneAtMs != null) {
      map['deleted_tombstone_at_ms'] = Variable<int>(deletedTombstoneAtMs);
    }
    return map;
  }

  PhotosCompanion toCompanion(bool nullToAbsent) {
    return PhotosCompanion(
      id: Value(id),
      originalFilename: Value(originalFilename),
      createdTimeMs: Value(createdTimeMs),
      importedTimeMs: Value(importedTimeMs),
      modifiedTimeMs: Value(modifiedTimeMs),
      source: Value(source),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      favorite: Value(favorite),
      encryptedFilePath: Value(encryptedFilePath),
      thumbnailPath: Value(thumbnailPath),
      thumbnailNonce: Value(thumbnailNonce),
      photoNonce: Value(photoNonce),
      wrappedDek: Value(wrappedDek),
      encryptionVersion: Value(encryptionVersion),
      syncStatus: Value(syncStatus),
      backupStatus: Value(backupStatus),
      checksumSha256: Value(checksumSha256),
      fileSize: Value(fileSize),
      mimeType: Value(mimeType),
      isTrashed: Value(isTrashed),
      trashExpiresAtMs: trashExpiresAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(trashExpiresAtMs),
      deletedTombstoneAtMs: deletedTombstoneAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedTombstoneAtMs),
    );
  }

  factory VaultPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultPhoto(
      id: serializer.fromJson<String>(json['id']),
      originalFilename: serializer.fromJson<String>(json['originalFilename']),
      createdTimeMs: serializer.fromJson<int>(json['createdTimeMs']),
      importedTimeMs: serializer.fromJson<int>(json['importedTimeMs']),
      modifiedTimeMs: serializer.fromJson<int>(json['modifiedTimeMs']),
      source: serializer.fromJson<String>(json['source']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      favorite: serializer.fromJson<int>(json['favorite']),
      encryptedFilePath: serializer.fromJson<String>(json['encryptedFilePath']),
      thumbnailPath: serializer.fromJson<String>(json['thumbnailPath']),
      thumbnailNonce: serializer.fromJson<String>(json['thumbnailNonce']),
      photoNonce: serializer.fromJson<String>(json['photoNonce']),
      wrappedDek: serializer.fromJson<String>(json['wrappedDek']),
      encryptionVersion: serializer.fromJson<int>(json['encryptionVersion']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      backupStatus: serializer.fromJson<String>(json['backupStatus']),
      checksumSha256: serializer.fromJson<String>(json['checksumSha256']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      isTrashed: serializer.fromJson<int>(json['isTrashed']),
      trashExpiresAtMs: serializer.fromJson<int?>(json['trashExpiresAtMs']),
      deletedTombstoneAtMs: serializer.fromJson<int?>(
        json['deletedTombstoneAtMs'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'originalFilename': serializer.toJson<String>(originalFilename),
      'createdTimeMs': serializer.toJson<int>(createdTimeMs),
      'importedTimeMs': serializer.toJson<int>(importedTimeMs),
      'modifiedTimeMs': serializer.toJson<int>(modifiedTimeMs),
      'source': serializer.toJson<String>(source),
      'albumId': serializer.toJson<String?>(albumId),
      'favorite': serializer.toJson<int>(favorite),
      'encryptedFilePath': serializer.toJson<String>(encryptedFilePath),
      'thumbnailPath': serializer.toJson<String>(thumbnailPath),
      'thumbnailNonce': serializer.toJson<String>(thumbnailNonce),
      'photoNonce': serializer.toJson<String>(photoNonce),
      'wrappedDek': serializer.toJson<String>(wrappedDek),
      'encryptionVersion': serializer.toJson<int>(encryptionVersion),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'backupStatus': serializer.toJson<String>(backupStatus),
      'checksumSha256': serializer.toJson<String>(checksumSha256),
      'fileSize': serializer.toJson<int>(fileSize),
      'mimeType': serializer.toJson<String>(mimeType),
      'isTrashed': serializer.toJson<int>(isTrashed),
      'trashExpiresAtMs': serializer.toJson<int?>(trashExpiresAtMs),
      'deletedTombstoneAtMs': serializer.toJson<int?>(deletedTombstoneAtMs),
    };
  }

  VaultPhoto copyWith({
    String? id,
    String? originalFilename,
    int? createdTimeMs,
    int? importedTimeMs,
    int? modifiedTimeMs,
    String? source,
    Value<String?> albumId = const Value.absent(),
    int? favorite,
    String? encryptedFilePath,
    String? thumbnailPath,
    String? thumbnailNonce,
    String? photoNonce,
    String? wrappedDek,
    int? encryptionVersion,
    String? syncStatus,
    String? backupStatus,
    String? checksumSha256,
    int? fileSize,
    String? mimeType,
    int? isTrashed,
    Value<int?> trashExpiresAtMs = const Value.absent(),
    Value<int?> deletedTombstoneAtMs = const Value.absent(),
  }) => VaultPhoto(
    id: id ?? this.id,
    originalFilename: originalFilename ?? this.originalFilename,
    createdTimeMs: createdTimeMs ?? this.createdTimeMs,
    importedTimeMs: importedTimeMs ?? this.importedTimeMs,
    modifiedTimeMs: modifiedTimeMs ?? this.modifiedTimeMs,
    source: source ?? this.source,
    albumId: albumId.present ? albumId.value : this.albumId,
    favorite: favorite ?? this.favorite,
    encryptedFilePath: encryptedFilePath ?? this.encryptedFilePath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    thumbnailNonce: thumbnailNonce ?? this.thumbnailNonce,
    photoNonce: photoNonce ?? this.photoNonce,
    wrappedDek: wrappedDek ?? this.wrappedDek,
    encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    syncStatus: syncStatus ?? this.syncStatus,
    backupStatus: backupStatus ?? this.backupStatus,
    checksumSha256: checksumSha256 ?? this.checksumSha256,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType ?? this.mimeType,
    isTrashed: isTrashed ?? this.isTrashed,
    trashExpiresAtMs: trashExpiresAtMs.present
        ? trashExpiresAtMs.value
        : this.trashExpiresAtMs,
    deletedTombstoneAtMs: deletedTombstoneAtMs.present
        ? deletedTombstoneAtMs.value
        : this.deletedTombstoneAtMs,
  );
  VaultPhoto copyWithCompanion(PhotosCompanion data) {
    return VaultPhoto(
      id: data.id.present ? data.id.value : this.id,
      originalFilename: data.originalFilename.present
          ? data.originalFilename.value
          : this.originalFilename,
      createdTimeMs: data.createdTimeMs.present
          ? data.createdTimeMs.value
          : this.createdTimeMs,
      importedTimeMs: data.importedTimeMs.present
          ? data.importedTimeMs.value
          : this.importedTimeMs,
      modifiedTimeMs: data.modifiedTimeMs.present
          ? data.modifiedTimeMs.value
          : this.modifiedTimeMs,
      source: data.source.present ? data.source.value : this.source,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      encryptedFilePath: data.encryptedFilePath.present
          ? data.encryptedFilePath.value
          : this.encryptedFilePath,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      thumbnailNonce: data.thumbnailNonce.present
          ? data.thumbnailNonce.value
          : this.thumbnailNonce,
      photoNonce: data.photoNonce.present
          ? data.photoNonce.value
          : this.photoNonce,
      wrappedDek: data.wrappedDek.present
          ? data.wrappedDek.value
          : this.wrappedDek,
      encryptionVersion: data.encryptionVersion.present
          ? data.encryptionVersion.value
          : this.encryptionVersion,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      backupStatus: data.backupStatus.present
          ? data.backupStatus.value
          : this.backupStatus,
      checksumSha256: data.checksumSha256.present
          ? data.checksumSha256.value
          : this.checksumSha256,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      isTrashed: data.isTrashed.present ? data.isTrashed.value : this.isTrashed,
      trashExpiresAtMs: data.trashExpiresAtMs.present
          ? data.trashExpiresAtMs.value
          : this.trashExpiresAtMs,
      deletedTombstoneAtMs: data.deletedTombstoneAtMs.present
          ? data.deletedTombstoneAtMs.value
          : this.deletedTombstoneAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultPhoto(')
          ..write('id: $id, ')
          ..write('originalFilename: $originalFilename, ')
          ..write('createdTimeMs: $createdTimeMs, ')
          ..write('importedTimeMs: $importedTimeMs, ')
          ..write('modifiedTimeMs: $modifiedTimeMs, ')
          ..write('source: $source, ')
          ..write('albumId: $albumId, ')
          ..write('favorite: $favorite, ')
          ..write('encryptedFilePath: $encryptedFilePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('thumbnailNonce: $thumbnailNonce, ')
          ..write('photoNonce: $photoNonce, ')
          ..write('wrappedDek: $wrappedDek, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('backupStatus: $backupStatus, ')
          ..write('checksumSha256: $checksumSha256, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('trashExpiresAtMs: $trashExpiresAtMs, ')
          ..write('deletedTombstoneAtMs: $deletedTombstoneAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    originalFilename,
    createdTimeMs,
    importedTimeMs,
    modifiedTimeMs,
    source,
    albumId,
    favorite,
    encryptedFilePath,
    thumbnailPath,
    thumbnailNonce,
    photoNonce,
    wrappedDek,
    encryptionVersion,
    syncStatus,
    backupStatus,
    checksumSha256,
    fileSize,
    mimeType,
    isTrashed,
    trashExpiresAtMs,
    deletedTombstoneAtMs,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultPhoto &&
          other.id == this.id &&
          other.originalFilename == this.originalFilename &&
          other.createdTimeMs == this.createdTimeMs &&
          other.importedTimeMs == this.importedTimeMs &&
          other.modifiedTimeMs == this.modifiedTimeMs &&
          other.source == this.source &&
          other.albumId == this.albumId &&
          other.favorite == this.favorite &&
          other.encryptedFilePath == this.encryptedFilePath &&
          other.thumbnailPath == this.thumbnailPath &&
          other.thumbnailNonce == this.thumbnailNonce &&
          other.photoNonce == this.photoNonce &&
          other.wrappedDek == this.wrappedDek &&
          other.encryptionVersion == this.encryptionVersion &&
          other.syncStatus == this.syncStatus &&
          other.backupStatus == this.backupStatus &&
          other.checksumSha256 == this.checksumSha256 &&
          other.fileSize == this.fileSize &&
          other.mimeType == this.mimeType &&
          other.isTrashed == this.isTrashed &&
          other.trashExpiresAtMs == this.trashExpiresAtMs &&
          other.deletedTombstoneAtMs == this.deletedTombstoneAtMs);
}

class PhotosCompanion extends UpdateCompanion<VaultPhoto> {
  final Value<String> id;
  final Value<String> originalFilename;
  final Value<int> createdTimeMs;
  final Value<int> importedTimeMs;
  final Value<int> modifiedTimeMs;
  final Value<String> source;
  final Value<String?> albumId;
  final Value<int> favorite;
  final Value<String> encryptedFilePath;
  final Value<String> thumbnailPath;
  final Value<String> thumbnailNonce;
  final Value<String> photoNonce;
  final Value<String> wrappedDek;
  final Value<int> encryptionVersion;
  final Value<String> syncStatus;
  final Value<String> backupStatus;
  final Value<String> checksumSha256;
  final Value<int> fileSize;
  final Value<String> mimeType;
  final Value<int> isTrashed;
  final Value<int?> trashExpiresAtMs;
  final Value<int?> deletedTombstoneAtMs;
  final Value<int> rowid;
  const PhotosCompanion({
    this.id = const Value.absent(),
    this.originalFilename = const Value.absent(),
    this.createdTimeMs = const Value.absent(),
    this.importedTimeMs = const Value.absent(),
    this.modifiedTimeMs = const Value.absent(),
    this.source = const Value.absent(),
    this.albumId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.encryptedFilePath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.thumbnailNonce = const Value.absent(),
    this.photoNonce = const Value.absent(),
    this.wrappedDek = const Value.absent(),
    this.encryptionVersion = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.backupStatus = const Value.absent(),
    this.checksumSha256 = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.isTrashed = const Value.absent(),
    this.trashExpiresAtMs = const Value.absent(),
    this.deletedTombstoneAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotosCompanion.insert({
    required String id,
    required String originalFilename,
    required int createdTimeMs,
    required int importedTimeMs,
    required int modifiedTimeMs,
    required String source,
    this.albumId = const Value.absent(),
    this.favorite = const Value.absent(),
    required String encryptedFilePath,
    required String thumbnailPath,
    required String thumbnailNonce,
    required String photoNonce,
    required String wrappedDek,
    required int encryptionVersion,
    required String syncStatus,
    required String backupStatus,
    required String checksumSha256,
    required int fileSize,
    required String mimeType,
    this.isTrashed = const Value.absent(),
    this.trashExpiresAtMs = const Value.absent(),
    this.deletedTombstoneAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       originalFilename = Value(originalFilename),
       createdTimeMs = Value(createdTimeMs),
       importedTimeMs = Value(importedTimeMs),
       modifiedTimeMs = Value(modifiedTimeMs),
       source = Value(source),
       encryptedFilePath = Value(encryptedFilePath),
       thumbnailPath = Value(thumbnailPath),
       thumbnailNonce = Value(thumbnailNonce),
       photoNonce = Value(photoNonce),
       wrappedDek = Value(wrappedDek),
       encryptionVersion = Value(encryptionVersion),
       syncStatus = Value(syncStatus),
       backupStatus = Value(backupStatus),
       checksumSha256 = Value(checksumSha256),
       fileSize = Value(fileSize),
       mimeType = Value(mimeType);
  static Insertable<VaultPhoto> custom({
    Expression<String>? id,
    Expression<String>? originalFilename,
    Expression<int>? createdTimeMs,
    Expression<int>? importedTimeMs,
    Expression<int>? modifiedTimeMs,
    Expression<String>? source,
    Expression<String>? albumId,
    Expression<int>? favorite,
    Expression<String>? encryptedFilePath,
    Expression<String>? thumbnailPath,
    Expression<String>? thumbnailNonce,
    Expression<String>? photoNonce,
    Expression<String>? wrappedDek,
    Expression<int>? encryptionVersion,
    Expression<String>? syncStatus,
    Expression<String>? backupStatus,
    Expression<String>? checksumSha256,
    Expression<int>? fileSize,
    Expression<String>? mimeType,
    Expression<int>? isTrashed,
    Expression<int>? trashExpiresAtMs,
    Expression<int>? deletedTombstoneAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originalFilename != null) 'original_filename': originalFilename,
      if (createdTimeMs != null) 'created_time_ms': createdTimeMs,
      if (importedTimeMs != null) 'imported_time_ms': importedTimeMs,
      if (modifiedTimeMs != null) 'modified_time_ms': modifiedTimeMs,
      if (source != null) 'source': source,
      if (albumId != null) 'album_id': albumId,
      if (favorite != null) 'favorite': favorite,
      if (encryptedFilePath != null) 'encrypted_file_path': encryptedFilePath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (thumbnailNonce != null) 'thumbnail_nonce': thumbnailNonce,
      if (photoNonce != null) 'photo_nonce': photoNonce,
      if (wrappedDek != null) 'wrapped_dek': wrappedDek,
      if (encryptionVersion != null) 'encryption_version': encryptionVersion,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (backupStatus != null) 'backup_status': backupStatus,
      if (checksumSha256 != null) 'checksum_sha256': checksumSha256,
      if (fileSize != null) 'file_size': fileSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (isTrashed != null) 'is_trashed': isTrashed,
      if (trashExpiresAtMs != null) 'trash_expires_at_ms': trashExpiresAtMs,
      if (deletedTombstoneAtMs != null)
        'deleted_tombstone_at_ms': deletedTombstoneAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? originalFilename,
    Value<int>? createdTimeMs,
    Value<int>? importedTimeMs,
    Value<int>? modifiedTimeMs,
    Value<String>? source,
    Value<String?>? albumId,
    Value<int>? favorite,
    Value<String>? encryptedFilePath,
    Value<String>? thumbnailPath,
    Value<String>? thumbnailNonce,
    Value<String>? photoNonce,
    Value<String>? wrappedDek,
    Value<int>? encryptionVersion,
    Value<String>? syncStatus,
    Value<String>? backupStatus,
    Value<String>? checksumSha256,
    Value<int>? fileSize,
    Value<String>? mimeType,
    Value<int>? isTrashed,
    Value<int?>? trashExpiresAtMs,
    Value<int?>? deletedTombstoneAtMs,
    Value<int>? rowid,
  }) {
    return PhotosCompanion(
      id: id ?? this.id,
      originalFilename: originalFilename ?? this.originalFilename,
      createdTimeMs: createdTimeMs ?? this.createdTimeMs,
      importedTimeMs: importedTimeMs ?? this.importedTimeMs,
      modifiedTimeMs: modifiedTimeMs ?? this.modifiedTimeMs,
      source: source ?? this.source,
      albumId: albumId ?? this.albumId,
      favorite: favorite ?? this.favorite,
      encryptedFilePath: encryptedFilePath ?? this.encryptedFilePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      thumbnailNonce: thumbnailNonce ?? this.thumbnailNonce,
      photoNonce: photoNonce ?? this.photoNonce,
      wrappedDek: wrappedDek ?? this.wrappedDek,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      syncStatus: syncStatus ?? this.syncStatus,
      backupStatus: backupStatus ?? this.backupStatus,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      isTrashed: isTrashed ?? this.isTrashed,
      trashExpiresAtMs: trashExpiresAtMs ?? this.trashExpiresAtMs,
      deletedTombstoneAtMs: deletedTombstoneAtMs ?? this.deletedTombstoneAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (originalFilename.present) {
      map['original_filename'] = Variable<String>(originalFilename.value);
    }
    if (createdTimeMs.present) {
      map['created_time_ms'] = Variable<int>(createdTimeMs.value);
    }
    if (importedTimeMs.present) {
      map['imported_time_ms'] = Variable<int>(importedTimeMs.value);
    }
    if (modifiedTimeMs.present) {
      map['modified_time_ms'] = Variable<int>(modifiedTimeMs.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<int>(favorite.value);
    }
    if (encryptedFilePath.present) {
      map['encrypted_file_path'] = Variable<String>(encryptedFilePath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (thumbnailNonce.present) {
      map['thumbnail_nonce'] = Variable<String>(thumbnailNonce.value);
    }
    if (photoNonce.present) {
      map['photo_nonce'] = Variable<String>(photoNonce.value);
    }
    if (wrappedDek.present) {
      map['wrapped_dek'] = Variable<String>(wrappedDek.value);
    }
    if (encryptionVersion.present) {
      map['encryption_version'] = Variable<int>(encryptionVersion.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (backupStatus.present) {
      map['backup_status'] = Variable<String>(backupStatus.value);
    }
    if (checksumSha256.present) {
      map['checksum_sha256'] = Variable<String>(checksumSha256.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (isTrashed.present) {
      map['is_trashed'] = Variable<int>(isTrashed.value);
    }
    if (trashExpiresAtMs.present) {
      map['trash_expires_at_ms'] = Variable<int>(trashExpiresAtMs.value);
    }
    if (deletedTombstoneAtMs.present) {
      map['deleted_tombstone_at_ms'] = Variable<int>(
        deletedTombstoneAtMs.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('id: $id, ')
          ..write('originalFilename: $originalFilename, ')
          ..write('createdTimeMs: $createdTimeMs, ')
          ..write('importedTimeMs: $importedTimeMs, ')
          ..write('modifiedTimeMs: $modifiedTimeMs, ')
          ..write('source: $source, ')
          ..write('albumId: $albumId, ')
          ..write('favorite: $favorite, ')
          ..write('encryptedFilePath: $encryptedFilePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('thumbnailNonce: $thumbnailNonce, ')
          ..write('photoNonce: $photoNonce, ')
          ..write('wrappedDek: $wrappedDek, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('backupStatus: $backupStatus, ')
          ..write('checksumSha256: $checksumSha256, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('trashExpiresAtMs: $trashExpiresAtMs, ')
          ..write('deletedTombstoneAtMs: $deletedTombstoneAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, VaultAlbum> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAtMs, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultAlbum> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultAlbum map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultAlbum(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class VaultAlbum extends DataClass implements Insertable<VaultAlbum> {
  final String id;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;
  const VaultAlbum({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      name: Value(name),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory VaultAlbum.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultAlbum(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  VaultAlbum copyWith({
    String? id,
    String? name,
    int? createdAtMs,
    int? updatedAtMs,
  }) => VaultAlbum(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  VaultAlbum copyWithCompanion(AlbumsCompanion data) {
    return VaultAlbum(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultAlbum(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAtMs, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultAlbum &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class AlbumsCompanion extends UpdateCompanion<VaultAlbum> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String id,
    required String name,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<VaultAlbum> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return AlbumsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, VaultTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultTag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class VaultTag extends DataClass implements Insertable<VaultTag> {
  final String id;
  final String name;
  final int createdAtMs;
  const VaultTag({
    required this.id,
    required this.name,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory VaultTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultTag(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  VaultTag copyWith({String? id, String? name, int? createdAtMs}) => VaultTag(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  VaultTag copyWithCompanion(TagsCompanion data) {
    return VaultTag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultTag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultTag &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAtMs == this.createdAtMs);
}

class TagsCompanion extends UpdateCompanion<VaultTag> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAtMs = Value(createdAtMs);
  static Insertable<VaultTag> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotoTagsTable extends PhotoTags
    with TableInfo<$PhotoTagsTable, PhotoTagLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotoTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [photoId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photo_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhotoTagLink> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_photoIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {photoId, tagId};
  @override
  PhotoTagLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhotoTagLink(
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $PhotoTagsTable createAlias(String alias) {
    return $PhotoTagsTable(attachedDatabase, alias);
  }
}

class PhotoTagLink extends DataClass implements Insertable<PhotoTagLink> {
  final String photoId;
  final String tagId;
  const PhotoTagLink({required this.photoId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['photo_id'] = Variable<String>(photoId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  PhotoTagsCompanion toCompanion(bool nullToAbsent) {
    return PhotoTagsCompanion(photoId: Value(photoId), tagId: Value(tagId));
  }

  factory PhotoTagLink.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhotoTagLink(
      photoId: serializer.fromJson<String>(json['photoId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'photoId': serializer.toJson<String>(photoId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  PhotoTagLink copyWith({String? photoId, String? tagId}) => PhotoTagLink(
    photoId: photoId ?? this.photoId,
    tagId: tagId ?? this.tagId,
  );
  PhotoTagLink copyWithCompanion(PhotoTagsCompanion data) {
    return PhotoTagLink(
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhotoTagLink(')
          ..write('photoId: $photoId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(photoId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhotoTagLink &&
          other.photoId == this.photoId &&
          other.tagId == this.tagId);
}

class PhotoTagsCompanion extends UpdateCompanion<PhotoTagLink> {
  final Value<String> photoId;
  final Value<String> tagId;
  final Value<int> rowid;
  const PhotoTagsCompanion({
    this.photoId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotoTagsCompanion.insert({
    required String photoId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : photoId = Value(photoId),
       tagId = Value(tagId);
  static Insertable<PhotoTagLink> custom({
    Expression<String>? photoId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (photoId != null) 'photo_id': photoId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotoTagsCompanion copyWith({
    Value<String>? photoId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return PhotoTagsCompanion(
      photoId: photoId ?? this.photoId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotoTagsCompanion(')
          ..write('photoId: $photoId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VaultTable extends Vault with TableInfo<$VaultTable, VaultMetadata> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vmkWrapVersionMeta = const VerificationMeta(
    'vmkWrapVersion',
  );
  @override
  late final GeneratedColumn<int> vmkWrapVersion = GeneratedColumn<int>(
    'vmk_wrap_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeEncryptionVersionMeta =
      const VerificationMeta('activeEncryptionVersion');
  @override
  late final GeneratedColumn<int> activeEncryptionVersion =
      GeneratedColumn<int>(
        'active_encryption_version',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mode,
    createdAtMs,
    vmkWrapVersion,
    activeEncryptionVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vault';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultMetadata> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('vmk_wrap_version')) {
      context.handle(
        _vmkWrapVersionMeta,
        vmkWrapVersion.isAcceptableOrUnknown(
          data['vmk_wrap_version']!,
          _vmkWrapVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_vmkWrapVersionMeta);
    }
    if (data.containsKey('active_encryption_version')) {
      context.handle(
        _activeEncryptionVersionMeta,
        activeEncryptionVersion.isAcceptableOrUnknown(
          data['active_encryption_version']!,
          _activeEncryptionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activeEncryptionVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultMetadata map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultMetadata(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      vmkWrapVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vmk_wrap_version'],
      )!,
      activeEncryptionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_encryption_version'],
      )!,
    );
  }

  @override
  $VaultTable createAlias(String alias) {
    return $VaultTable(attachedDatabase, alias);
  }
}

class VaultMetadata extends DataClass implements Insertable<VaultMetadata> {
  final String id;
  final String mode;
  final int createdAtMs;
  final int vmkWrapVersion;
  final int activeEncryptionVersion;
  const VaultMetadata({
    required this.id,
    required this.mode,
    required this.createdAtMs,
    required this.vmkWrapVersion,
    required this.activeEncryptionVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['mode'] = Variable<String>(mode);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['vmk_wrap_version'] = Variable<int>(vmkWrapVersion);
    map['active_encryption_version'] = Variable<int>(activeEncryptionVersion);
    return map;
  }

  VaultCompanion toCompanion(bool nullToAbsent) {
    return VaultCompanion(
      id: Value(id),
      mode: Value(mode),
      createdAtMs: Value(createdAtMs),
      vmkWrapVersion: Value(vmkWrapVersion),
      activeEncryptionVersion: Value(activeEncryptionVersion),
    );
  }

  factory VaultMetadata.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultMetadata(
      id: serializer.fromJson<String>(json['id']),
      mode: serializer.fromJson<String>(json['mode']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      vmkWrapVersion: serializer.fromJson<int>(json['vmkWrapVersion']),
      activeEncryptionVersion: serializer.fromJson<int>(
        json['activeEncryptionVersion'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mode': serializer.toJson<String>(mode),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'vmkWrapVersion': serializer.toJson<int>(vmkWrapVersion),
      'activeEncryptionVersion': serializer.toJson<int>(
        activeEncryptionVersion,
      ),
    };
  }

  VaultMetadata copyWith({
    String? id,
    String? mode,
    int? createdAtMs,
    int? vmkWrapVersion,
    int? activeEncryptionVersion,
  }) => VaultMetadata(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    vmkWrapVersion: vmkWrapVersion ?? this.vmkWrapVersion,
    activeEncryptionVersion:
        activeEncryptionVersion ?? this.activeEncryptionVersion,
  );
  VaultMetadata copyWithCompanion(VaultCompanion data) {
    return VaultMetadata(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      vmkWrapVersion: data.vmkWrapVersion.present
          ? data.vmkWrapVersion.value
          : this.vmkWrapVersion,
      activeEncryptionVersion: data.activeEncryptionVersion.present
          ? data.activeEncryptionVersion.value
          : this.activeEncryptionVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultMetadata(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('vmkWrapVersion: $vmkWrapVersion, ')
          ..write('activeEncryptionVersion: $activeEncryptionVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mode,
    createdAtMs,
    vmkWrapVersion,
    activeEncryptionVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultMetadata &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.createdAtMs == this.createdAtMs &&
          other.vmkWrapVersion == this.vmkWrapVersion &&
          other.activeEncryptionVersion == this.activeEncryptionVersion);
}

class VaultCompanion extends UpdateCompanion<VaultMetadata> {
  final Value<String> id;
  final Value<String> mode;
  final Value<int> createdAtMs;
  final Value<int> vmkWrapVersion;
  final Value<int> activeEncryptionVersion;
  final Value<int> rowid;
  const VaultCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.vmkWrapVersion = const Value.absent(),
    this.activeEncryptionVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VaultCompanion.insert({
    required String id,
    required String mode,
    required int createdAtMs,
    required int vmkWrapVersion,
    required int activeEncryptionVersion,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mode = Value(mode),
       createdAtMs = Value(createdAtMs),
       vmkWrapVersion = Value(vmkWrapVersion),
       activeEncryptionVersion = Value(activeEncryptionVersion);
  static Insertable<VaultMetadata> custom({
    Expression<String>? id,
    Expression<String>? mode,
    Expression<int>? createdAtMs,
    Expression<int>? vmkWrapVersion,
    Expression<int>? activeEncryptionVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (vmkWrapVersion != null) 'vmk_wrap_version': vmkWrapVersion,
      if (activeEncryptionVersion != null)
        'active_encryption_version': activeEncryptionVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VaultCompanion copyWith({
    Value<String>? id,
    Value<String>? mode,
    Value<int>? createdAtMs,
    Value<int>? vmkWrapVersion,
    Value<int>? activeEncryptionVersion,
    Value<int>? rowid,
  }) {
    return VaultCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      vmkWrapVersion: vmkWrapVersion ?? this.vmkWrapVersion,
      activeEncryptionVersion:
          activeEncryptionVersion ?? this.activeEncryptionVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (vmkWrapVersion.present) {
      map['vmk_wrap_version'] = Variable<int>(vmkWrapVersion.value);
    }
    if (activeEncryptionVersion.present) {
      map['active_encryption_version'] = Variable<int>(
        activeEncryptionVersion.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('vmkWrapVersion: $vmkWrapVersion, ')
          ..write('activeEncryptionVersion: $activeEncryptionVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThumbnailsTable extends Thumbnails
    with TableInfo<$ThumbnailsTable, VaultThumbnail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThumbnailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedPathMeta = const VerificationMeta(
    'encryptedPath',
  );
  @override
  late final GeneratedColumn<String> encryptedPath = GeneratedColumn<String>(
    'encrypted_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptionVersionMeta = const VerificationMeta(
    'encryptionVersion',
  );
  @override
  late final GeneratedColumn<int> encryptionVersion = GeneratedColumn<int>(
    'encryption_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumSha256Meta = const VerificationMeta(
    'checksumSha256',
  );
  @override
  late final GeneratedColumn<String> checksumSha256 = GeneratedColumn<String>(
    'checksum_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    photoId,
    encryptedPath,
    nonce,
    encryptionVersion,
    width,
    height,
    checksumSha256,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thumbnails';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultThumbnail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_photoIdMeta);
    }
    if (data.containsKey('encrypted_path')) {
      context.handle(
        _encryptedPathMeta,
        encryptedPath.isAcceptableOrUnknown(
          data['encrypted_path']!,
          _encryptedPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPathMeta);
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('encryption_version')) {
      context.handle(
        _encryptionVersionMeta,
        encryptionVersion.isAcceptableOrUnknown(
          data['encryption_version']!,
          _encryptionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptionVersionMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('checksum_sha256')) {
      context.handle(
        _checksumSha256Meta,
        checksumSha256.isAcceptableOrUnknown(
          data['checksum_sha256']!,
          _checksumSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checksumSha256Meta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultThumbnail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultThumbnail(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      )!,
      encryptedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_path'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nonce'],
      )!,
      encryptionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}encryption_version'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      checksumSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum_sha256'],
      )!,
    );
  }

  @override
  $ThumbnailsTable createAlias(String alias) {
    return $ThumbnailsTable(attachedDatabase, alias);
  }
}

class VaultThumbnail extends DataClass implements Insertable<VaultThumbnail> {
  final String id;
  final String photoId;
  final String encryptedPath;
  final String nonce;
  final int encryptionVersion;
  final int width;
  final int height;
  final String checksumSha256;
  const VaultThumbnail({
    required this.id,
    required this.photoId,
    required this.encryptedPath,
    required this.nonce,
    required this.encryptionVersion,
    required this.width,
    required this.height,
    required this.checksumSha256,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['photo_id'] = Variable<String>(photoId);
    map['encrypted_path'] = Variable<String>(encryptedPath);
    map['nonce'] = Variable<String>(nonce);
    map['encryption_version'] = Variable<int>(encryptionVersion);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['checksum_sha256'] = Variable<String>(checksumSha256);
    return map;
  }

  ThumbnailsCompanion toCompanion(bool nullToAbsent) {
    return ThumbnailsCompanion(
      id: Value(id),
      photoId: Value(photoId),
      encryptedPath: Value(encryptedPath),
      nonce: Value(nonce),
      encryptionVersion: Value(encryptionVersion),
      width: Value(width),
      height: Value(height),
      checksumSha256: Value(checksumSha256),
    );
  }

  factory VaultThumbnail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultThumbnail(
      id: serializer.fromJson<String>(json['id']),
      photoId: serializer.fromJson<String>(json['photoId']),
      encryptedPath: serializer.fromJson<String>(json['encryptedPath']),
      nonce: serializer.fromJson<String>(json['nonce']),
      encryptionVersion: serializer.fromJson<int>(json['encryptionVersion']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      checksumSha256: serializer.fromJson<String>(json['checksumSha256']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'photoId': serializer.toJson<String>(photoId),
      'encryptedPath': serializer.toJson<String>(encryptedPath),
      'nonce': serializer.toJson<String>(nonce),
      'encryptionVersion': serializer.toJson<int>(encryptionVersion),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'checksumSha256': serializer.toJson<String>(checksumSha256),
    };
  }

  VaultThumbnail copyWith({
    String? id,
    String? photoId,
    String? encryptedPath,
    String? nonce,
    int? encryptionVersion,
    int? width,
    int? height,
    String? checksumSha256,
  }) => VaultThumbnail(
    id: id ?? this.id,
    photoId: photoId ?? this.photoId,
    encryptedPath: encryptedPath ?? this.encryptedPath,
    nonce: nonce ?? this.nonce,
    encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    width: width ?? this.width,
    height: height ?? this.height,
    checksumSha256: checksumSha256 ?? this.checksumSha256,
  );
  VaultThumbnail copyWithCompanion(ThumbnailsCompanion data) {
    return VaultThumbnail(
      id: data.id.present ? data.id.value : this.id,
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      encryptedPath: data.encryptedPath.present
          ? data.encryptedPath.value
          : this.encryptedPath,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      encryptionVersion: data.encryptionVersion.present
          ? data.encryptionVersion.value
          : this.encryptionVersion,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      checksumSha256: data.checksumSha256.present
          ? data.checksumSha256.value
          : this.checksumSha256,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultThumbnail(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('encryptedPath: $encryptedPath, ')
          ..write('nonce: $nonce, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('checksumSha256: $checksumSha256')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    photoId,
    encryptedPath,
    nonce,
    encryptionVersion,
    width,
    height,
    checksumSha256,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultThumbnail &&
          other.id == this.id &&
          other.photoId == this.photoId &&
          other.encryptedPath == this.encryptedPath &&
          other.nonce == this.nonce &&
          other.encryptionVersion == this.encryptionVersion &&
          other.width == this.width &&
          other.height == this.height &&
          other.checksumSha256 == this.checksumSha256);
}

class ThumbnailsCompanion extends UpdateCompanion<VaultThumbnail> {
  final Value<String> id;
  final Value<String> photoId;
  final Value<String> encryptedPath;
  final Value<String> nonce;
  final Value<int> encryptionVersion;
  final Value<int> width;
  final Value<int> height;
  final Value<String> checksumSha256;
  final Value<int> rowid;
  const ThumbnailsCompanion({
    this.id = const Value.absent(),
    this.photoId = const Value.absent(),
    this.encryptedPath = const Value.absent(),
    this.nonce = const Value.absent(),
    this.encryptionVersion = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.checksumSha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThumbnailsCompanion.insert({
    required String id,
    required String photoId,
    required String encryptedPath,
    required String nonce,
    required int encryptionVersion,
    required int width,
    required int height,
    required String checksumSha256,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       photoId = Value(photoId),
       encryptedPath = Value(encryptedPath),
       nonce = Value(nonce),
       encryptionVersion = Value(encryptionVersion),
       width = Value(width),
       height = Value(height),
       checksumSha256 = Value(checksumSha256);
  static Insertable<VaultThumbnail> custom({
    Expression<String>? id,
    Expression<String>? photoId,
    Expression<String>? encryptedPath,
    Expression<String>? nonce,
    Expression<int>? encryptionVersion,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? checksumSha256,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (photoId != null) 'photo_id': photoId,
      if (encryptedPath != null) 'encrypted_path': encryptedPath,
      if (nonce != null) 'nonce': nonce,
      if (encryptionVersion != null) 'encryption_version': encryptionVersion,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (checksumSha256 != null) 'checksum_sha256': checksumSha256,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThumbnailsCompanion copyWith({
    Value<String>? id,
    Value<String>? photoId,
    Value<String>? encryptedPath,
    Value<String>? nonce,
    Value<int>? encryptionVersion,
    Value<int>? width,
    Value<int>? height,
    Value<String>? checksumSha256,
    Value<int>? rowid,
  }) {
    return ThumbnailsCompanion(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      encryptedPath: encryptedPath ?? this.encryptedPath,
      nonce: nonce ?? this.nonce,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      width: width ?? this.width,
      height: height ?? this.height,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (encryptedPath.present) {
      map['encrypted_path'] = Variable<String>(encryptedPath.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (encryptionVersion.present) {
      map['encryption_version'] = Variable<int>(encryptionVersion.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (checksumSha256.present) {
      map['checksum_sha256'] = Variable<String>(checksumSha256.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThumbnailsCompanion(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('encryptedPath: $encryptedPath, ')
          ..write('nonce: $nonce, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('checksumSha256: $checksumSha256, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _objectIdMeta = const VerificationMeta(
    'objectId',
  );
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
    'object_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectTypeMeta = const VerificationMeta(
    'objectType',
  );
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
    'object_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteVersionMeta = const VerificationMeta(
    'remoteVersion',
  );
  @override
  late final GeneratedColumn<int> remoteVersion = GeneratedColumn<int>(
    'remote_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    objectId,
    objectType,
    localVersion,
    remoteVersion,
    state,
    retryCount,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('object_id')) {
      context.handle(
        _objectIdMeta,
        objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
        _objectTypeMeta,
        objectType.isAcceptableOrUnknown(data['object_type']!, _objectTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localVersionMeta);
    }
    if (data.containsKey('remote_version')) {
      context.handle(
        _remoteVersionMeta,
        remoteVersion.isAcceptableOrUnknown(
          data['remote_version']!,
          _remoteVersionMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {objectId};
  @override
  SyncStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateEntry(
      objectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_id'],
      )!,
      objectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_type'],
      )!,
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      remoteVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_version'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateEntry extends DataClass implements Insertable<SyncStateEntry> {
  final String objectId;
  final String objectType;
  final int localVersion;
  final int? remoteVersion;
  final String state;
  final int retryCount;
  final int updatedAtMs;
  const SyncStateEntry({
    required this.objectId,
    required this.objectType,
    required this.localVersion,
    this.remoteVersion,
    required this.state,
    required this.retryCount,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['object_id'] = Variable<String>(objectId);
    map['object_type'] = Variable<String>(objectType);
    map['local_version'] = Variable<int>(localVersion);
    if (!nullToAbsent || remoteVersion != null) {
      map['remote_version'] = Variable<int>(remoteVersion);
    }
    map['state'] = Variable<String>(state);
    map['retry_count'] = Variable<int>(retryCount);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      objectId: Value(objectId),
      objectType: Value(objectType),
      localVersion: Value(localVersion),
      remoteVersion: remoteVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteVersion),
      state: Value(state),
      retryCount: Value(retryCount),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory SyncStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateEntry(
      objectId: serializer.fromJson<String>(json['objectId']),
      objectType: serializer.fromJson<String>(json['objectType']),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      remoteVersion: serializer.fromJson<int?>(json['remoteVersion']),
      state: serializer.fromJson<String>(json['state']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'objectId': serializer.toJson<String>(objectId),
      'objectType': serializer.toJson<String>(objectType),
      'localVersion': serializer.toJson<int>(localVersion),
      'remoteVersion': serializer.toJson<int?>(remoteVersion),
      'state': serializer.toJson<String>(state),
      'retryCount': serializer.toJson<int>(retryCount),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  SyncStateEntry copyWith({
    String? objectId,
    String? objectType,
    int? localVersion,
    Value<int?> remoteVersion = const Value.absent(),
    String? state,
    int? retryCount,
    int? updatedAtMs,
  }) => SyncStateEntry(
    objectId: objectId ?? this.objectId,
    objectType: objectType ?? this.objectType,
    localVersion: localVersion ?? this.localVersion,
    remoteVersion: remoteVersion.present
        ? remoteVersion.value
        : this.remoteVersion,
    state: state ?? this.state,
    retryCount: retryCount ?? this.retryCount,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  SyncStateEntry copyWithCompanion(SyncStateCompanion data) {
    return SyncStateEntry(
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      objectType: data.objectType.present
          ? data.objectType.value
          : this.objectType,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      remoteVersion: data.remoteVersion.present
          ? data.remoteVersion.value
          : this.remoteVersion,
      state: data.state.present ? data.state.value : this.state,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateEntry(')
          ..write('objectId: $objectId, ')
          ..write('objectType: $objectType, ')
          ..write('localVersion: $localVersion, ')
          ..write('remoteVersion: $remoteVersion, ')
          ..write('state: $state, ')
          ..write('retryCount: $retryCount, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    objectId,
    objectType,
    localVersion,
    remoteVersion,
    state,
    retryCount,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateEntry &&
          other.objectId == this.objectId &&
          other.objectType == this.objectType &&
          other.localVersion == this.localVersion &&
          other.remoteVersion == this.remoteVersion &&
          other.state == this.state &&
          other.retryCount == this.retryCount &&
          other.updatedAtMs == this.updatedAtMs);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateEntry> {
  final Value<String> objectId;
  final Value<String> objectType;
  final Value<int> localVersion;
  final Value<int?> remoteVersion;
  final Value<String> state;
  final Value<int> retryCount;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.objectId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.remoteVersion = const Value.absent(),
    this.state = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String objectId,
    required String objectType,
    required int localVersion,
    this.remoteVersion = const Value.absent(),
    required String state,
    this.retryCount = const Value.absent(),
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : objectId = Value(objectId),
       objectType = Value(objectType),
       localVersion = Value(localVersion),
       state = Value(state),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<SyncStateEntry> custom({
    Expression<String>? objectId,
    Expression<String>? objectType,
    Expression<int>? localVersion,
    Expression<int>? remoteVersion,
    Expression<String>? state,
    Expression<int>? retryCount,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (objectId != null) 'object_id': objectId,
      if (objectType != null) 'object_type': objectType,
      if (localVersion != null) 'local_version': localVersion,
      if (remoteVersion != null) 'remote_version': remoteVersion,
      if (state != null) 'state': state,
      if (retryCount != null) 'retry_count': retryCount,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? objectId,
    Value<String>? objectType,
    Value<int>? localVersion,
    Value<int?>? remoteVersion,
    Value<String>? state,
    Value<int>? retryCount,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      objectId: objectId ?? this.objectId,
      objectType: objectType ?? this.objectType,
      localVersion: localVersion ?? this.localVersion,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      state: state ?? this.state,
      retryCount: retryCount ?? this.retryCount,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (remoteVersion.present) {
      map['remote_version'] = Variable<int>(remoteVersion.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('objectId: $objectId, ')
          ..write('objectType: $objectType, ')
          ..write('localVersion: $localVersion, ')
          ..write('remoteVersion: $remoteVersion, ')
          ..write('state: $state, ')
          ..write('retryCount: $retryCount, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupStateTable extends BackupState
    with TableInfo<$BackupStateTable, BackupStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backup_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  BackupStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupStateEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $BackupStateTable createAlias(String alias) {
    return $BackupStateTable(attachedDatabase, alias);
  }
}

class BackupStateEntry extends DataClass
    implements Insertable<BackupStateEntry> {
  final String key;
  final String value;
  final int updatedAtMs;
  const BackupStateEntry({
    required this.key,
    required this.value,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  BackupStateCompanion toCompanion(bool nullToAbsent) {
    return BackupStateCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory BackupStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupStateEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  BackupStateEntry copyWith({String? key, String? value, int? updatedAtMs}) =>
      BackupStateEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
  BackupStateEntry copyWithCompanion(BackupStateCompanion data) {
    return BackupStateEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupStateEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupStateEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtMs == this.updatedAtMs);
}

class BackupStateCompanion extends UpdateCompanion<BackupStateEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const BackupStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupStateCompanion.insert({
    required String key,
    required String value,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<BackupStateEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return BackupStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EncryptionVersionsTable extends EncryptionVersions
    with TableInfo<$EncryptionVersionsTable, EncryptionVersionEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EncryptionVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cipherMeta = const VerificationMeta('cipher');
  @override
  late final GeneratedColumn<String> cipher = GeneratedColumn<String>(
    'cipher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kdfMeta = const VerificationMeta('kdf');
  @override
  late final GeneratedColumn<String> kdf = GeneratedColumn<String>(
    'kdf',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paramsJsonMeta = const VerificationMeta(
    'paramsJson',
  );
  @override
  late final GeneratedColumn<String> paramsJson = GeneratedColumn<String>(
    'params_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<int> active = GeneratedColumn<int>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    version,
    cipher,
    kdf,
    paramsJson,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'encryption_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<EncryptionVersionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('cipher')) {
      context.handle(
        _cipherMeta,
        cipher.isAcceptableOrUnknown(data['cipher']!, _cipherMeta),
      );
    } else if (isInserting) {
      context.missing(_cipherMeta);
    }
    if (data.containsKey('kdf')) {
      context.handle(
        _kdfMeta,
        kdf.isAcceptableOrUnknown(data['kdf']!, _kdfMeta),
      );
    } else if (isInserting) {
      context.missing(_kdfMeta);
    }
    if (data.containsKey('params_json')) {
      context.handle(
        _paramsJsonMeta,
        paramsJson.isAcceptableOrUnknown(data['params_json']!, _paramsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_paramsJsonMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {version};
  @override
  EncryptionVersionEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EncryptionVersionEntry(
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      cipher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cipher'],
      )!,
      kdf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kdf'],
      )!,
      paramsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}params_json'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $EncryptionVersionsTable createAlias(String alias) {
    return $EncryptionVersionsTable(attachedDatabase, alias);
  }
}

class EncryptionVersionEntry extends DataClass
    implements Insertable<EncryptionVersionEntry> {
  final int version;
  final String cipher;
  final String kdf;
  final String paramsJson;
  final int active;
  const EncryptionVersionEntry({
    required this.version,
    required this.cipher,
    required this.kdf,
    required this.paramsJson,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['version'] = Variable<int>(version);
    map['cipher'] = Variable<String>(cipher);
    map['kdf'] = Variable<String>(kdf);
    map['params_json'] = Variable<String>(paramsJson);
    map['active'] = Variable<int>(active);
    return map;
  }

  EncryptionVersionsCompanion toCompanion(bool nullToAbsent) {
    return EncryptionVersionsCompanion(
      version: Value(version),
      cipher: Value(cipher),
      kdf: Value(kdf),
      paramsJson: Value(paramsJson),
      active: Value(active),
    );
  }

  factory EncryptionVersionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EncryptionVersionEntry(
      version: serializer.fromJson<int>(json['version']),
      cipher: serializer.fromJson<String>(json['cipher']),
      kdf: serializer.fromJson<String>(json['kdf']),
      paramsJson: serializer.fromJson<String>(json['paramsJson']),
      active: serializer.fromJson<int>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'version': serializer.toJson<int>(version),
      'cipher': serializer.toJson<String>(cipher),
      'kdf': serializer.toJson<String>(kdf),
      'paramsJson': serializer.toJson<String>(paramsJson),
      'active': serializer.toJson<int>(active),
    };
  }

  EncryptionVersionEntry copyWith({
    int? version,
    String? cipher,
    String? kdf,
    String? paramsJson,
    int? active,
  }) => EncryptionVersionEntry(
    version: version ?? this.version,
    cipher: cipher ?? this.cipher,
    kdf: kdf ?? this.kdf,
    paramsJson: paramsJson ?? this.paramsJson,
    active: active ?? this.active,
  );
  EncryptionVersionEntry copyWithCompanion(EncryptionVersionsCompanion data) {
    return EncryptionVersionEntry(
      version: data.version.present ? data.version.value : this.version,
      cipher: data.cipher.present ? data.cipher.value : this.cipher,
      kdf: data.kdf.present ? data.kdf.value : this.kdf,
      paramsJson: data.paramsJson.present
          ? data.paramsJson.value
          : this.paramsJson,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EncryptionVersionEntry(')
          ..write('version: $version, ')
          ..write('cipher: $cipher, ')
          ..write('kdf: $kdf, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(version, cipher, kdf, paramsJson, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EncryptionVersionEntry &&
          other.version == this.version &&
          other.cipher == this.cipher &&
          other.kdf == this.kdf &&
          other.paramsJson == this.paramsJson &&
          other.active == this.active);
}

class EncryptionVersionsCompanion
    extends UpdateCompanion<EncryptionVersionEntry> {
  final Value<int> version;
  final Value<String> cipher;
  final Value<String> kdf;
  final Value<String> paramsJson;
  final Value<int> active;
  const EncryptionVersionsCompanion({
    this.version = const Value.absent(),
    this.cipher = const Value.absent(),
    this.kdf = const Value.absent(),
    this.paramsJson = const Value.absent(),
    this.active = const Value.absent(),
  });
  EncryptionVersionsCompanion.insert({
    this.version = const Value.absent(),
    required String cipher,
    required String kdf,
    required String paramsJson,
    this.active = const Value.absent(),
  }) : cipher = Value(cipher),
       kdf = Value(kdf),
       paramsJson = Value(paramsJson);
  static Insertable<EncryptionVersionEntry> custom({
    Expression<int>? version,
    Expression<String>? cipher,
    Expression<String>? kdf,
    Expression<String>? paramsJson,
    Expression<int>? active,
  }) {
    return RawValuesInsertable({
      if (version != null) 'version': version,
      if (cipher != null) 'cipher': cipher,
      if (kdf != null) 'kdf': kdf,
      if (paramsJson != null) 'params_json': paramsJson,
      if (active != null) 'active': active,
    });
  }

  EncryptionVersionsCompanion copyWith({
    Value<int>? version,
    Value<String>? cipher,
    Value<String>? kdf,
    Value<String>? paramsJson,
    Value<int>? active,
  }) {
    return EncryptionVersionsCompanion(
      version: version ?? this.version,
      cipher: cipher ?? this.cipher,
      kdf: kdf ?? this.kdf,
      paramsJson: paramsJson ?? this.paramsJson,
      active: active ?? this.active,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (cipher.present) {
      map['cipher'] = Variable<String>(cipher.value);
    }
    if (kdf.present) {
      map['kdf'] = Variable<String>(kdf.value);
    }
    if (paramsJson.present) {
      map['params_json'] = Variable<String>(paramsJson.value);
    }
    if (active.present) {
      map['active'] = Variable<int>(active.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EncryptionVersionsCompanion(')
          ..write('version: $version, ')
          ..write('cipher: $cipher, ')
          ..write('kdf: $kdf, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }
}

class $ImportJobsTable extends ImportJobs
    with TableInfo<$ImportJobsTable, ImportJobEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalItemsMeta = const VerificationMeta(
    'totalItems',
  );
  @override
  late final GeneratedColumn<int> totalItems = GeneratedColumn<int>(
    'total_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedItemsMeta = const VerificationMeta(
    'completedItems',
  );
  @override
  late final GeneratedColumn<int> completedItems = GeneratedColumn<int>(
    'completed_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedItemsMeta = const VerificationMeta(
    'failedItems',
  );
  @override
  late final GeneratedColumn<int> failedItems = GeneratedColumn<int>(
    'failed_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    source,
    totalItems,
    completedItems,
    failedItems,
    status,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportJobEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('total_items')) {
      context.handle(
        _totalItemsMeta,
        totalItems.isAcceptableOrUnknown(data['total_items']!, _totalItemsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalItemsMeta);
    }
    if (data.containsKey('completed_items')) {
      context.handle(
        _completedItemsMeta,
        completedItems.isAcceptableOrUnknown(
          data['completed_items']!,
          _completedItemsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedItemsMeta);
    }
    if (data.containsKey('failed_items')) {
      context.handle(
        _failedItemsMeta,
        failedItems.isAcceptableOrUnknown(
          data['failed_items']!,
          _failedItemsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_failedItemsMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportJobEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportJobEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      totalItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_items'],
      )!,
      completedItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_items'],
      )!,
      failedItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_items'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ImportJobsTable createAlias(String alias) {
    return $ImportJobsTable(attachedDatabase, alias);
  }
}

class ImportJobEntry extends DataClass implements Insertable<ImportJobEntry> {
  final String id;
  final String source;
  final int totalItems;
  final int completedItems;
  final int failedItems;
  final String status;
  final int createdAtMs;
  final int updatedAtMs;
  const ImportJobEntry({
    required this.id,
    required this.source,
    required this.totalItems,
    required this.completedItems,
    required this.failedItems,
    required this.status,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source'] = Variable<String>(source);
    map['total_items'] = Variable<int>(totalItems);
    map['completed_items'] = Variable<int>(completedItems);
    map['failed_items'] = Variable<int>(failedItems);
    map['status'] = Variable<String>(status);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ImportJobsCompanion toCompanion(bool nullToAbsent) {
    return ImportJobsCompanion(
      id: Value(id),
      source: Value(source),
      totalItems: Value(totalItems),
      completedItems: Value(completedItems),
      failedItems: Value(failedItems),
      status: Value(status),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ImportJobEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportJobEntry(
      id: serializer.fromJson<String>(json['id']),
      source: serializer.fromJson<String>(json['source']),
      totalItems: serializer.fromJson<int>(json['totalItems']),
      completedItems: serializer.fromJson<int>(json['completedItems']),
      failedItems: serializer.fromJson<int>(json['failedItems']),
      status: serializer.fromJson<String>(json['status']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'source': serializer.toJson<String>(source),
      'totalItems': serializer.toJson<int>(totalItems),
      'completedItems': serializer.toJson<int>(completedItems),
      'failedItems': serializer.toJson<int>(failedItems),
      'status': serializer.toJson<String>(status),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ImportJobEntry copyWith({
    String? id,
    String? source,
    int? totalItems,
    int? completedItems,
    int? failedItems,
    String? status,
    int? createdAtMs,
    int? updatedAtMs,
  }) => ImportJobEntry(
    id: id ?? this.id,
    source: source ?? this.source,
    totalItems: totalItems ?? this.totalItems,
    completedItems: completedItems ?? this.completedItems,
    failedItems: failedItems ?? this.failedItems,
    status: status ?? this.status,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ImportJobEntry copyWithCompanion(ImportJobsCompanion data) {
    return ImportJobEntry(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      totalItems: data.totalItems.present
          ? data.totalItems.value
          : this.totalItems,
      completedItems: data.completedItems.present
          ? data.completedItems.value
          : this.completedItems,
      failedItems: data.failedItems.present
          ? data.failedItems.value
          : this.failedItems,
      status: data.status.present ? data.status.value : this.status,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportJobEntry(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('totalItems: $totalItems, ')
          ..write('completedItems: $completedItems, ')
          ..write('failedItems: $failedItems, ')
          ..write('status: $status, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    source,
    totalItems,
    completedItems,
    failedItems,
    status,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportJobEntry &&
          other.id == this.id &&
          other.source == this.source &&
          other.totalItems == this.totalItems &&
          other.completedItems == this.completedItems &&
          other.failedItems == this.failedItems &&
          other.status == this.status &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ImportJobsCompanion extends UpdateCompanion<ImportJobEntry> {
  final Value<String> id;
  final Value<String> source;
  final Value<int> totalItems;
  final Value<int> completedItems;
  final Value<int> failedItems;
  final Value<String> status;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ImportJobsCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.totalItems = const Value.absent(),
    this.completedItems = const Value.absent(),
    this.failedItems = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportJobsCompanion.insert({
    required String id,
    required String source,
    required int totalItems,
    required int completedItems,
    required int failedItems,
    required String status,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       source = Value(source),
       totalItems = Value(totalItems),
       completedItems = Value(completedItems),
       failedItems = Value(failedItems),
       status = Value(status),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ImportJobEntry> custom({
    Expression<String>? id,
    Expression<String>? source,
    Expression<int>? totalItems,
    Expression<int>? completedItems,
    Expression<int>? failedItems,
    Expression<String>? status,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (totalItems != null) 'total_items': totalItems,
      if (completedItems != null) 'completed_items': completedItems,
      if (failedItems != null) 'failed_items': failedItems,
      if (status != null) 'status': status,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? source,
    Value<int>? totalItems,
    Value<int>? completedItems,
    Value<int>? failedItems,
    Value<String>? status,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ImportJobsCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      failedItems: failedItems ?? this.failedItems,
      status: status ?? this.status,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (totalItems.present) {
      map['total_items'] = Variable<int>(totalItems.value);
    }
    if (completedItems.present) {
      map['completed_items'] = Variable<int>(completedItems.value);
    }
    if (failedItems.present) {
      map['failed_items'] = Variable<int>(failedItems.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportJobsCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('totalItems: $totalItems, ')
          ..write('completedItems: $completedItems, ')
          ..write('failedItems: $failedItems, ')
          ..write('status: $status, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShareExportsTable extends ShareExports
    with TableInfo<$ShareExportsTable, ShareExportEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShareExportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exportModeMeta = const VerificationMeta(
    'exportMode',
  );
  @override
  late final GeneratedColumn<String> exportMode = GeneratedColumn<String>(
    'export_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packagePathMeta = const VerificationMeta(
    'packagePath',
  );
  @override
  late final GeneratedColumn<String> packagePath = GeneratedColumn<String>(
    'package_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMsMeta = const VerificationMeta(
    'expiresAtMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    photoId,
    exportMode,
    packagePath,
    expiresAtMs,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'share_exports';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShareExportEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    }
    if (data.containsKey('export_mode')) {
      context.handle(
        _exportModeMeta,
        exportMode.isAcceptableOrUnknown(data['export_mode']!, _exportModeMeta),
      );
    } else if (isInserting) {
      context.missing(_exportModeMeta);
    }
    if (data.containsKey('package_path')) {
      context.handle(
        _packagePathMeta,
        packagePath.isAcceptableOrUnknown(
          data['package_path']!,
          _packagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packagePathMeta);
    }
    if (data.containsKey('expires_at_ms')) {
      context.handle(
        _expiresAtMsMeta,
        expiresAtMs.isAcceptableOrUnknown(
          data['expires_at_ms']!,
          _expiresAtMsMeta,
        ),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShareExportEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShareExportEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      ),
      exportMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}export_mode'],
      )!,
      packagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_path'],
      )!,
      expiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_ms'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $ShareExportsTable createAlias(String alias) {
    return $ShareExportsTable(attachedDatabase, alias);
  }
}

class ShareExportEntry extends DataClass
    implements Insertable<ShareExportEntry> {
  final String id;
  final String? photoId;
  final String exportMode;
  final String packagePath;
  final int? expiresAtMs;
  final int createdAtMs;
  const ShareExportEntry({
    required this.id,
    this.photoId,
    required this.exportMode,
    required this.packagePath,
    this.expiresAtMs,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || photoId != null) {
      map['photo_id'] = Variable<String>(photoId);
    }
    map['export_mode'] = Variable<String>(exportMode);
    map['package_path'] = Variable<String>(packagePath);
    if (!nullToAbsent || expiresAtMs != null) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  ShareExportsCompanion toCompanion(bool nullToAbsent) {
    return ShareExportsCompanion(
      id: Value(id),
      photoId: photoId == null && nullToAbsent
          ? const Value.absent()
          : Value(photoId),
      exportMode: Value(exportMode),
      packagePath: Value(packagePath),
      expiresAtMs: expiresAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAtMs),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory ShareExportEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShareExportEntry(
      id: serializer.fromJson<String>(json['id']),
      photoId: serializer.fromJson<String?>(json['photoId']),
      exportMode: serializer.fromJson<String>(json['exportMode']),
      packagePath: serializer.fromJson<String>(json['packagePath']),
      expiresAtMs: serializer.fromJson<int?>(json['expiresAtMs']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'photoId': serializer.toJson<String?>(photoId),
      'exportMode': serializer.toJson<String>(exportMode),
      'packagePath': serializer.toJson<String>(packagePath),
      'expiresAtMs': serializer.toJson<int?>(expiresAtMs),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  ShareExportEntry copyWith({
    String? id,
    Value<String?> photoId = const Value.absent(),
    String? exportMode,
    String? packagePath,
    Value<int?> expiresAtMs = const Value.absent(),
    int? createdAtMs,
  }) => ShareExportEntry(
    id: id ?? this.id,
    photoId: photoId.present ? photoId.value : this.photoId,
    exportMode: exportMode ?? this.exportMode,
    packagePath: packagePath ?? this.packagePath,
    expiresAtMs: expiresAtMs.present ? expiresAtMs.value : this.expiresAtMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  ShareExportEntry copyWithCompanion(ShareExportsCompanion data) {
    return ShareExportEntry(
      id: data.id.present ? data.id.value : this.id,
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      exportMode: data.exportMode.present
          ? data.exportMode.value
          : this.exportMode,
      packagePath: data.packagePath.present
          ? data.packagePath.value
          : this.packagePath,
      expiresAtMs: data.expiresAtMs.present
          ? data.expiresAtMs.value
          : this.expiresAtMs,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareExportEntry(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('exportMode: $exportMode, ')
          ..write('packagePath: $packagePath, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    photoId,
    exportMode,
    packagePath,
    expiresAtMs,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShareExportEntry &&
          other.id == this.id &&
          other.photoId == this.photoId &&
          other.exportMode == this.exportMode &&
          other.packagePath == this.packagePath &&
          other.expiresAtMs == this.expiresAtMs &&
          other.createdAtMs == this.createdAtMs);
}

class ShareExportsCompanion extends UpdateCompanion<ShareExportEntry> {
  final Value<String> id;
  final Value<String?> photoId;
  final Value<String> exportMode;
  final Value<String> packagePath;
  final Value<int?> expiresAtMs;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const ShareExportsCompanion({
    this.id = const Value.absent(),
    this.photoId = const Value.absent(),
    this.exportMode = const Value.absent(),
    this.packagePath = const Value.absent(),
    this.expiresAtMs = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShareExportsCompanion.insert({
    required String id,
    this.photoId = const Value.absent(),
    required String exportMode,
    required String packagePath,
    this.expiresAtMs = const Value.absent(),
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       exportMode = Value(exportMode),
       packagePath = Value(packagePath),
       createdAtMs = Value(createdAtMs);
  static Insertable<ShareExportEntry> custom({
    Expression<String>? id,
    Expression<String>? photoId,
    Expression<String>? exportMode,
    Expression<String>? packagePath,
    Expression<int>? expiresAtMs,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (photoId != null) 'photo_id': photoId,
      if (exportMode != null) 'export_mode': exportMode,
      if (packagePath != null) 'package_path': packagePath,
      if (expiresAtMs != null) 'expires_at_ms': expiresAtMs,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShareExportsCompanion copyWith({
    Value<String>? id,
    Value<String?>? photoId,
    Value<String>? exportMode,
    Value<String>? packagePath,
    Value<int?>? expiresAtMs,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return ShareExportsCompanion(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      exportMode: exportMode ?? this.exportMode,
      packagePath: packagePath ?? this.packagePath,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (exportMode.present) {
      map['export_mode'] = Variable<String>(exportMode.value);
    }
    if (packagePath.present) {
      map['package_path'] = Variable<String>(packagePath.value);
    }
    if (expiresAtMs.present) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShareExportsCompanion(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('exportMode: $exportMode, ')
          ..write('packagePath: $packagePath, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrashItemsTable extends TrashItems
    with TableInfo<$TrashItemsTable, TrashItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrashItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _movedAtMsMeta = const VerificationMeta(
    'movedAtMs',
  );
  @override
  late final GeneratedColumn<int> movedAtMs = GeneratedColumn<int>(
    'moved_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMsMeta = const VerificationMeta(
    'expiresAtMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncDeletePendingMeta = const VerificationMeta(
    'syncDeletePending',
  );
  @override
  late final GeneratedColumn<int> syncDeletePending = GeneratedColumn<int>(
    'sync_delete_pending',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    photoId,
    movedAtMs,
    expiresAtMs,
    syncDeletePending,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trash_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrashItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_photoIdMeta);
    }
    if (data.containsKey('moved_at_ms')) {
      context.handle(
        _movedAtMsMeta,
        movedAtMs.isAcceptableOrUnknown(data['moved_at_ms']!, _movedAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_movedAtMsMeta);
    }
    if (data.containsKey('expires_at_ms')) {
      context.handle(
        _expiresAtMsMeta,
        expiresAtMs.isAcceptableOrUnknown(
          data['expires_at_ms']!,
          _expiresAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMsMeta);
    }
    if (data.containsKey('sync_delete_pending')) {
      context.handle(
        _syncDeletePendingMeta,
        syncDeletePending.isAcceptableOrUnknown(
          data['sync_delete_pending']!,
          _syncDeletePendingMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {photoId};
  @override
  TrashItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrashItem(
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      )!,
      movedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}moved_at_ms'],
      )!,
      expiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_ms'],
      )!,
      syncDeletePending: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_delete_pending'],
      )!,
    );
  }

  @override
  $TrashItemsTable createAlias(String alias) {
    return $TrashItemsTable(attachedDatabase, alias);
  }
}

class TrashItem extends DataClass implements Insertable<TrashItem> {
  final String photoId;
  final int movedAtMs;
  final int expiresAtMs;
  final int syncDeletePending;
  const TrashItem({
    required this.photoId,
    required this.movedAtMs,
    required this.expiresAtMs,
    required this.syncDeletePending,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['photo_id'] = Variable<String>(photoId);
    map['moved_at_ms'] = Variable<int>(movedAtMs);
    map['expires_at_ms'] = Variable<int>(expiresAtMs);
    map['sync_delete_pending'] = Variable<int>(syncDeletePending);
    return map;
  }

  TrashItemsCompanion toCompanion(bool nullToAbsent) {
    return TrashItemsCompanion(
      photoId: Value(photoId),
      movedAtMs: Value(movedAtMs),
      expiresAtMs: Value(expiresAtMs),
      syncDeletePending: Value(syncDeletePending),
    );
  }

  factory TrashItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrashItem(
      photoId: serializer.fromJson<String>(json['photoId']),
      movedAtMs: serializer.fromJson<int>(json['movedAtMs']),
      expiresAtMs: serializer.fromJson<int>(json['expiresAtMs']),
      syncDeletePending: serializer.fromJson<int>(json['syncDeletePending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'photoId': serializer.toJson<String>(photoId),
      'movedAtMs': serializer.toJson<int>(movedAtMs),
      'expiresAtMs': serializer.toJson<int>(expiresAtMs),
      'syncDeletePending': serializer.toJson<int>(syncDeletePending),
    };
  }

  TrashItem copyWith({
    String? photoId,
    int? movedAtMs,
    int? expiresAtMs,
    int? syncDeletePending,
  }) => TrashItem(
    photoId: photoId ?? this.photoId,
    movedAtMs: movedAtMs ?? this.movedAtMs,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    syncDeletePending: syncDeletePending ?? this.syncDeletePending,
  );
  TrashItem copyWithCompanion(TrashItemsCompanion data) {
    return TrashItem(
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      movedAtMs: data.movedAtMs.present ? data.movedAtMs.value : this.movedAtMs,
      expiresAtMs: data.expiresAtMs.present
          ? data.expiresAtMs.value
          : this.expiresAtMs,
      syncDeletePending: data.syncDeletePending.present
          ? data.syncDeletePending.value
          : this.syncDeletePending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrashItem(')
          ..write('photoId: $photoId, ')
          ..write('movedAtMs: $movedAtMs, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('syncDeletePending: $syncDeletePending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(photoId, movedAtMs, expiresAtMs, syncDeletePending);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrashItem &&
          other.photoId == this.photoId &&
          other.movedAtMs == this.movedAtMs &&
          other.expiresAtMs == this.expiresAtMs &&
          other.syncDeletePending == this.syncDeletePending);
}

class TrashItemsCompanion extends UpdateCompanion<TrashItem> {
  final Value<String> photoId;
  final Value<int> movedAtMs;
  final Value<int> expiresAtMs;
  final Value<int> syncDeletePending;
  final Value<int> rowid;
  const TrashItemsCompanion({
    this.photoId = const Value.absent(),
    this.movedAtMs = const Value.absent(),
    this.expiresAtMs = const Value.absent(),
    this.syncDeletePending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrashItemsCompanion.insert({
    required String photoId,
    required int movedAtMs,
    required int expiresAtMs,
    this.syncDeletePending = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : photoId = Value(photoId),
       movedAtMs = Value(movedAtMs),
       expiresAtMs = Value(expiresAtMs);
  static Insertable<TrashItem> custom({
    Expression<String>? photoId,
    Expression<int>? movedAtMs,
    Expression<int>? expiresAtMs,
    Expression<int>? syncDeletePending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (photoId != null) 'photo_id': photoId,
      if (movedAtMs != null) 'moved_at_ms': movedAtMs,
      if (expiresAtMs != null) 'expires_at_ms': expiresAtMs,
      if (syncDeletePending != null) 'sync_delete_pending': syncDeletePending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrashItemsCompanion copyWith({
    Value<String>? photoId,
    Value<int>? movedAtMs,
    Value<int>? expiresAtMs,
    Value<int>? syncDeletePending,
    Value<int>? rowid,
  }) {
    return TrashItemsCompanion(
      photoId: photoId ?? this.photoId,
      movedAtMs: movedAtMs ?? this.movedAtMs,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      syncDeletePending: syncDeletePending ?? this.syncDeletePending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (movedAtMs.present) {
      map['moved_at_ms'] = Variable<int>(movedAtMs.value);
    }
    if (expiresAtMs.present) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs.value);
    }
    if (syncDeletePending.present) {
      map['sync_delete_pending'] = Variable<int>(syncDeletePending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrashItemsCompanion(')
          ..write('photoId: $photoId, ')
          ..write('movedAtMs: $movedAtMs, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('syncDeletePending: $syncDeletePending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingEntry extends DataClass implements Insertable<AppSettingEntry> {
  final String key;
  final String value;
  final int updatedAtMs;
  const AppSettingEntry({
    required this.key,
    required this.value,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AppSettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AppSettingEntry copyWith({String? key, String? value, int? updatedAtMs}) =>
      AppSettingEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
  AppSettingEntry copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtMs == this.updatedAtMs);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<AppSettingEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SecurityEventsTable extends SecurityEvents
    with TableInfo<$SecurityEventsTable, SecurityEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecurityEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMsMeta = const VerificationMeta(
    'occurredAtMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtMs = GeneratedColumn<int>(
    'occurred_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventType,
    severity,
    occurredAtMs,
    detailsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'security_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SecurityEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    } else if (isInserting) {
      context.missing(_severityMeta);
    }
    if (data.containsKey('occurred_at_ms')) {
      context.handle(
        _occurredAtMsMeta,
        occurredAtMs.isAcceptableOrUnknown(
          data['occurred_at_ms']!,
          _occurredAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMsMeta);
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SecurityEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecurityEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      occurredAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_ms'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      ),
    );
  }

  @override
  $SecurityEventsTable createAlias(String alias) {
    return $SecurityEventsTable(attachedDatabase, alias);
  }
}

class SecurityEvent extends DataClass implements Insertable<SecurityEvent> {
  final String id;
  final String eventType;
  final String severity;
  final int occurredAtMs;
  final String? detailsJson;
  const SecurityEvent({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.occurredAtMs,
    this.detailsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['event_type'] = Variable<String>(eventType);
    map['severity'] = Variable<String>(severity);
    map['occurred_at_ms'] = Variable<int>(occurredAtMs);
    if (!nullToAbsent || detailsJson != null) {
      map['details_json'] = Variable<String>(detailsJson);
    }
    return map;
  }

  SecurityEventsCompanion toCompanion(bool nullToAbsent) {
    return SecurityEventsCompanion(
      id: Value(id),
      eventType: Value(eventType),
      severity: Value(severity),
      occurredAtMs: Value(occurredAtMs),
      detailsJson: detailsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(detailsJson),
    );
  }

  factory SecurityEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecurityEvent(
      id: serializer.fromJson<String>(json['id']),
      eventType: serializer.fromJson<String>(json['eventType']),
      severity: serializer.fromJson<String>(json['severity']),
      occurredAtMs: serializer.fromJson<int>(json['occurredAtMs']),
      detailsJson: serializer.fromJson<String?>(json['detailsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'eventType': serializer.toJson<String>(eventType),
      'severity': serializer.toJson<String>(severity),
      'occurredAtMs': serializer.toJson<int>(occurredAtMs),
      'detailsJson': serializer.toJson<String?>(detailsJson),
    };
  }

  SecurityEvent copyWith({
    String? id,
    String? eventType,
    String? severity,
    int? occurredAtMs,
    Value<String?> detailsJson = const Value.absent(),
  }) => SecurityEvent(
    id: id ?? this.id,
    eventType: eventType ?? this.eventType,
    severity: severity ?? this.severity,
    occurredAtMs: occurredAtMs ?? this.occurredAtMs,
    detailsJson: detailsJson.present ? detailsJson.value : this.detailsJson,
  );
  SecurityEvent copyWithCompanion(SecurityEventsCompanion data) {
    return SecurityEvent(
      id: data.id.present ? data.id.value : this.id,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      severity: data.severity.present ? data.severity.value : this.severity,
      occurredAtMs: data.occurredAtMs.present
          ? data.occurredAtMs.value
          : this.occurredAtMs,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecurityEvent(')
          ..write('id: $id, ')
          ..write('eventType: $eventType, ')
          ..write('severity: $severity, ')
          ..write('occurredAtMs: $occurredAtMs, ')
          ..write('detailsJson: $detailsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, eventType, severity, occurredAtMs, detailsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecurityEvent &&
          other.id == this.id &&
          other.eventType == this.eventType &&
          other.severity == this.severity &&
          other.occurredAtMs == this.occurredAtMs &&
          other.detailsJson == this.detailsJson);
}

class SecurityEventsCompanion extends UpdateCompanion<SecurityEvent> {
  final Value<String> id;
  final Value<String> eventType;
  final Value<String> severity;
  final Value<int> occurredAtMs;
  final Value<String?> detailsJson;
  final Value<int> rowid;
  const SecurityEventsCompanion({
    this.id = const Value.absent(),
    this.eventType = const Value.absent(),
    this.severity = const Value.absent(),
    this.occurredAtMs = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SecurityEventsCompanion.insert({
    required String id,
    required String eventType,
    required String severity,
    required int occurredAtMs,
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       eventType = Value(eventType),
       severity = Value(severity),
       occurredAtMs = Value(occurredAtMs);
  static Insertable<SecurityEvent> custom({
    Expression<String>? id,
    Expression<String>? eventType,
    Expression<String>? severity,
    Expression<int>? occurredAtMs,
    Expression<String>? detailsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventType != null) 'event_type': eventType,
      if (severity != null) 'severity': severity,
      if (occurredAtMs != null) 'occurred_at_ms': occurredAtMs,
      if (detailsJson != null) 'details_json': detailsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SecurityEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? eventType,
    Value<String>? severity,
    Value<int>? occurredAtMs,
    Value<String?>? detailsJson,
    Value<int>? rowid,
  }) {
    return SecurityEventsCompanion(
      id: id ?? this.id,
      eventType: eventType ?? this.eventType,
      severity: severity ?? this.severity,
      occurredAtMs: occurredAtMs ?? this.occurredAtMs,
      detailsJson: detailsJson ?? this.detailsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (occurredAtMs.present) {
      map['occurred_at_ms'] = Variable<int>(occurredAtMs.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecurityEventsCompanion(')
          ..write('id: $id, ')
          ..write('eventType: $eventType, ')
          ..write('severity: $severity, ')
          ..write('occurredAtMs: $occurredAtMs, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$VaultDatabase extends GeneratedDatabase {
  _$VaultDatabase(QueryExecutor e) : super(e);
  $VaultDatabaseManager get managers => $VaultDatabaseManager(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $PhotoTagsTable photoTags = $PhotoTagsTable(this);
  late final $VaultTable vault = $VaultTable(this);
  late final $ThumbnailsTable thumbnails = $ThumbnailsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $BackupStateTable backupState = $BackupStateTable(this);
  late final $EncryptionVersionsTable encryptionVersions =
      $EncryptionVersionsTable(this);
  late final $ImportJobsTable importJobs = $ImportJobsTable(this);
  late final $ShareExportsTable shareExports = $ShareExportsTable(this);
  late final $TrashItemsTable trashItems = $TrashItemsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SecurityEventsTable securityEvents = $SecurityEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    photos,
    albums,
    tags,
    photoTags,
    vault,
    thumbnails,
    syncState,
    backupState,
    encryptionVersions,
    importJobs,
    shareExports,
    trashItems,
    appSettings,
    securityEvents,
  ];
}

typedef $$PhotosTableCreateCompanionBuilder =
    PhotosCompanion Function({
      required String id,
      required String originalFilename,
      required int createdTimeMs,
      required int importedTimeMs,
      required int modifiedTimeMs,
      required String source,
      Value<String?> albumId,
      Value<int> favorite,
      required String encryptedFilePath,
      required String thumbnailPath,
      required String thumbnailNonce,
      required String photoNonce,
      required String wrappedDek,
      required int encryptionVersion,
      required String syncStatus,
      required String backupStatus,
      required String checksumSha256,
      required int fileSize,
      required String mimeType,
      Value<int> isTrashed,
      Value<int?> trashExpiresAtMs,
      Value<int?> deletedTombstoneAtMs,
      Value<int> rowid,
    });
typedef $$PhotosTableUpdateCompanionBuilder =
    PhotosCompanion Function({
      Value<String> id,
      Value<String> originalFilename,
      Value<int> createdTimeMs,
      Value<int> importedTimeMs,
      Value<int> modifiedTimeMs,
      Value<String> source,
      Value<String?> albumId,
      Value<int> favorite,
      Value<String> encryptedFilePath,
      Value<String> thumbnailPath,
      Value<String> thumbnailNonce,
      Value<String> photoNonce,
      Value<String> wrappedDek,
      Value<int> encryptionVersion,
      Value<String> syncStatus,
      Value<String> backupStatus,
      Value<String> checksumSha256,
      Value<int> fileSize,
      Value<String> mimeType,
      Value<int> isTrashed,
      Value<int?> trashExpiresAtMs,
      Value<int?> deletedTombstoneAtMs,
      Value<int> rowid,
    });

class $$PhotosTableFilterComposer
    extends Composer<_$VaultDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdTimeMs => $composableBuilder(
    column: $table.createdTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedTimeMs => $composableBuilder(
    column: $table.importedTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedTimeMs => $composableBuilder(
    column: $table.modifiedTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedFilePath => $composableBuilder(
    column: $table.encryptedFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailNonce => $composableBuilder(
    column: $table.thumbnailNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoNonce => $composableBuilder(
    column: $table.photoNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wrappedDek => $composableBuilder(
    column: $table.wrappedDek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupStatus => $composableBuilder(
    column: $table.backupStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isTrashed => $composableBuilder(
    column: $table.isTrashed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trashExpiresAtMs => $composableBuilder(
    column: $table.trashExpiresAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedTombstoneAtMs => $composableBuilder(
    column: $table.deletedTombstoneAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PhotosTableOrderingComposer
    extends Composer<_$VaultDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdTimeMs => $composableBuilder(
    column: $table.createdTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedTimeMs => $composableBuilder(
    column: $table.importedTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedTimeMs => $composableBuilder(
    column: $table.modifiedTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedFilePath => $composableBuilder(
    column: $table.encryptedFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailNonce => $composableBuilder(
    column: $table.thumbnailNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoNonce => $composableBuilder(
    column: $table.photoNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wrappedDek => $composableBuilder(
    column: $table.wrappedDek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupStatus => $composableBuilder(
    column: $table.backupStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isTrashed => $composableBuilder(
    column: $table.isTrashed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trashExpiresAtMs => $composableBuilder(
    column: $table.trashExpiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedTombstoneAtMs => $composableBuilder(
    column: $table.deletedTombstoneAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$VaultDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdTimeMs => $composableBuilder(
    column: $table.createdTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedTimeMs => $composableBuilder(
    column: $table.importedTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get modifiedTimeMs => $composableBuilder(
    column: $table.modifiedTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<int> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<String> get encryptedFilePath => $composableBuilder(
    column: $table.encryptedFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailNonce => $composableBuilder(
    column: $table.thumbnailNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoNonce => $composableBuilder(
    column: $table.photoNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wrappedDek => $composableBuilder(
    column: $table.wrappedDek,
    builder: (column) => column,
  );

  GeneratedColumn<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backupStatus => $composableBuilder(
    column: $table.backupStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get isTrashed =>
      $composableBuilder(column: $table.isTrashed, builder: (column) => column);

  GeneratedColumn<int> get trashExpiresAtMs => $composableBuilder(
    column: $table.trashExpiresAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedTombstoneAtMs => $composableBuilder(
    column: $table.deletedTombstoneAtMs,
    builder: (column) => column,
  );
}

class $$PhotosTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $PhotosTable,
          VaultPhoto,
          $$PhotosTableFilterComposer,
          $$PhotosTableOrderingComposer,
          $$PhotosTableAnnotationComposer,
          $$PhotosTableCreateCompanionBuilder,
          $$PhotosTableUpdateCompanionBuilder,
          (
            VaultPhoto,
            BaseReferences<_$VaultDatabase, $PhotosTable, VaultPhoto>,
          ),
          VaultPhoto,
          PrefetchHooks Function()
        > {
  $$PhotosTableTableManager(_$VaultDatabase db, $PhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> originalFilename = const Value.absent(),
                Value<int> createdTimeMs = const Value.absent(),
                Value<int> importedTimeMs = const Value.absent(),
                Value<int> modifiedTimeMs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<int> favorite = const Value.absent(),
                Value<String> encryptedFilePath = const Value.absent(),
                Value<String> thumbnailPath = const Value.absent(),
                Value<String> thumbnailNonce = const Value.absent(),
                Value<String> photoNonce = const Value.absent(),
                Value<String> wrappedDek = const Value.absent(),
                Value<int> encryptionVersion = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> backupStatus = const Value.absent(),
                Value<String> checksumSha256 = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> isTrashed = const Value.absent(),
                Value<int?> trashExpiresAtMs = const Value.absent(),
                Value<int?> deletedTombstoneAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion(
                id: id,
                originalFilename: originalFilename,
                createdTimeMs: createdTimeMs,
                importedTimeMs: importedTimeMs,
                modifiedTimeMs: modifiedTimeMs,
                source: source,
                albumId: albumId,
                favorite: favorite,
                encryptedFilePath: encryptedFilePath,
                thumbnailPath: thumbnailPath,
                thumbnailNonce: thumbnailNonce,
                photoNonce: photoNonce,
                wrappedDek: wrappedDek,
                encryptionVersion: encryptionVersion,
                syncStatus: syncStatus,
                backupStatus: backupStatus,
                checksumSha256: checksumSha256,
                fileSize: fileSize,
                mimeType: mimeType,
                isTrashed: isTrashed,
                trashExpiresAtMs: trashExpiresAtMs,
                deletedTombstoneAtMs: deletedTombstoneAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String originalFilename,
                required int createdTimeMs,
                required int importedTimeMs,
                required int modifiedTimeMs,
                required String source,
                Value<String?> albumId = const Value.absent(),
                Value<int> favorite = const Value.absent(),
                required String encryptedFilePath,
                required String thumbnailPath,
                required String thumbnailNonce,
                required String photoNonce,
                required String wrappedDek,
                required int encryptionVersion,
                required String syncStatus,
                required String backupStatus,
                required String checksumSha256,
                required int fileSize,
                required String mimeType,
                Value<int> isTrashed = const Value.absent(),
                Value<int?> trashExpiresAtMs = const Value.absent(),
                Value<int?> deletedTombstoneAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion.insert(
                id: id,
                originalFilename: originalFilename,
                createdTimeMs: createdTimeMs,
                importedTimeMs: importedTimeMs,
                modifiedTimeMs: modifiedTimeMs,
                source: source,
                albumId: albumId,
                favorite: favorite,
                encryptedFilePath: encryptedFilePath,
                thumbnailPath: thumbnailPath,
                thumbnailNonce: thumbnailNonce,
                photoNonce: photoNonce,
                wrappedDek: wrappedDek,
                encryptionVersion: encryptionVersion,
                syncStatus: syncStatus,
                backupStatus: backupStatus,
                checksumSha256: checksumSha256,
                fileSize: fileSize,
                mimeType: mimeType,
                isTrashed: isTrashed,
                trashExpiresAtMs: trashExpiresAtMs,
                deletedTombstoneAtMs: deletedTombstoneAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $PhotosTable,
      VaultPhoto,
      $$PhotosTableFilterComposer,
      $$PhotosTableOrderingComposer,
      $$PhotosTableAnnotationComposer,
      $$PhotosTableCreateCompanionBuilder,
      $$PhotosTableUpdateCompanionBuilder,
      (VaultPhoto, BaseReferences<_$VaultDatabase, $PhotosTable, VaultPhoto>),
      VaultPhoto,
      PrefetchHooks Function()
    >;
typedef $$AlbumsTableCreateCompanionBuilder =
    AlbumsCompanion Function({
      required String id,
      required String name,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$AlbumsTableUpdateCompanionBuilder =
    AlbumsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$AlbumsTableFilterComposer
    extends Composer<_$VaultDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$VaultDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AlbumsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $AlbumsTable,
          VaultAlbum,
          $$AlbumsTableFilterComposer,
          $$AlbumsTableOrderingComposer,
          $$AlbumsTableAnnotationComposer,
          $$AlbumsTableCreateCompanionBuilder,
          $$AlbumsTableUpdateCompanionBuilder,
          (
            VaultAlbum,
            BaseReferences<_$VaultDatabase, $AlbumsTable, VaultAlbum>,
          ),
          VaultAlbum,
          PrefetchHooks Function()
        > {
  $$AlbumsTableTableManager(_$VaultDatabase db, $AlbumsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion(
                id: id,
                name: name,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAtMs,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion.insert(
                id: id,
                name: name,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlbumsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $AlbumsTable,
      VaultAlbum,
      $$AlbumsTableFilterComposer,
      $$AlbumsTableOrderingComposer,
      $$AlbumsTableAnnotationComposer,
      $$AlbumsTableCreateCompanionBuilder,
      $$AlbumsTableUpdateCompanionBuilder,
      (VaultAlbum, BaseReferences<_$VaultDatabase, $AlbumsTable, VaultAlbum>),
      VaultAlbum,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

class $$TagsTableFilterComposer extends Composer<_$VaultDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer
    extends Composer<_$VaultDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $TagsTable,
          VaultTag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (VaultTag, BaseReferences<_$VaultDatabase, $TagsTable, VaultTag>),
          VaultTag,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$VaultDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $TagsTable,
      VaultTag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (VaultTag, BaseReferences<_$VaultDatabase, $TagsTable, VaultTag>),
      VaultTag,
      PrefetchHooks Function()
    >;
typedef $$PhotoTagsTableCreateCompanionBuilder =
    PhotoTagsCompanion Function({
      required String photoId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$PhotoTagsTableUpdateCompanionBuilder =
    PhotoTagsCompanion Function({
      Value<String> photoId,
      Value<String> tagId,
      Value<int> rowid,
    });

class $$PhotoTagsTableFilterComposer
    extends Composer<_$VaultDatabase, $PhotoTagsTable> {
  $$PhotoTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PhotoTagsTableOrderingComposer
    extends Composer<_$VaultDatabase, $PhotoTagsTable> {
  $$PhotoTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhotoTagsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $PhotoTagsTable> {
  $$PhotoTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);
}

class $$PhotoTagsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $PhotoTagsTable,
          PhotoTagLink,
          $$PhotoTagsTableFilterComposer,
          $$PhotoTagsTableOrderingComposer,
          $$PhotoTagsTableAnnotationComposer,
          $$PhotoTagsTableCreateCompanionBuilder,
          $$PhotoTagsTableUpdateCompanionBuilder,
          (
            PhotoTagLink,
            BaseReferences<_$VaultDatabase, $PhotoTagsTable, PhotoTagLink>,
          ),
          PhotoTagLink,
          PrefetchHooks Function()
        > {
  $$PhotoTagsTableTableManager(_$VaultDatabase db, $PhotoTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotoTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotoTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotoTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> photoId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotoTagsCompanion(
                photoId: photoId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String photoId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => PhotoTagsCompanion.insert(
                photoId: photoId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PhotoTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $PhotoTagsTable,
      PhotoTagLink,
      $$PhotoTagsTableFilterComposer,
      $$PhotoTagsTableOrderingComposer,
      $$PhotoTagsTableAnnotationComposer,
      $$PhotoTagsTableCreateCompanionBuilder,
      $$PhotoTagsTableUpdateCompanionBuilder,
      (
        PhotoTagLink,
        BaseReferences<_$VaultDatabase, $PhotoTagsTable, PhotoTagLink>,
      ),
      PhotoTagLink,
      PrefetchHooks Function()
    >;
typedef $$VaultTableCreateCompanionBuilder =
    VaultCompanion Function({
      required String id,
      required String mode,
      required int createdAtMs,
      required int vmkWrapVersion,
      required int activeEncryptionVersion,
      Value<int> rowid,
    });
typedef $$VaultTableUpdateCompanionBuilder =
    VaultCompanion Function({
      Value<String> id,
      Value<String> mode,
      Value<int> createdAtMs,
      Value<int> vmkWrapVersion,
      Value<int> activeEncryptionVersion,
      Value<int> rowid,
    });

class $$VaultTableFilterComposer
    extends Composer<_$VaultDatabase, $VaultTable> {
  $$VaultTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vmkWrapVersion => $composableBuilder(
    column: $table.vmkWrapVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeEncryptionVersion => $composableBuilder(
    column: $table.activeEncryptionVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VaultTableOrderingComposer
    extends Composer<_$VaultDatabase, $VaultTable> {
  $$VaultTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vmkWrapVersion => $composableBuilder(
    column: $table.vmkWrapVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeEncryptionVersion => $composableBuilder(
    column: $table.activeEncryptionVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VaultTableAnnotationComposer
    extends Composer<_$VaultDatabase, $VaultTable> {
  $$VaultTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vmkWrapVersion => $composableBuilder(
    column: $table.vmkWrapVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeEncryptionVersion => $composableBuilder(
    column: $table.activeEncryptionVersion,
    builder: (column) => column,
  );
}

class $$VaultTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $VaultTable,
          VaultMetadata,
          $$VaultTableFilterComposer,
          $$VaultTableOrderingComposer,
          $$VaultTableAnnotationComposer,
          $$VaultTableCreateCompanionBuilder,
          $$VaultTableUpdateCompanionBuilder,
          (
            VaultMetadata,
            BaseReferences<_$VaultDatabase, $VaultTable, VaultMetadata>,
          ),
          VaultMetadata,
          PrefetchHooks Function()
        > {
  $$VaultTableTableManager(_$VaultDatabase db, $VaultTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> vmkWrapVersion = const Value.absent(),
                Value<int> activeEncryptionVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VaultCompanion(
                id: id,
                mode: mode,
                createdAtMs: createdAtMs,
                vmkWrapVersion: vmkWrapVersion,
                activeEncryptionVersion: activeEncryptionVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mode,
                required int createdAtMs,
                required int vmkWrapVersion,
                required int activeEncryptionVersion,
                Value<int> rowid = const Value.absent(),
              }) => VaultCompanion.insert(
                id: id,
                mode: mode,
                createdAtMs: createdAtMs,
                vmkWrapVersion: vmkWrapVersion,
                activeEncryptionVersion: activeEncryptionVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VaultTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $VaultTable,
      VaultMetadata,
      $$VaultTableFilterComposer,
      $$VaultTableOrderingComposer,
      $$VaultTableAnnotationComposer,
      $$VaultTableCreateCompanionBuilder,
      $$VaultTableUpdateCompanionBuilder,
      (
        VaultMetadata,
        BaseReferences<_$VaultDatabase, $VaultTable, VaultMetadata>,
      ),
      VaultMetadata,
      PrefetchHooks Function()
    >;
typedef $$ThumbnailsTableCreateCompanionBuilder =
    ThumbnailsCompanion Function({
      required String id,
      required String photoId,
      required String encryptedPath,
      required String nonce,
      required int encryptionVersion,
      required int width,
      required int height,
      required String checksumSha256,
      Value<int> rowid,
    });
typedef $$ThumbnailsTableUpdateCompanionBuilder =
    ThumbnailsCompanion Function({
      Value<String> id,
      Value<String> photoId,
      Value<String> encryptedPath,
      Value<String> nonce,
      Value<int> encryptionVersion,
      Value<int> width,
      Value<int> height,
      Value<String> checksumSha256,
      Value<int> rowid,
    });

class $$ThumbnailsTableFilterComposer
    extends Composer<_$VaultDatabase, $ThumbnailsTable> {
  $$ThumbnailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ThumbnailsTableOrderingComposer
    extends Composer<_$VaultDatabase, $ThumbnailsTable> {
  $$ThumbnailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThumbnailsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $ThumbnailsTable> {
  $$ThumbnailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get checksumSha256 => $composableBuilder(
    column: $table.checksumSha256,
    builder: (column) => column,
  );
}

class $$ThumbnailsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $ThumbnailsTable,
          VaultThumbnail,
          $$ThumbnailsTableFilterComposer,
          $$ThumbnailsTableOrderingComposer,
          $$ThumbnailsTableAnnotationComposer,
          $$ThumbnailsTableCreateCompanionBuilder,
          $$ThumbnailsTableUpdateCompanionBuilder,
          (
            VaultThumbnail,
            BaseReferences<_$VaultDatabase, $ThumbnailsTable, VaultThumbnail>,
          ),
          VaultThumbnail,
          PrefetchHooks Function()
        > {
  $$ThumbnailsTableTableManager(_$VaultDatabase db, $ThumbnailsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThumbnailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThumbnailsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThumbnailsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> photoId = const Value.absent(),
                Value<String> encryptedPath = const Value.absent(),
                Value<String> nonce = const Value.absent(),
                Value<int> encryptionVersion = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<String> checksumSha256 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThumbnailsCompanion(
                id: id,
                photoId: photoId,
                encryptedPath: encryptedPath,
                nonce: nonce,
                encryptionVersion: encryptionVersion,
                width: width,
                height: height,
                checksumSha256: checksumSha256,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String photoId,
                required String encryptedPath,
                required String nonce,
                required int encryptionVersion,
                required int width,
                required int height,
                required String checksumSha256,
                Value<int> rowid = const Value.absent(),
              }) => ThumbnailsCompanion.insert(
                id: id,
                photoId: photoId,
                encryptedPath: encryptedPath,
                nonce: nonce,
                encryptionVersion: encryptionVersion,
                width: width,
                height: height,
                checksumSha256: checksumSha256,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ThumbnailsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $ThumbnailsTable,
      VaultThumbnail,
      $$ThumbnailsTableFilterComposer,
      $$ThumbnailsTableOrderingComposer,
      $$ThumbnailsTableAnnotationComposer,
      $$ThumbnailsTableCreateCompanionBuilder,
      $$ThumbnailsTableUpdateCompanionBuilder,
      (
        VaultThumbnail,
        BaseReferences<_$VaultDatabase, $ThumbnailsTable, VaultThumbnail>,
      ),
      VaultThumbnail,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String objectId,
      required String objectType,
      required int localVersion,
      Value<int?> remoteVersion,
      required String state,
      Value<int> retryCount,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> objectId,
      Value<String> objectType,
      Value<int> localVersion,
      Value<int?> remoteVersion,
      Value<String> state,
      Value<int> retryCount,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$VaultDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteVersion => $composableBuilder(
    column: $table.remoteVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$VaultDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteVersion => $composableBuilder(
    column: $table.remoteVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$VaultDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteVersion => $composableBuilder(
    column: $table.remoteVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $SyncStateTable,
          SyncStateEntry,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateEntry,
            BaseReferences<_$VaultDatabase, $SyncStateTable, SyncStateEntry>,
          ),
          SyncStateEntry,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$VaultDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> objectId = const Value.absent(),
                Value<String> objectType = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<int?> remoteVersion = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                objectId: objectId,
                objectType: objectType,
                localVersion: localVersion,
                remoteVersion: remoteVersion,
                state: state,
                retryCount: retryCount,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String objectId,
                required String objectType,
                required int localVersion,
                Value<int?> remoteVersion = const Value.absent(),
                required String state,
                Value<int> retryCount = const Value.absent(),
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                objectId: objectId,
                objectType: objectType,
                localVersion: localVersion,
                remoteVersion: remoteVersion,
                state: state,
                retryCount: retryCount,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $SyncStateTable,
      SyncStateEntry,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateEntry,
        BaseReferences<_$VaultDatabase, $SyncStateTable, SyncStateEntry>,
      ),
      SyncStateEntry,
      PrefetchHooks Function()
    >;
typedef $$BackupStateTableCreateCompanionBuilder =
    BackupStateCompanion Function({
      required String key,
      required String value,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$BackupStateTableUpdateCompanionBuilder =
    BackupStateCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$BackupStateTableFilterComposer
    extends Composer<_$VaultDatabase, $BackupStateTable> {
  $$BackupStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupStateTableOrderingComposer
    extends Composer<_$VaultDatabase, $BackupStateTable> {
  $$BackupStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupStateTableAnnotationComposer
    extends Composer<_$VaultDatabase, $BackupStateTable> {
  $$BackupStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$BackupStateTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $BackupStateTable,
          BackupStateEntry,
          $$BackupStateTableFilterComposer,
          $$BackupStateTableOrderingComposer,
          $$BackupStateTableAnnotationComposer,
          $$BackupStateTableCreateCompanionBuilder,
          $$BackupStateTableUpdateCompanionBuilder,
          (
            BackupStateEntry,
            BaseReferences<
              _$VaultDatabase,
              $BackupStateTable,
              BackupStateEntry
            >,
          ),
          BackupStateEntry,
          PrefetchHooks Function()
        > {
  $$BackupStateTableTableManager(_$VaultDatabase db, $BackupStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BackupStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BackupStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupStateCompanion(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => BackupStateCompanion.insert(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupStateTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $BackupStateTable,
      BackupStateEntry,
      $$BackupStateTableFilterComposer,
      $$BackupStateTableOrderingComposer,
      $$BackupStateTableAnnotationComposer,
      $$BackupStateTableCreateCompanionBuilder,
      $$BackupStateTableUpdateCompanionBuilder,
      (
        BackupStateEntry,
        BaseReferences<_$VaultDatabase, $BackupStateTable, BackupStateEntry>,
      ),
      BackupStateEntry,
      PrefetchHooks Function()
    >;
typedef $$EncryptionVersionsTableCreateCompanionBuilder =
    EncryptionVersionsCompanion Function({
      Value<int> version,
      required String cipher,
      required String kdf,
      required String paramsJson,
      Value<int> active,
    });
typedef $$EncryptionVersionsTableUpdateCompanionBuilder =
    EncryptionVersionsCompanion Function({
      Value<int> version,
      Value<String> cipher,
      Value<String> kdf,
      Value<String> paramsJson,
      Value<int> active,
    });

class $$EncryptionVersionsTableFilterComposer
    extends Composer<_$VaultDatabase, $EncryptionVersionsTable> {
  $$EncryptionVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cipher => $composableBuilder(
    column: $table.cipher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kdf => $composableBuilder(
    column: $table.kdf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EncryptionVersionsTableOrderingComposer
    extends Composer<_$VaultDatabase, $EncryptionVersionsTable> {
  $$EncryptionVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cipher => $composableBuilder(
    column: $table.cipher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kdf => $composableBuilder(
    column: $table.kdf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EncryptionVersionsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $EncryptionVersionsTable> {
  $$EncryptionVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get cipher =>
      $composableBuilder(column: $table.cipher, builder: (column) => column);

  GeneratedColumn<String> get kdf =>
      $composableBuilder(column: $table.kdf, builder: (column) => column);

  GeneratedColumn<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$EncryptionVersionsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $EncryptionVersionsTable,
          EncryptionVersionEntry,
          $$EncryptionVersionsTableFilterComposer,
          $$EncryptionVersionsTableOrderingComposer,
          $$EncryptionVersionsTableAnnotationComposer,
          $$EncryptionVersionsTableCreateCompanionBuilder,
          $$EncryptionVersionsTableUpdateCompanionBuilder,
          (
            EncryptionVersionEntry,
            BaseReferences<
              _$VaultDatabase,
              $EncryptionVersionsTable,
              EncryptionVersionEntry
            >,
          ),
          EncryptionVersionEntry,
          PrefetchHooks Function()
        > {
  $$EncryptionVersionsTableTableManager(
    _$VaultDatabase db,
    $EncryptionVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EncryptionVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EncryptionVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EncryptionVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> version = const Value.absent(),
                Value<String> cipher = const Value.absent(),
                Value<String> kdf = const Value.absent(),
                Value<String> paramsJson = const Value.absent(),
                Value<int> active = const Value.absent(),
              }) => EncryptionVersionsCompanion(
                version: version,
                cipher: cipher,
                kdf: kdf,
                paramsJson: paramsJson,
                active: active,
              ),
          createCompanionCallback:
              ({
                Value<int> version = const Value.absent(),
                required String cipher,
                required String kdf,
                required String paramsJson,
                Value<int> active = const Value.absent(),
              }) => EncryptionVersionsCompanion.insert(
                version: version,
                cipher: cipher,
                kdf: kdf,
                paramsJson: paramsJson,
                active: active,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EncryptionVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $EncryptionVersionsTable,
      EncryptionVersionEntry,
      $$EncryptionVersionsTableFilterComposer,
      $$EncryptionVersionsTableOrderingComposer,
      $$EncryptionVersionsTableAnnotationComposer,
      $$EncryptionVersionsTableCreateCompanionBuilder,
      $$EncryptionVersionsTableUpdateCompanionBuilder,
      (
        EncryptionVersionEntry,
        BaseReferences<
          _$VaultDatabase,
          $EncryptionVersionsTable,
          EncryptionVersionEntry
        >,
      ),
      EncryptionVersionEntry,
      PrefetchHooks Function()
    >;
typedef $$ImportJobsTableCreateCompanionBuilder =
    ImportJobsCompanion Function({
      required String id,
      required String source,
      required int totalItems,
      required int completedItems,
      required int failedItems,
      required String status,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ImportJobsTableUpdateCompanionBuilder =
    ImportJobsCompanion Function({
      Value<String> id,
      Value<String> source,
      Value<int> totalItems,
      Value<int> completedItems,
      Value<int> failedItems,
      Value<String> status,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ImportJobsTableFilterComposer
    extends Composer<_$VaultDatabase, $ImportJobsTable> {
  $$ImportJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedItems => $composableBuilder(
    column: $table.failedItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportJobsTableOrderingComposer
    extends Composer<_$VaultDatabase, $ImportJobsTable> {
  $$ImportJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedItems => $composableBuilder(
    column: $table.failedItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportJobsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $ImportJobsTable> {
  $$ImportJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failedItems => $composableBuilder(
    column: $table.failedItems,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ImportJobsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $ImportJobsTable,
          ImportJobEntry,
          $$ImportJobsTableFilterComposer,
          $$ImportJobsTableOrderingComposer,
          $$ImportJobsTableAnnotationComposer,
          $$ImportJobsTableCreateCompanionBuilder,
          $$ImportJobsTableUpdateCompanionBuilder,
          (
            ImportJobEntry,
            BaseReferences<_$VaultDatabase, $ImportJobsTable, ImportJobEntry>,
          ),
          ImportJobEntry,
          PrefetchHooks Function()
        > {
  $$ImportJobsTableTableManager(_$VaultDatabase db, $ImportJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> totalItems = const Value.absent(),
                Value<int> completedItems = const Value.absent(),
                Value<int> failedItems = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportJobsCompanion(
                id: id,
                source: source,
                totalItems: totalItems,
                completedItems: completedItems,
                failedItems: failedItems,
                status: status,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String source,
                required int totalItems,
                required int completedItems,
                required int failedItems,
                required String status,
                required int createdAtMs,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ImportJobsCompanion.insert(
                id: id,
                source: source,
                totalItems: totalItems,
                completedItems: completedItems,
                failedItems: failedItems,
                status: status,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $ImportJobsTable,
      ImportJobEntry,
      $$ImportJobsTableFilterComposer,
      $$ImportJobsTableOrderingComposer,
      $$ImportJobsTableAnnotationComposer,
      $$ImportJobsTableCreateCompanionBuilder,
      $$ImportJobsTableUpdateCompanionBuilder,
      (
        ImportJobEntry,
        BaseReferences<_$VaultDatabase, $ImportJobsTable, ImportJobEntry>,
      ),
      ImportJobEntry,
      PrefetchHooks Function()
    >;
typedef $$ShareExportsTableCreateCompanionBuilder =
    ShareExportsCompanion Function({
      required String id,
      Value<String?> photoId,
      required String exportMode,
      required String packagePath,
      Value<int?> expiresAtMs,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$ShareExportsTableUpdateCompanionBuilder =
    ShareExportsCompanion Function({
      Value<String> id,
      Value<String?> photoId,
      Value<String> exportMode,
      Value<String> packagePath,
      Value<int?> expiresAtMs,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

class $$ShareExportsTableFilterComposer
    extends Composer<_$VaultDatabase, $ShareExportsTable> {
  $$ShareExportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exportMode => $composableBuilder(
    column: $table.exportMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packagePath => $composableBuilder(
    column: $table.packagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShareExportsTableOrderingComposer
    extends Composer<_$VaultDatabase, $ShareExportsTable> {
  $$ShareExportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exportMode => $composableBuilder(
    column: $table.exportMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packagePath => $composableBuilder(
    column: $table.packagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShareExportsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $ShareExportsTable> {
  $$ShareExportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<String> get exportMode => $composableBuilder(
    column: $table.exportMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packagePath => $composableBuilder(
    column: $table.packagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$ShareExportsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $ShareExportsTable,
          ShareExportEntry,
          $$ShareExportsTableFilterComposer,
          $$ShareExportsTableOrderingComposer,
          $$ShareExportsTableAnnotationComposer,
          $$ShareExportsTableCreateCompanionBuilder,
          $$ShareExportsTableUpdateCompanionBuilder,
          (
            ShareExportEntry,
            BaseReferences<
              _$VaultDatabase,
              $ShareExportsTable,
              ShareExportEntry
            >,
          ),
          ShareExportEntry,
          PrefetchHooks Function()
        > {
  $$ShareExportsTableTableManager(_$VaultDatabase db, $ShareExportsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShareExportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShareExportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShareExportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> photoId = const Value.absent(),
                Value<String> exportMode = const Value.absent(),
                Value<String> packagePath = const Value.absent(),
                Value<int?> expiresAtMs = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShareExportsCompanion(
                id: id,
                photoId: photoId,
                exportMode: exportMode,
                packagePath: packagePath,
                expiresAtMs: expiresAtMs,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> photoId = const Value.absent(),
                required String exportMode,
                required String packagePath,
                Value<int?> expiresAtMs = const Value.absent(),
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ShareExportsCompanion.insert(
                id: id,
                photoId: photoId,
                exportMode: exportMode,
                packagePath: packagePath,
                expiresAtMs: expiresAtMs,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShareExportsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $ShareExportsTable,
      ShareExportEntry,
      $$ShareExportsTableFilterComposer,
      $$ShareExportsTableOrderingComposer,
      $$ShareExportsTableAnnotationComposer,
      $$ShareExportsTableCreateCompanionBuilder,
      $$ShareExportsTableUpdateCompanionBuilder,
      (
        ShareExportEntry,
        BaseReferences<_$VaultDatabase, $ShareExportsTable, ShareExportEntry>,
      ),
      ShareExportEntry,
      PrefetchHooks Function()
    >;
typedef $$TrashItemsTableCreateCompanionBuilder =
    TrashItemsCompanion Function({
      required String photoId,
      required int movedAtMs,
      required int expiresAtMs,
      Value<int> syncDeletePending,
      Value<int> rowid,
    });
typedef $$TrashItemsTableUpdateCompanionBuilder =
    TrashItemsCompanion Function({
      Value<String> photoId,
      Value<int> movedAtMs,
      Value<int> expiresAtMs,
      Value<int> syncDeletePending,
      Value<int> rowid,
    });

class $$TrashItemsTableFilterComposer
    extends Composer<_$VaultDatabase, $TrashItemsTable> {
  $$TrashItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get movedAtMs => $composableBuilder(
    column: $table.movedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncDeletePending => $composableBuilder(
    column: $table.syncDeletePending,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrashItemsTableOrderingComposer
    extends Composer<_$VaultDatabase, $TrashItemsTable> {
  $$TrashItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get movedAtMs => $composableBuilder(
    column: $table.movedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncDeletePending => $composableBuilder(
    column: $table.syncDeletePending,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrashItemsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $TrashItemsTable> {
  $$TrashItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<int> get movedAtMs =>
      $composableBuilder(column: $table.movedAtMs, builder: (column) => column);

  GeneratedColumn<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncDeletePending => $composableBuilder(
    column: $table.syncDeletePending,
    builder: (column) => column,
  );
}

class $$TrashItemsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $TrashItemsTable,
          TrashItem,
          $$TrashItemsTableFilterComposer,
          $$TrashItemsTableOrderingComposer,
          $$TrashItemsTableAnnotationComposer,
          $$TrashItemsTableCreateCompanionBuilder,
          $$TrashItemsTableUpdateCompanionBuilder,
          (
            TrashItem,
            BaseReferences<_$VaultDatabase, $TrashItemsTable, TrashItem>,
          ),
          TrashItem,
          PrefetchHooks Function()
        > {
  $$TrashItemsTableTableManager(_$VaultDatabase db, $TrashItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrashItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrashItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrashItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> photoId = const Value.absent(),
                Value<int> movedAtMs = const Value.absent(),
                Value<int> expiresAtMs = const Value.absent(),
                Value<int> syncDeletePending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrashItemsCompanion(
                photoId: photoId,
                movedAtMs: movedAtMs,
                expiresAtMs: expiresAtMs,
                syncDeletePending: syncDeletePending,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String photoId,
                required int movedAtMs,
                required int expiresAtMs,
                Value<int> syncDeletePending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrashItemsCompanion.insert(
                photoId: photoId,
                movedAtMs: movedAtMs,
                expiresAtMs: expiresAtMs,
                syncDeletePending: syncDeletePending,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrashItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $TrashItemsTable,
      TrashItem,
      $$TrashItemsTableFilterComposer,
      $$TrashItemsTableOrderingComposer,
      $$TrashItemsTableAnnotationComposer,
      $$TrashItemsTableCreateCompanionBuilder,
      $$TrashItemsTableUpdateCompanionBuilder,
      (TrashItem, BaseReferences<_$VaultDatabase, $TrashItemsTable, TrashItem>),
      TrashItem,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$VaultDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$VaultDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $AppSettingsTable,
          AppSettingEntry,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingEntry,
            BaseReferences<_$VaultDatabase, $AppSettingsTable, AppSettingEntry>,
          ),
          AppSettingEntry,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$VaultDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $AppSettingsTable,
      AppSettingEntry,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingEntry,
        BaseReferences<_$VaultDatabase, $AppSettingsTable, AppSettingEntry>,
      ),
      AppSettingEntry,
      PrefetchHooks Function()
    >;
typedef $$SecurityEventsTableCreateCompanionBuilder =
    SecurityEventsCompanion Function({
      required String id,
      required String eventType,
      required String severity,
      required int occurredAtMs,
      Value<String?> detailsJson,
      Value<int> rowid,
    });
typedef $$SecurityEventsTableUpdateCompanionBuilder =
    SecurityEventsCompanion Function({
      Value<String> id,
      Value<String> eventType,
      Value<String> severity,
      Value<int> occurredAtMs,
      Value<String?> detailsJson,
      Value<int> rowid,
    });

class $$SecurityEventsTableFilterComposer
    extends Composer<_$VaultDatabase, $SecurityEventsTable> {
  $$SecurityEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SecurityEventsTableOrderingComposer
    extends Composer<_$VaultDatabase, $SecurityEventsTable> {
  $$SecurityEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SecurityEventsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $SecurityEventsTable> {
  $$SecurityEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );
}

class $$SecurityEventsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $SecurityEventsTable,
          SecurityEvent,
          $$SecurityEventsTableFilterComposer,
          $$SecurityEventsTableOrderingComposer,
          $$SecurityEventsTableAnnotationComposer,
          $$SecurityEventsTableCreateCompanionBuilder,
          $$SecurityEventsTableUpdateCompanionBuilder,
          (
            SecurityEvent,
            BaseReferences<
              _$VaultDatabase,
              $SecurityEventsTable,
              SecurityEvent
            >,
          ),
          SecurityEvent,
          PrefetchHooks Function()
        > {
  $$SecurityEventsTableTableManager(
    _$VaultDatabase db,
    $SecurityEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecurityEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SecurityEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SecurityEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<int> occurredAtMs = const Value.absent(),
                Value<String?> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecurityEventsCompanion(
                id: id,
                eventType: eventType,
                severity: severity,
                occurredAtMs: occurredAtMs,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String eventType,
                required String severity,
                required int occurredAtMs,
                Value<String?> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecurityEventsCompanion.insert(
                id: id,
                eventType: eventType,
                severity: severity,
                occurredAtMs: occurredAtMs,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SecurityEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $SecurityEventsTable,
      SecurityEvent,
      $$SecurityEventsTableFilterComposer,
      $$SecurityEventsTableOrderingComposer,
      $$SecurityEventsTableAnnotationComposer,
      $$SecurityEventsTableCreateCompanionBuilder,
      $$SecurityEventsTableUpdateCompanionBuilder,
      (
        SecurityEvent,
        BaseReferences<_$VaultDatabase, $SecurityEventsTable, SecurityEvent>,
      ),
      SecurityEvent,
      PrefetchHooks Function()
    >;

class $VaultDatabaseManager {
  final _$VaultDatabase _db;
  $VaultDatabaseManager(this._db);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$PhotoTagsTableTableManager get photoTags =>
      $$PhotoTagsTableTableManager(_db, _db.photoTags);
  $$VaultTableTableManager get vault =>
      $$VaultTableTableManager(_db, _db.vault);
  $$ThumbnailsTableTableManager get thumbnails =>
      $$ThumbnailsTableTableManager(_db, _db.thumbnails);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$BackupStateTableTableManager get backupState =>
      $$BackupStateTableTableManager(_db, _db.backupState);
  $$EncryptionVersionsTableTableManager get encryptionVersions =>
      $$EncryptionVersionsTableTableManager(_db, _db.encryptionVersions);
  $$ImportJobsTableTableManager get importJobs =>
      $$ImportJobsTableTableManager(_db, _db.importJobs);
  $$ShareExportsTableTableManager get shareExports =>
      $$ShareExportsTableTableManager(_db, _db.shareExports);
  $$TrashItemsTableTableManager get trashItems =>
      $$TrashItemsTableTableManager(_db, _db.trashItems);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SecurityEventsTableTableManager get securityEvents =>
      $$SecurityEventsTableTableManager(_db, _db.securityEvents);
}
