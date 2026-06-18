import 'dart:convert';
import 'dart:typed_data';

import 'package:alexis_system/services/ai_fabric_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AiFabricScanService parsing', () {
    test('parses Gemini JSON text', () {
      final result = AiFabricScanService.parseGeminiResponse(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'name': 'VBC AR2267 31 Blue',
                      'category': 'Wool',
                      'color': 'navy blue',
                    }),
                  },
                ],
              },
            },
          ],
        }),
      );

      expect(result.name, 'VBC AR2267 31 Blue');
      expect(result.category, 'Wool');
      expect(result.color, 'NAVY BLUE');
    });

    test('parses JSON wrapped in markdown code fence', () {
      final result = AiFabricScanService.parseFabricJsonText('''
```json
{"name":"LINEN 101","category":"Linen","color":"ivory"}
```
''');

      expect(result.name, 'LINEN 101');
      expect(result.category, 'Linen');
      expect(result.color, 'IVORY');
    });

    test('throws for malformed JSON', () {
      expect(
        () => AiFabricScanService.parseFabricJsonText('not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AiFabricScanService HTTP', () {
    test('sends Firebase token and image payload to proxy', () async {
      late http.Request capturedRequest;
      final service = AiFabricScanService(
        idTokenProvider: () async => 'test-token',
        appCheckTokenProvider: () async => 'test-app-check-token',
        proxyUri: Uri.parse('https://example.test/gemini'),
        client: MockClient((request) async {
          capturedRequest = request;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final parts = body['contents'][0]['parts'] as List<dynamic>;
          final imagePart = parts[1]['inlineData'] as Map<String, dynamic>;

          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(
            request.headers['X-Firebase-AppCheck'],
            'test-app-check-token',
          );
          expect(request.headers['Content-Type'], 'application/json');
          expect(imagePart['mimeType'], 'image/png');
          expect(imagePart['data'], isNotEmpty);

          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            '{"name":"TEST","category":"Cotton","color":"BLACK"}',
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.scanFabricLabel(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );

      expect(capturedRequest.url, Uri.parse('https://example.test/gemini'));
      expect(result.name, 'TEST');
      expect(result.category, 'Cotton');
      expect(result.color, 'BLACK');
    });

    test('continues without App Check token', () async {
      late http.Request capturedRequest;
      final service = AiFabricScanService(
        idTokenProvider: () async => 'test-token',
        appCheckTokenProvider: () async => null,
        proxyUri: Uri.parse('https://example.test/gemini'),
        client: MockClient((request) async {
          capturedRequest = request;

          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            '{"name":"TEST","category":"Cotton","color":"NAVY"}',
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.scanFabricLabel(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );

      expect(capturedRequest.headers['Authorization'], 'Bearer test-token');
      expect(capturedRequest.headers.containsKey('X-Firebase-AppCheck'), false);
      expect(result.color, 'NAVY');
    });

    test('throws when token provider returns empty token', () async {
      final service = AiFabricScanService(
        idTokenProvider: () async => '',
        appCheckTokenProvider: () async => 'test-app-check-token',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => service.scanFabricLabel(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiFabricScanException>()),
      );
    });

    test('throws on proxy error', () async {
      final service = AiFabricScanService(
        idTokenProvider: () async => 'test-token',
        appCheckTokenProvider: () async => 'test-app-check-token',
        client: MockClient((_) async => http.Response('Unauthorized', 401)),
      );

      expect(
        () => service.scanFabricLabel(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiFabricScanException>()),
      );
    });
  });
}
