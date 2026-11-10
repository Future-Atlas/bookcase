import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/avatar_image_format.dart';

void main() {
  test('detects supported avatar image formats from bytes', () {
    expect(
      AvatarImageFormat.detect(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      same(AvatarImageFormat.jpeg),
    );
    expect(
      AvatarImageFormat.detect(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      same(AvatarImageFormat.png),
    );
    expect(
      AvatarImageFormat.detect(
        Uint8List.fromList([
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
      ),
      same(AvatarImageFormat.webp),
    );
  });

  test('rejects unsupported or truncated image data', () {
    expect(AvatarImageFormat.detect(Uint8List(0)), isNull);
    expect(
      AvatarImageFormat.detect(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])),
      isNull,
    );
  });
  test('web avatar selection skips picker-side canvas conversion', () {
    final source = File(
      'lib/screens/account_settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('maxWidth: kIsWeb ? null : 1024'));
    expect(source, contains('maxHeight: kIsWeb ? null : 1024'));
    expect(source, contains('imageQuality: kIsWeb ? null : 85'));
  });
}
