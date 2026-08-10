import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/render/resolver.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Same device-free fake used by `vault_state_test.dart` — see that file's
/// doc comment.
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

Map<String, dynamic> _imageDoc(List<String> destinations) => {
  'version': 1,
  'kind': 'document',
  'children': [
    {
      'kind': 'paragraph',
      'children': [
        for (final d in destinations)
          {'kind': 'image', 'destination': d, 'alt': ''},
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DocImages.prefetch', () {
    test(
      'resolves a relative image to a data: URI, mime by extension',
      () async {
        final entry = VaultEntry(
          name: 'Doc.md',
          relPath: 'Doc.md',
          isDir: false,
          children: const [],
          source: VaultSource.sample,
        );
        final vault = VaultState(
          sampleProvider: _FakeVaultProvider(
            files: {'Doc.md': _bytes('# x'), 'img/logo.png': _bytes('PNGDATA')},
          ),
          folderProvider: _FakeVaultProvider(),
        );
        await vault.init();

        final images = await DocImages.prefetch(
          _imageDoc(['img/logo.png']),
          (relPath) => vault.resolveRelative(entry, relPath),
        );

        final resolver = images.toResolver();
        final url = resolver(MdvResolveKind.image, 'img/logo.png');
        expect(url, isNotNull);
        expect(url, startsWith('data:image/png;base64,'));
        expect(utf8.decode(base64Decode(url!.split(',').last)), 'PNGDATA');
      },
    );

    test('mime table covers png/jpg/jpeg/gif/webp/svg', () async {
      final entry = VaultEntry(
        name: 'Doc.md',
        relPath: 'Doc.md',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final targets = ['a.png', 'b.jpg', 'c.jpeg', 'd.gif', 'e.webp', 'f.svg'];
      final vault = VaultState(
        sampleProvider: _FakeVaultProvider(
          files: {
            'Doc.md': _bytes('# x'),
            for (final t in targets) t: _bytes('bytes-$t'),
          },
        ),
        folderProvider: _FakeVaultProvider(),
      );
      await vault.init();

      final images = await DocImages.prefetch(
        _imageDoc(targets),
        (relPath) => vault.resolveRelative(entry, relPath),
      );
      final resolver = images.toResolver();

      expect(
        resolver(MdvResolveKind.image, 'a.png'),
        startsWith('data:image/png;'),
      );
      expect(
        resolver(MdvResolveKind.image, 'b.jpg'),
        startsWith('data:image/jpeg;'),
      );
      expect(
        resolver(MdvResolveKind.image, 'c.jpeg'),
        startsWith('data:image/jpeg;'),
      );
      expect(
        resolver(MdvResolveKind.image, 'd.gif'),
        startsWith('data:image/gif;'),
      );
      expect(
        resolver(MdvResolveKind.image, 'e.webp'),
        startsWith('data:image/webp;'),
      );
      expect(
        resolver(MdvResolveKind.image, 'f.svg'),
        startsWith('data:image/svg+xml;'),
      );
    });

    test('declines an unknown extension', () async {
      final entry = VaultEntry(
        name: 'Doc.md',
        relPath: 'Doc.md',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final vault = VaultState(
        sampleProvider: _FakeVaultProvider(
          files: {'Doc.md': _bytes('# x'), 'diagram.pdf': _bytes('PDF')},
        ),
        folderProvider: _FakeVaultProvider(),
      );
      await vault.init();

      final images = await DocImages.prefetch(
        _imageDoc(['diagram.pdf']),
        (relPath) => vault.resolveRelative(entry, relPath),
      );
      expect(images.toResolver()(MdvResolveKind.image, 'diagram.pdf'), isNull);
    });

    test(
      'declines a missing target (VaultState.resolveRelative returns null)',
      () async {
        final entry = VaultEntry(
          name: 'Doc.md',
          relPath: 'Doc.md',
          isDir: false,
          children: const [],
          source: VaultSource.sample,
        );
        final vault = VaultState(
          sampleProvider: _FakeVaultProvider(files: {'Doc.md': _bytes('# x')}),
          folderProvider: _FakeVaultProvider(),
        );
        await vault.init();

        final images = await DocImages.prefetch(
          _imageDoc(['missing.png']),
          (relPath) => vault.resolveRelative(entry, relPath),
        );
        expect(
          images.toResolver()(MdvResolveKind.image, 'missing.png'),
          isNull,
        );
      },
    );

    test(
      'declines a traversal target that would escape the vault root',
      () async {
        final entry = VaultEntry(
          name: 'nested/Doc.md',
          relPath: 'nested/Doc.md',
          isDir: false,
          children: const [],
          source: VaultSource.sample,
        );
        final vault = VaultState(
          sampleProvider: _FakeVaultProvider(
            files: {'nested/Doc.md': _bytes('# x'), 'outside.png': _bytes('X')},
          ),
          folderProvider: _FakeVaultProvider(),
        );
        await vault.init();

        // '../../outside.png' from 'nested/' pops past the vault root.
        final images = await DocImages.prefetch(
          _imageDoc(['../../outside.png']),
          (relPath) => vault.resolveRelative(entry, relPath),
        );
        expect(
          images.toResolver()(MdvResolveKind.image, '../../outside.png'),
          isNull,
        );
      },
    );

    test('declines an over-cap image (> 2MB)', () async {
      final entry = VaultEntry(
        name: 'Doc.md',
        relPath: 'Doc.md',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final huge = Uint8List(DocImages.maxBytes + 1);
      final vault = VaultState(
        sampleProvider: _FakeVaultProvider(
          files: {'Doc.md': _bytes('# x'), 'big.png': huge},
        ),
        folderProvider: _FakeVaultProvider(),
      );
      await vault.init();

      final images = await DocImages.prefetch(
        _imageDoc(['big.png']),
        (relPath) => vault.resolveRelative(entry, relPath),
      );
      expect(images.toResolver()(MdvResolveKind.image, 'big.png'), isNull);
    });

    test('accepts an image exactly at the cap', () async {
      final entry = VaultEntry(
        name: 'Doc.md',
        relPath: 'Doc.md',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final exact = Uint8List(DocImages.maxBytes);
      final vault = VaultState(
        sampleProvider: _FakeVaultProvider(
          files: {'Doc.md': _bytes('# x'), 'exact.png': exact},
        ),
        folderProvider: _FakeVaultProvider(),
      );
      await vault.init();

      final images = await DocImages.prefetch(
        _imageDoc(['exact.png']),
        (relPath) => vault.resolveRelative(entry, relPath),
      );
      expect(images.toResolver()(MdvResolveKind.image, 'exact.png'), isNotNull);
    });

    test(
      'declines absolute, data:, and http(s) targets without ever calling resolveBytes',
      () async {
        var calls = 0;
        final images = await DocImages.prefetch(
          _imageDoc([
            '/etc/passwd.png',
            'data:image/png;base64,QQ==',
            'https://example.com/x.png',
            '#fragment.png',
          ]),
          (relPath) async {
            calls++;
            return _bytes('should not be reached');
          },
        );
        expect(calls, 0);
        final resolver = images.toResolver();
        expect(resolver(MdvResolveKind.image, '/etc/passwd.png'), isNull);
        expect(
          resolver(MdvResolveKind.image, 'data:image/png;base64,QQ=='),
          isNull,
        );
        expect(
          resolver(MdvResolveKind.image, 'https://example.com/x.png'),
          isNull,
        );
        expect(resolver(MdvResolveKind.image, '#fragment.png'), isNull);
      },
    );
  });

  group('DocImages.toResolver', () {
    test(
      'always declines link and wikiLink kinds, even for a resolved image target',
      () async {
        final entry = VaultEntry(
          name: 'Doc.md',
          relPath: 'Doc.md',
          isDir: false,
          children: const [],
          source: VaultSource.sample,
        );
        final vault = VaultState(
          sampleProvider: _FakeVaultProvider(
            files: {'Doc.md': _bytes('# x'), 'img/logo.png': _bytes('PNG')},
          ),
          folderProvider: _FakeVaultProvider(),
        );
        await vault.init();

        final images = await DocImages.prefetch(
          _imageDoc(['img/logo.png']),
          (relPath) => vault.resolveRelative(entry, relPath),
        );
        final resolver = images.toResolver();

        expect(resolver(MdvResolveKind.link, 'img/logo.png'), isNull);
        expect(resolver(MdvResolveKind.wikiLink, 'img/logo.png'), isNull);
        expect(resolver(MdvResolveKind.image, 'img/logo.png'), isNotNull);
      },
    );

    test('empty is a total decline', () {
      final resolver = DocImages.empty.toResolver();
      expect(resolver(MdvResolveKind.image, 'anything.png'), isNull);
    });
  });
}
