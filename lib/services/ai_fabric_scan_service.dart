import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AiFabricScanResult {
  const AiFabricScanResult({
    required this.name,
    required this.category,
    required this.color,
  });

  final String name;
  final String category;
  final String color;
}

class AiFabricScanException implements Exception {
  const AiFabricScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiFabricScanService {
  AiFabricScanService({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
    Future<String?> Function()? appCheckTokenProvider,
    Uri? proxyUri,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _idTokenProvider = idTokenProvider ?? _firebaseIdTokenProvider,
       _appCheckTokenProvider =
           appCheckTokenProvider ?? _firebaseAppCheckTokenProvider,
       _proxyUri = proxyUri ?? _defaultProxyUri;

  static final Uri _defaultProxyUri = Uri.parse(
    'https://geminiproxy-iv4r7rb3ja-uc.a.run.app',
  );

  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _idTokenProvider;
  final Future<String?> Function() _appCheckTokenProvider;
  final Uri _proxyUri;

  static const String _prompt = '''
你是一個專業的裁縫店庫存助手。
請讀取這張布料標籤照片，並只以 JSON 格式回傳以下資訊：
{
  "name": "品牌名稱加上色號或成分，例如 VBC AR2267 31 Blue",
  "category": "依據成分猜測分類，只能填 Cotton, Linen, Wool, 或 Other",
  "color": "布料顏色，例如 NAVY BLUE、DARK GREY、IVORY，用英文大寫"
}
注意：不要回傳任何 JSON 以外的文字說明。如果看不清楚，請回傳空字串。''';

  Future<AiFabricScanResult> scanFabricLabel({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final idToken = await _idTokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw const AiFabricScanException('請先登入後再使用 AI 辨識。');
    }
    final appCheckToken = await _appCheckTokenProvider();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw const AiFabricScanException('無法取得 App Check 驗證，請重新整理後再試。');
    }

    final response = await _client.post(
      _proxyUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _prompt},
              {
                'inlineData': {
                  'mimeType': mimeType,
                  'data': base64Encode(imageBytes),
                },
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw AiFabricScanException(
        'API 錯誤 ${response.statusCode}: ${response.body}',
      );
    }

    return parseGeminiResponse(response.body);
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static AiFabricScanResult parseGeminiResponse(String responseBody) {
    final dynamic decodedResponse = jsonDecode(responseBody);
    if (decodedResponse is! Map<String, dynamic>) {
      throw const AiFabricScanException('AI 回應格式不正確。');
    }

    final text = _extractCandidateText(decodedResponse);
    if (text == null || text.trim().isEmpty) {
      throw const AiFabricScanException('AI 未回傳可解析的布料資料。');
    }

    return parseFabricJsonText(text);
  }

  static AiFabricScanResult parseFabricJsonText(String text) {
    final cleanJson = _stripMarkdownCodeFence(text);
    final dynamic decodedData = jsonDecode(cleanJson);
    if (decodedData is! Map<String, dynamic>) {
      throw const AiFabricScanException('AI 布料資料格式不正確。');
    }

    return AiFabricScanResult(
      name: decodedData['name']?.toString() ?? '',
      category: decodedData['category']?.toString() ?? '',
      color: (decodedData['color']?.toString() ?? '').toUpperCase(),
    );
  }

  static Future<String?> _firebaseIdTokenProvider() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AiFabricScanException('請先登入後再使用 AI 辨識。');
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const AiFabricScanException('無法取得登入驗證，請重新登入。');
    }

    return idToken;
  }

  static Future<String?> _firebaseAppCheckTokenProvider() async {
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw const AiFabricScanException('無法取得 App Check 驗證，請重新整理後再試。');
    }

    return appCheckToken;
  }

  static String? _extractCandidateText(Map<String, dynamic> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;

    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, dynamic>) return null;

    final content = firstCandidate['content'];
    if (content is! Map<String, dynamic>) return null;

    final parts = content['parts'];
    if (parts is! List) return null;

    final textParts = parts
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text'])
        .whereType<String>();

    return textParts.join();
  }

  static String _stripMarkdownCodeFence(String text) {
    var value = text.trim();
    if (!value.startsWith('```')) return value;

    value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    return value.trim();
  }
}
