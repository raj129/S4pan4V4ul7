import 'package:flutter/foundation.dart';

@immutable
class LocalSticker {
  const LocalSticker({
    required this.id,
    required this.fileName,
    required this.extension,
    required this.label,
    required this.sizeBytes,
    required this.addedAt,
    required this.sha256,
  });

  final String id;
  final String fileName;
  final String extension;
  final String label;
  final int sizeBytes;
  final DateTime addedAt;
  final String sha256;

  factory LocalSticker.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final fileName = json['fileName'];
    final extension = json['extension'];
    final label = json['label'];
    final sizeBytes = json['sizeBytes'];
    final addedAt = json['addedAt'];
    final sha256 = json['sha256'];
    if (id is! String ||
        fileName is! String ||
        !_validFileName(fileName) ||
        extension is! String ||
        !_allowedExtensions.contains(extension) ||
        label is! String ||
        sizeBytes is! int ||
        sizeBytes < 1 ||
        addedAt is! int ||
        sha256 is! String) {
      throw const FormatException('Invalid saved sticker metadata.');
    }
    return LocalSticker(
      id: id,
      fileName: fileName,
      extension: extension,
      label: label,
      sizeBytes: sizeBytes,
      addedAt: DateTime.fromMillisecondsSinceEpoch(addedAt, isUtc: true),
      sha256: sha256,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'fileName': fileName,
    'extension': extension,
    'label': label,
    'sizeBytes': sizeBytes,
    'addedAt': addedAt.toUtc().millisecondsSinceEpoch,
    'sha256': sha256,
  };

  static const _allowedExtensions = {'gif', 'webp', 'png', 'jpg', 'jpeg'};

  static bool _validFileName(String value) =>
      value.isNotEmpty &&
      value == value.split(RegExp(r'[/\\]')).last &&
      value.endsWith('.enc');
}
