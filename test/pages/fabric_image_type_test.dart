import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexis_system/pages/fabric_page.dart';

void main() {
  test('detects jpeg, png, webp by magic bytes', () {
    expect(detectImageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]))?.contentType, 'image/jpeg');
    expect(detectImageType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10]))?.ext, 'png');
    final webp = Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]);
    expect(detectImageType(webp)?.contentType, 'image/webp');
  });

  test('returns null for unsupported or empty data', () {
    expect(detectImageType(Uint8List(0)), isNull);
    expect(detectImageType(Uint8List.fromList('GIF89a....'.codeUnits)), isNull);
  });
}
