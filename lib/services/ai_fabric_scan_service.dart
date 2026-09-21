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
    this.costPerUnit,
    this.retailPrice,
  });

  final String name;
  final String category;
  final String color;
  final double? costPerUnit;
  final double? retailPrice;
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

  static const String _batchPrompt = '''
你是一個專業的裁縫店庫存助手。
這張照片可能是：(a) 供應商文字價目表（每行一款布料），或 (b) 多張實體布卡並排。
請辨識照片中「所有」布料，並只以 JSON 陣列格式回傳，每一筆格式如下：
{
  "name": "品牌名稱加上色號，例如 VBC AR2267 31 Blue",
  "category": "只能填 Cotton, Linen, Wool, 或 Other；無法判斷時填 Other",
  "color": "英文大寫顏色，例如 NAVY BLUE；無法判斷時填空字串",
  "costPerUnit": 成本價數字（數字型別，無法判斷時填 null），
  "retailPrice": 零售價數字（數字型別，無法判斷時填 null）
}
規則：
- 回傳嚴格的 JSON 陣列，例如 [{...}, {...}]，不要有 markdown 包裹、不要有多餘文字。
- 抓不到的欄位回傳空字串或 null，不要猜測或編造。
- category 只能是 Cotton / Linen / Wool / Other，不可填其他值。
- color 用英文大寫。
- 若照片中完全沒有可辨識的布料，回傳空陣列 []。''';

  Future<AiFabricScanResult> scanFabricLabel({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final idToken = await _idTokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw const AiFabricScanException('請先登入後再使用 AI 辨識。');
    }

    String? appCheckToken;
    try {
      appCheckToken = await _appCheckTokenProvider();
    } catch (_) {
      appCheckToken = null;
    }

    final response = await _client.post(
      _proxyUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        if (appCheckToken != null && appCheckToken.isNotEmpty)
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

  Future<List<AiFabricScanResult>> scanFabricLabelBatch({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final idToken = await _idTokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw const AiFabricScanException('請先登入後再使用 AI 辨識。');
    }

    String? appCheckToken;
    try {
      appCheckToken = await _appCheckTokenProvider();
    } catch (_) {
      appCheckToken = null;
    }

    final response = await _client.post(
      _proxyUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        if (appCheckToken != null && appCheckToken.isNotEmpty)
          'X-Firebase-AppCheck': appCheckToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _batchPrompt},
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

    return parseGeminiResponseBatch(response.body);
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

  static List<AiFabricScanResult> parseGeminiResponseBatch(String responseBody) {
    final dynamic decodedResponse = jsonDecode(responseBody);
    if (decodedResponse is! Map<String, dynamic>) return [];

    final text = _extractCandidateText(decodedResponse);
    if (text == null || text.trim().isEmpty) return [];

    return parseFabricJsonArrayText(text);
  }

  static List<AiFabricScanResult> parseFabricJsonArrayText(String text) {
    // Attempt 1: strip code fence, parse directly.
    try {
      final cleanJson = _stripMarkdownCodeFence(text.trim());
      final dynamic decoded = jsonDecode(cleanJson);
      if (decoded is List) return _mapBatchList(decoded);
    } catch (_) {}

    // Attempt 2: extract the first [...] block from the raw text (handles
    // responses where Gemini wraps the array in explanatory prose).
    try {
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start != -1 && end > start) {
        final dynamic decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is List) return _mapBatchList(decoded);
      }
    } catch (e) {
      // ignore: avoid_print
      print('AiFabricScanService batch parse error: $e');
    }

    return [];
  }

  static List<AiFabricScanResult> _mapBatchList(List<dynamic> list) {
    final results = <AiFabricScanResult>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      results.add(AiFabricScanResult(
        name: item['name']?.toString() ?? '',
        category: item['category']?.toString() ?? 'Other',
        color: (item['color']?.toString() ?? '').toUpperCase(),
        costPerUnit: _parseNullableDouble(item['costPerUnit']),
        retailPrice: _parseNullableDouble(item['retailPrice']),
      ));
    }
    return results;
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
