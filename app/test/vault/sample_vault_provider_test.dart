import 'dart:convert';

import 'package:app/src/vault/sample_vault_provider.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_index.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const provider = SampleVaultProvider();

  test('list() returns the fixed Markdown path set, unindexed', () async {
    final paths = await provider.list(SampleVaultProvider.grant);
    expect(paths, SampleVaultProvider.mdRelPaths);
  });

  test(
    'the sample vault indexes into a nested folder plus top-level docs',
    () async {
      final paths = await provider.list(SampleVaultProvider.grant);
      final entries = VaultIndex.build(paths, VaultSource.sample);

      expect(entries.where((e) => e.isDir).map((e) => e.name).toList(), [
        'Notes',
      ]);
      final notes = entries.firstWhere((e) => e.name == 'Notes');
      expect(notes.mdCount, 2);
      expect(notes.children.map((e) => e.name).toList(), [
        'Ideas.md',
        'Project Plan.md',
      ]);

      final topLevelFiles = entries
          .where((e) => !e.isDir)
          .map((e) => e.name)
          .toList();
      expect(topLevelFiles, contains('Welcome.md'));
      expect(topLevelFiles, contains('Getting Started.md'));
      expect(topLevelFiles, contains('Colophon.md'));
    },
  );

  test('every listed Markdown file actually loads as an asset', () async {
    for (final relPath in SampleVaultProvider.mdRelPaths) {
      final entry = VaultEntry(
        name: relPath.split('/').last,
        relPath: relPath,
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final bytes = await provider.read(entry);
      expect(bytes, isNotEmpty, reason: '$relPath should not be empty');
    }
  });

  test(
    'Welcome.md is the rich doc: mermaid, KaTeX inline+block, a Go fence, a relative image, a wiki-link, and a task list',
    () async {
      const entry = VaultEntry(
        name: 'Welcome.md',
        relPath: 'Welcome.md',
        isDir: false,
        children: [],
        source: VaultSource.sample,
      );
      final bytes = await provider.read(entry);
      final content = utf8.decode(bytes);

      expect(content, contains('```mermaid'), reason: 'mermaid diagram fence');
      expect(content, contains(r'$x = \frac{-b'), reason: 'inline KaTeX');
      expect(content, contains(r'$$'), reason: 'block KaTeX delimiters');
      expect(content, contains('```go'), reason: 'Go code fence');
      expect(
        content,
        contains('![MarkDownViewer logo](img/logo.png)'),
        reason: 'relative image',
      );
      expect(content, contains('[[Getting Started]]'), reason: 'wiki-link');
      expect(content, contains('- [x]'), reason: 'a checked task-list item');
      expect(content, contains('- [ ]'), reason: 'an unchecked task-list item');
    },
  );

  test(
    'the bundled logo.png the rich doc links to is readable and non-empty',
    () async {
      const entry = VaultEntry(
        name: 'logo.png',
        relPath: 'img/logo.png',
        isDir: false,
        children: [],
        source: VaultSource.sample,
      );
      final bytes = await provider.read(entry);
      expect(bytes.length, greaterThan(0));
      // PNG magic bytes.
      expect(bytes.sublist(0, 8), [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
    },
  );

  test(
    'reading a missing path throws rather than returning empty bytes',
    () async {
      const entry = VaultEntry(
        name: 'nope.md',
        relPath: 'nope.md',
        isDir: false,
        children: [],
        source: VaultSource.sample,
      );
      expect(() => provider.read(entry), throwsA(anything));
    },
  );

  test('pickFolder() is unsupported — the sample vault can\'t be picked', () {
    expect(() => provider.pickFolder(), throwsUnsupportedError);
  });

  test(
    'restore() always succeeds — the sample vault needs no re-authorization',
    () async {
      expect(await provider.restore(SampleVaultProvider.grant), true);
    },
  );
}
