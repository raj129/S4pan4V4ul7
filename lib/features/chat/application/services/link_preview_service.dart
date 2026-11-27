import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Metadata extracted from a shared URL (title, description, image, site name).
class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    required this.domain,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  final String url;
  final String domain;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  bool get hasMetadata =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
}

/// Fetches and caches Open Graph / oEmbed link previews for chat URLs.
class LinkPreviewService {
  LinkPreviewService._();

  static final LinkPreviewService instance = LinkPreviewService._();

  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+)',
    caseSensitive: false,
  );

  final Map<String, LinkPreviewData?> _cache = {};
  final Map<String, Future<LinkPreviewData?>> _inFlight = {};

  /// Extracts the first `http(s)://` URL from [text], trimming trailing punctuation.
  static String? extractFirstUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    var raw = match.group(0)!;
    while (raw.isNotEmpty && '.,!?;:)'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.toString();
  }

  LinkPreviewData? peek(String url) => _cache[url];

  Future<LinkPreviewData?> fetch(String url) {
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _fetchInternal(url).whenComplete(() {
      _inFlight.remove(url);
    });
    _inFlight[url] = future;
    return future;
  }

  Future<LinkPreviewData?> _fetchInternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      _cache[url] = null;
      return null;
    }
    final domain = uri.host.replaceFirst(RegExp(r'^www\.'), '');

    try {
      // YouTube / YouTube Music oEmbed gives reliable titles and thumbnails.
      if (_isYouTubeHost(domain)) {
        final oembed = await _fetchYouTubeOembed(url, domain);
        if (oembed != null) {
          _cache[url] = oembed;
          return oembed;
        }
      }

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (compatible; LinkPreviewBot/1.0)',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 400) {
        _cache[url] = null;
        return null;
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('html') && !contentType.contains('text')) {
        _cache[url] = null;
        return null;
      }

      final html = response.body.length > 65536
          ? response.body.substring(0, 65536)
          : response.body;

      final title =
          _metaContent(html, 'og:title') ??
          _metaContent(html, 'twitter:title') ??
          _htmlTitle(html);
      final description =
          _metaContent(html, 'og:description') ??
          _metaContent(html, 'twitter:description') ??
          _metaContent(html, 'description');
      final rawImage =
          _metaContent(html, 'og:image') ??
          _metaContent(html, 'twitter:image');
      final siteName = _metaContent(html, 'og:site_name');

      String? imageUrl;
      if (rawImage != null && rawImage.isNotEmpty) {
        final resolved = uri.resolve(rawImage);
        if (resolved.scheme == 'http' || resolved.scheme == 'https') {
          imageUrl = resolved.toString();
        }
      }

      final data = LinkPreviewData(
        url: url,
        domain: domain,
        title: title,
        description: description,
        imageUrl: imageUrl,
        siteName: siteName,
      );
      _cache[url] = data.hasMetadata ? data : null;
      return _cache[url];
    } catch (_) {
      _cache[url] = null;
      return null;
    }
  }

  static bool _isYouTubeHost(String domain) =>
      domain == 'youtube.com' ||
      domain == 'm.youtube.com' ||
      domain == 'music.youtube.com' ||
      domain == 'youtu.be';

  Future<LinkPreviewData?> _fetchYouTubeOembed(
    String url,
    String domain,
  ) async {
    try {
      final oembedUri = Uri.https('www.youtube.com', '/oembed', {
        'url': url,
        'format': 'json',
      });
      final res = await http.get(oembedUri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return LinkPreviewData(
        url: url,
        domain: domain,
        title: json['title'] as String?,
        description: json['author_name'] as String?,
        imageUrl: json['thumbnail_url'] as String?,
        siteName: domain.startsWith('music.') ? 'YouTube Music' : 'YouTube',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _metaContent(String html, String key) {
    final escaped = RegExp.escape(key);
    final patterns = [
      RegExp(
        '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]+content=["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]+(?:property|name)=["\']$escaped["\']',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m != null) {
        final val = _decodeHtml(m.group(1) ?? '').trim();
        if (val.isNotEmpty) return val;
      }
    }
    return null;
  }

  static String? _htmlTitle(String html) {
    final m = RegExp(
      r'<title[^>]*>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (m == null) return null;
    final val = _decodeHtml(m.group(1) ?? '').trim();
    return val.isEmpty ? null : val;
  }

  static String _decodeHtml(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}
