import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/features/chat/application/services/giphy_media_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/giphy_media.dart';

void main() {
  group('GiphyMedia', () {
    test('parses media and preview renditions', () {
      final media = GiphyMedia.fromJson({
        'id': 'gif-1',
        'title': 'A reaction',
        'images': {
          'fixed_width': {
            'url': 'https://media1.giphy.com/media/example/200w.gif',
            'width': '200',
            'height': '150',
          },
          'fixed_width_small_still': {
            'url': 'https://media1.giphy.com/media/example/100w_s.jpg',
          },
        },
      }, type: MessageType.gif);

      expect(media.id, 'gif-1');
      expect(media.type, MessageType.gif);
      expect(media.extension, 'gif');
      expect(media.width, 200);
      expect(media.height, 150);
      expect(media.previewUrl, contains('100w_s.jpg'));
    });

    test('rejects media URLs outside GIPHY', () {
      expect(
        () => GiphyMedia.fromJson({
          'id': 'bad',
          'title': '',
          'images': {
            'fixed_width': {'url': 'https://example.com/file.gif'},
            'fixed_width_small_still': {
              'url': 'https://media.giphy.com/preview.jpg',
            },
          },
        }, type: MessageType.sticker),
        throwsFormatException,
      );
    });
  });

  test(
    'search uses GIPHY client endpoints and returns a next offset',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'sticker-1',
                'title': 'hello',
                'images': {
                  'fixed_width': {
                    'url': 'https://media.giphy.com/media/example/200w.gif',
                  },
                  'fixed_width_small_still': {
                    'url': 'https://media.giphy.com/media/example/100w_s.jpg',
                  },
                },
              },
            ],
            'pagination': {'total_count': 30, 'count': 24},
          }),
          200,
        );
      });
      final service = GiphyMediaService(client: client, apiKey: 'test-key');
      try {
        final page = await service.search(
          query: 'hello',
          type: MessageType.sticker,
        );

        expect(requests.single.url.path, '/v1/stickers/search');
        expect(requests.single.url.queryParameters['api_key'], 'test-key');
        expect(requests.single.url.queryParameters['q'], 'hello');
        expect(requests.single.url.queryParameters['rating'], 'g');
        expect(page.results.single.type, MessageType.sticker);
        expect(page.nextOffset, 24);
      } finally {
        service.close();
      }
    },
  );

  test('empty query uses the trending endpoint', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/gifs/trending');
      expect(request.url.queryParameters.containsKey('q'), isFalse);
      return http.Response(
        jsonEncode({
          'data': [],
          'pagination': {'total_count': 0},
        }),
        200,
      );
    });
    final service = GiphyMediaService(client: client, apiKey: 'test-key');
    try {
      final page = await service.search(query: '', type: MessageType.gif);
      expect(page.results, isEmpty);
      expect(page.nextOffset, isNull);
    } finally {
      service.close();
    }
  });
}
