import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/render/native_images.dart';
import 'package:app/src/render/resolver.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter/painting.dart' show MemoryImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Same device-free fake used by `resolver_test.dart` /
/// `vault_state_test.dart` — see those files' doc comments.
class _FakeVaultProvider implements VaultProvider {
  _FakeVaultProvider({Map<String, Uint8List>? files}) : files = files ?? {};
  final Map<String, Uint8List> files;

  @override
  Future<VaultGrant?> pickFolder() async => null;

  @override
  Future<bool> restore(VaultGrant grant) async => true;

  @override
  Future<List<String>> list(VaultGrant grant) async =>
      files.keys.where((p) => p.toLowerCase().endsWith('.md')).toList();

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final bytes = files[entry.relPath];
    if (bytes == null) throw StateError('not found: ${entry.relPath}');
    return bytes;
  }
}

VaultEntry _entry({String relPath = 'Doc.md'}) => VaultEntry(
  name: relPath,
  relPath: relPath,
  isDir: false,
  children: const [],
  source: VaultSource.sample,
);

/// A resolver wired to a REAL [VaultState.resolveRelative] over fake
/// providers — the exact seam the Reader gives it
/// (`(relPath) => vault.resolveRelative(entry, relPath)`).
Future<NativeImageResolver> _resolverOver(
  Map<String, Uint8List> files, {
  VaultEntry? entry,
}) async {
  final from = entry ?? _entry();
  final vault = VaultState(
    sampleProvider: _FakeVaultProvider(
      files: {'Doc.md': _bytes('# x'), ...files},
    ),
    folderProvider: _FakeVaultProvider(),
  );
  await vault.init();
  return NativeImageResolver(
    resolveBytes: (relPath) => vault.resolveRelative(from, relPath),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NativeImageResolver', () {
    test(
      'a relative png resolves to a MemoryImage with the vault bytes',
      () async {
        final resolver = await _resolverOver({
          'img/logo.png': _bytes('PNGDATA'),
        });

        final provider = await resolver('img/logo.png', 'logo');

        expect(provider, isA<MemoryImage>());
        expect(
          utf8.decode((provider! as MemoryImage).bytes),
          'PNGDATA',
          reason: 'the MemoryImage must carry the resolved vault bytes',
        );
      },
    );

    test(
      'the non-svg allowlist extensions all resolve (case-insensitive)',
      () async {
        final resolver = await _resolverOver({
          'a.png': _bytes('a'),
          'b.jpg': _bytes('b'),
          'c.jpeg': _bytes('c'),
          'd.gif': _bytes('d'),
          'e.webp': _bytes('e'),
          'f.PNG': _bytes('f'),
        });

        for (final target in ['a.png', 'b.jpg', 'c.jpeg', 'd.gif', 'e.webp']) {
          expect(
            await resolver(target, ''),
            isA<MemoryImage>(),
            reason: target,
          );
        }
        // extensionOf lowercases, mirroring DocImages' rule.
        expect(await resolver('f.PNG', ''), isA<MemoryImage>());
      },
    );

    test('a well-formed relative svg rasterizes to a non-null ImageProvider '
        '(NOT a MemoryImage — the bytes are vector source, not raster)', () async {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 24 24"><rect width="24" height="24"/></svg>';
      final resolver = await _resolverOver({'img/d.svg': _bytes(svg)});

      final provider = await resolver('img/d.svg', 'diagram');

      expect(provider, isNotNull);
      expect(
        provider,
        isNot(isA<MemoryImage>()),
        reason: 'SVG is rasterized, never wrapped as raw MemoryImage bytes',
      );
    });

    test('malformed svg declines to null, never a throw', () async {
      final resolver = await _resolverOver({
        'img/bad.svg': _bytes('not actually svg markup'),
      });
      expect(await resolver('img/bad.svg', 'diagram'), isNull);
    });

    test('a zero-size svg (empty viewBox) declines to null', () async {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 0 0"></svg>';
      final resolver = await _resolverOver({'img/zero.svg': _bytes(svg)});
      expect(await resolver('img/zero.svg', ''), isNull);
    });

    test('an extension outside the allowlist declines', () async {
      final resolver = await _resolverOver({'x.bmp': _bytes('bm')});
      expect(await resolver('x.bmp', ''), isNull);
      expect(await resolver('noext', ''), isNull);
    });

    test('oversize bytes (> 20MB sanity cap) decline', () async {
      final big = Uint8List(NativeImageResolver.maxBytes + 1);
      final atCap = Uint8List(NativeImageResolver.maxBytes);
      final resolver = await _resolverOver({'big.png': big, 'cap.png': atCap});

      expect(await resolver('big.png', ''), isNull);
      // Exactly at the cap is fine — the cap declines only past it.
      expect(await resolver('cap.png', ''), isA<MemoryImage>());
    });

    test('non-relative targets decline WITHOUT touching the vault', () async {
      var reads = 0;
      final resolver = NativeImageResolver(
        resolveBytes: (_) async {
          reads++;
          return _bytes('x');
        },
      );

      expect(await resolver('http://example.com/a.png', ''), isNull);
      expect(await resolver('https://example.com/a.png', ''), isNull);
      expect(await resolver('data:image/png;base64,AAAA', ''), isNull);
      expect(await resolver('/abs/a.png', ''), isNull);
      expect(await resolver('#fragment', ''), isNull);
      expect(await resolver('', ''), isNull);
      expect(reads, 0, reason: 'declined targets must never hit the vault');
    });

    test('a vault miss resolves to null, never a throw', () async {
      final resolver = await _resolverOver({}); // no image files at all
      expect(await resolver('img/missing.png', ''), isNull);
    });

    test('a throwing read resolves to null, never a throw', () async {
      final resolver = NativeImageResolver(
        resolveBytes: (_) => throw StateError('channel down'),
      );
      expect(await resolver('img/x.png', ''), isNull);
    });

    test('a null read resolves to null', () async {
      final resolver = NativeImageResolver(resolveBytes: (_) async => null);
      expect(await resolver('img/x.png', ''), isNull);
    });

    test('tear-offs of one instance compare equal — the identity contract '
        'the plugin memoizes on (an inline closure per build would not)', () {
      final resolver = NativeImageResolver(resolveBytes: (_) async => null);
      final MdvImageResolver a = resolver.call;
      final MdvImageResolver b = resolver.call;
      expect(a == b, isTrue);

      // The anti-pattern, pinned: two closures with identical bodies are
      // NOT equal, which is exactly why the Reader must hold the resolver
      // as a field instead of building one inline per build.
      MdvImageResolver closure() =>
          (url, alt) async => null;
      expect(closure() == closure(), isFalse);
    });
  });

  group('shared target rules (extracted from DocImages, not forked)', () {
    test('looksRelativeTarget matches the webview pre-resolver policy', () {
      expect(DocImages.looksRelativeTarget('img/a.png'), isTrue);
      expect(DocImages.looksRelativeTarget('a.png'), isTrue);
      expect(DocImages.looksRelativeTarget('../up/a.png'), isTrue);
      expect(DocImages.looksRelativeTarget(''), isFalse);
      expect(DocImages.looksRelativeTarget('#frag'), isFalse);
      expect(DocImages.looksRelativeTarget('/abs/a.png'), isFalse);
      expect(DocImages.looksRelativeTarget('http://x/a.png'), isFalse);
      expect(DocImages.looksRelativeTarget('data:image/png;base64,'), isFalse);
      expect(DocImages.looksRelativeTarget('mailto:a@b.c'), isFalse);
    });

    test('extensionOf strips fragment/query and lowercases', () {
      expect(DocImages.extensionOf('a.png'), '.png');
      expect(DocImages.extensionOf('a.PNG'), '.png');
      expect(DocImages.extensionOf('dir/a.jpeg?x=1'), '.jpeg');
      expect(DocImages.extensionOf('a.webp#frag'), '.webp');
      expect(DocImages.extensionOf('noext'), '');
    });

    test('allowsImageExtension covers the mime table exactly', () {
      for (final ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg']) {
        expect(DocImages.allowsImageExtension(ext), isTrue, reason: ext);
      }
      expect(DocImages.allowsImageExtension('.bmp'), isFalse);
      expect(DocImages.allowsImageExtension(''), isFalse);
    });
  });
}
