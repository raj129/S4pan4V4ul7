import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/giphy_media.dart';

class GiphyMediaPage {
  const GiphyMediaPage({required this.results, required this.nextOffset});

  final List<GiphyMedia> results;
  final int? nextOffset;
}

class GiphyMediaService {
  GiphyMediaService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? const String.fromEnvironment('GIPHY_API_KEY');

  static const pageSize = 24;
  static const maxMediaBytes = 4 * 1024 * 1024;
  static const _maxSearchChars = 50;
  static const _maxOffset = 4999;
  static const _allowedMediaHostSuffix = '.giphy.com';

  final http.Client _client;
  final String _apiKey;

  Future<GiphyMediaPage> search({
    required String query,
    required MessageType type,
    int offset = 0,
  }) async {
    if (type != MessageType.gif && type != MessageType.sticker) {
      throw ArgumentError.value(type, 'type', 'Expected GIF or sticker.');
    }
    if (_apiKey.isEmpty) {
      throw StateError(
        'GIPHY_API_KEY is not configured. Supply it at build time with '
        '--dart-define=GIPHY_API_KEY=<your-key>.',
      );
    }
    if (offset < 0 || offset > _maxOffset) {
      throw ArgumentError.value(offset, 'offset', 'Invalid GIPHY offset.');
    }
    final normalized = query.trim();
    if (normalized.length > _maxSearchChars) {
      throw ArgumentError.value(
        query,
        'query',
        'GIPHY search text must be 50 characters or fewer.',
      );
    }

    final kind = type == MessageType.sticker ? 'stickers' : 'gifs';
    final endpoint = normalized.isEmpty ? 'trending' : 'search';
    final uri = Uri.https('api.giphy.com', '/v1/$kind/$endpoint', {
      'api_key': _apiKey,
      'limit': '$pageSize',
      'offset': '$offset',
      'rating': 'g',
      'bundle': 'messaging_non_clips',
      if (normalized.isNotEmpty) 'q': normalized,
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('GIPHY search failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const FormatException('Invalid GIPHY search response.');
    }

    final results = <GiphyMedia>[];
    for (final value in decoded['data'] as List) {
      if (value is! Map<String, dynamic>) continue;
      try {
        results.add(GiphyMedia.fromJson(value, type: type));
      } on FormatException {
        continue;
      }
    }
    final pagination = decoded['pagination'];
    final totalCount = pagination is Map
        ? (pagination['total_count'] as num?)?.toInt()
        : null;
    final reportedPageCount = pagination is Map
        ? (pagination['count'] as num?)?.toInt() ?? results.length
        : results.length;
    final pageCount = reportedPageCount > 0
        ? reportedPageCount
        : results.length;
    final nextOffset = offset + pageCount;
    return GiphyMediaPage(
      results: results,
      nextOffset:
          results.isNotEmpty &&
              nextOffset <= _maxOffset &&
              (totalCount == null || nextOffset < totalCount)
          ? nextOffset
          : null,
    );
  }

  Future<Uint8List> download(GiphyMedia media) async {
    final uri = Uri.tryParse(media.mediaUrl);
    if (uri == null || !_isGiphyUrl(uri)) {
      throw const FormatException('GIF URL is not from GIPHY.');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('GIPHY media download failed (${response.statusCode}).');
    }
    final length = response.contentLength;
    if (length != null && (length <= 0 || length > maxMediaBytes)) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('Media is empty or exceeds the 4 MB limit.');
    }
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      total += chunk.length;
      if (total > maxMediaBytes) {
        throw StateError('Media exceeds the 4 MB limit.');
      }
      bytes.add(chunk);
    }
    if (total == 0) throw StateError('GIPHY media download was empty.');
    return bytes.takeBytes();
  }

  static bool _isGiphyUrl(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'giphy.com' || uri.host.endsWith(_allowedMediaHostSuffix));

  void close() => _client.close();
}
