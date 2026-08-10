import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_index.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultIndex.build ordering', () {
    test('folders sort before files at the same level', () {
      final entries = VaultIndex.build([
        'README.md',
        'docs/Design.md',
      ], VaultSource.folder);
      expect(entries.map((e) => e.name).toList(), ['docs', 'README.md']);
      expect(entries[0].isDir, true);
      expect(entries[1].isDir, false);
    });

    test('sorting is alphabetical and case-insensitive within each group', () {
      final entries = VaultIndex.build([
        'zeta/Z.md',
        'Alpha/A.md',
        'readme.md',
        'CHANGELOG.md',
      ], VaultSource.folder);

      expect(entries.where((e) => e.isDir).map((e) => e.name).toList(), [
        'Alpha',
        'zeta',
      ]);
      expect(entries.where((e) => !e.isDir).map((e) => e.name).toList(), [
        'CHANGELOG.md',
        'readme.md',
      ]);
    });

    test('nesting applies the same folders-first-alpha rule recursively', () {
      final entries = VaultIndex.build([
        'docs/zeta.md',
        'docs/Alpha/inner.md',
        'docs/README.md',
      ], VaultSource.folder);

      final docs = entries.single;
      expect(docs.name, 'docs');
      expect(docs.children.map((e) => e.name).toList(), [
        'Alpha',
        'README.md',
        'zeta.md',
      ]);
    });

    test('every entry carries the given source', () {
      final entries = VaultIndex.build(['docs/a.md'], VaultSource.sample);
      expect(entries.single.source, VaultSource.sample);
      expect(entries.single.children.single.source, VaultSource.sample);
    });

    test(
      'relPath is rebuilt "/"-joined from the segments, not the raw input',
      () {
        final entries = VaultIndex.build(['a/b/c.md'], VaultSource.folder);
        expect(entries.single.relPath, 'a');
        expect(entries.single.children.single.relPath, 'a/b');
        expect(
          entries.single.children.single.children.single.relPath,
          'a/b/c.md',
        );
      },
    );

    test('a path with empty/redundant segments is ignored gracefully', () {
      final entries = VaultIndex.build([
        '',
        '/a.md',
        'b.md',
      ], VaultSource.folder);
      // '' contributes nothing; '/a.md' has one non-empty segment "a.md".
      expect(entries.map((e) => e.name).toList(), ['a.md', 'b.md']);
    });
  });

  group('VaultIndex.build mdCount (recursive Markdown descendant count)', () {
    test('a leaf directory\'s count is its direct file count', () {
      final entries = VaultIndex.build([
        'docs/a.md',
        'docs/b.md',
      ], VaultSource.folder);
      expect(entries.single.mdCount, 2);
    });

    test('a directory\'s count includes files nested arbitrarily deep', () {
      final entries = VaultIndex.build([
        'third_party/README.md',
        'third_party/CHANGELOG.md',
        'third_party/vendor/a.md',
        'third_party/vendor/b.md',
        'third_party/vendor/nested/c.md',
      ], VaultSource.folder);

      final thirdParty = entries.single;
      expect(thirdParty.mdCount, 5);
      final vendor = thirdParty.children.firstWhere((e) => e.name == 'vendor');
      expect(vendor.mdCount, 3);
    });

    test('files (non-directories) always report mdCount 0', () {
      final entries = VaultIndex.build(['a.md'], VaultSource.folder);
      expect(entries.single.mdCount, 0);
    });

    test('an empty input list produces an empty tree', () {
      expect(VaultIndex.build(const [], VaultSource.folder), isEmpty);
    });
  });

  group('VaultEntry.isMarkdown', () {
    test('.md and .markdown are recognized case-insensitively', () {
      const md = VaultEntry(
        name: 'a.MD',
        relPath: 'a.MD',
        isDir: false,
        children: [],
        source: VaultSource.folder,
      );
      const markdown = VaultEntry(
        name: 'b.Markdown',
        relPath: 'b.Markdown',
        isDir: false,
        children: [],
        source: VaultSource.folder,
      );
      const other = VaultEntry(
        name: 'c.txt',
        relPath: 'c.txt',
        isDir: false,
        children: [],
        source: VaultSource.folder,
      );
      expect(md.isMarkdown, true);
      expect(markdown.isMarkdown, true);
      expect(other.isMarkdown, false);
    });

    test('a directory is never markdown even if its name ends in .md', () {
      const dir = VaultEntry(
        name: 'weird.md',
        relPath: 'weird.md',
        isDir: true,
        children: [],
        source: VaultSource.folder,
      );
      expect(dir.isMarkdown, false);
    });
  });
}
