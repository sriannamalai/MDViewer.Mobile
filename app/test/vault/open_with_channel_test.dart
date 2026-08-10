// OpenWithFile.tryParse unit tests (task-7-brief.md's "open-with routing
// logic unit-tested behind a seam") — the actual platform-channel delivery
// (SceneDelegate/MainActivity → native OpenWithChannel → this parser) is
// device-E2E only (Task 8); this is the pure-Dart trust-boundary parser
// that sits right at the edge of that channel, the same role
// `ScrollSpyPayload.tryParse` plays for the scrollspy channel.

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/vault/open_with_channel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('OpenWithFile.tryParse', () {
    test('parses a well-formed payload with a Uint8List bytes field', () {
      final file = OpenWithFile.tryParse({
        'name': 'Notes.md',
        'mimeType': 'text/markdown',
        'bytes': _bytes('# hello'),
      });

      expect(file, isNotNull);
      expect(file!.name, 'Notes.md');
      expect(file.mimeType, 'text/markdown');
      expect(utf8.decode(file.bytes), '# hello');
    });

    test(
      'accepts a plain List<int> bytes field (some codecs decode this way)',
      () {
        final file = OpenWithFile.tryParse({
          'name': 'Notes.md',
          'bytes': [104, 105], // "hi"
        });

        expect(file, isNotNull);
        expect(utf8.decode(file!.bytes), 'hi');
        expect(file.mimeType, isNull);
      },
    );

    test('a missing mimeType is fine — the field is optional', () {
      final file = OpenWithFile.tryParse({
        'name': 'A.md',
        'bytes': _bytes('x'),
      });
      expect(file, isNotNull);
      expect(file!.mimeType, isNull);
    });

    test('null input returns null, not a crash', () {
      expect(OpenWithFile.tryParse(null), isNull);
    });

    test('a non-Map input returns null', () {
      expect(OpenWithFile.tryParse('not a map'), isNull);
      expect(OpenWithFile.tryParse(42), isNull);
    });

    test('a missing name returns null', () {
      expect(OpenWithFile.tryParse({'bytes': _bytes('x')}), isNull);
    });

    test('an empty name returns null', () {
      expect(OpenWithFile.tryParse({'name': '', 'bytes': _bytes('x')}), isNull);
    });

    test('a missing bytes field returns null', () {
      expect(OpenWithFile.tryParse({'name': 'A.md'}), isNull);
    });

    test('a non-string name returns null', () {
      expect(OpenWithFile.tryParse({'name': 42, 'bytes': _bytes('x')}), isNull);
    });

    test(
      'a non-string mimeType is dropped, not treated as a parse failure',
      () {
        final file = OpenWithFile.tryParse({
          'name': 'A.md',
          'bytes': _bytes('x'),
          'mimeType': 7,
        });
        expect(file, isNotNull);
        expect(file!.mimeType, isNull);
      },
    );
  });
}
