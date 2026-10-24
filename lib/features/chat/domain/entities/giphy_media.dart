import 'package:flutter/foundation.dart';

import 'chat_message.dart';

@immutable
class GiphyMedia {
  const GiphyMedia({
    required this.id,
    required this.title,
    required this.mediaUrl,
    required this.previewUrl,
    required this.type,
    this.width,
    this.height,
  });

  final String id;
  final String title;
  final String mediaUrl;
  final String previewUrl;
  final MessageType type;
  final int? width;
  final int? height;

  String get extension {
    final path = Uri.parse(mediaUrl).path.toLowerCase();
    return path.endsWith('.webp') ? 'webp' : 'gif';
  }

  factory GiphyMedia.fromJson(
    Map<String, dynamic> json, {
    required MessageType type,
  }) {
    final id = json['id'];
    final title = json['title'];
    final images = json['images'];
    if (id is! String || title is! String || images is! Map) {
      throw const FormatException('Invalid GIPHY media response.');
    }
    final sendImage =
        images['fixed_width'] ??
        images['downsized_medium'] ??
        images['original'];
    final previewImage =
        images['fixed_width_small_still'] ??
        images['fixed_width_still'] ??
        sendImage;
    if (sendImage is! Map ||
        previewImage is! Map ||
        sendImage['url'] is! String ||
        previewImage['url'] is! String) {
      throw const FormatException('GIPHY result has no usable renditions.');
    }
    final mediaUrl = sendImage['url'] as String;
    final previewUrl = previewImage['url'] as String;
    if (!_isGiphyUrl(mediaUrl) || !_isGiphyUrl(previewUrl)) {
      throw const FormatException('GIPHY media URL is not trusted.');
    }
    return GiphyMedia(
      id: id,
      title: title,
      mediaUrl: mediaUrl,
      previewUrl: previewUrl,
      type: type,
      width: _dimension(sendImage['width']),
      height: _dimension(sendImage['height']),
    );
  }

  static int? _dimension(Object? value) => switch (value) {
    final int dimension => dimension,
    final String dimension => int.tryParse(dimension),
    _ => null,
  };

  static bool _isGiphyUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return false;
    return uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com');
  }
}
