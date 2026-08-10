// VaultSearch unit tests (task-7-brief.md): case-sensitivity, regex,
// whole-word, snippet extraction, 1-based line numbers, the result cap,
// invalid-regex handling (never throws), and cancellation. Pure Dart — no
// platform channel, no device.

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/vault/search.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

VaultEntry _entry(String relPath) => VaultEntry(
  name: relPath.split('/').last,
  relPath: relPath,
  isDir: false,
  children: const [],
  source: VaultSource.sample,
);

Future<Uint8List> Function(VaultEntry) _reader(Map<String, String> files) {
  return (entry) async {
    final content = files[entry.relPath];
    if (content == null) throw StateError('not found: ${entry.relPath}');
    return _bytes(content);
  };
}

void main() {
  group('VaultSearch.search — basics', () {
    test(
      'an empty query returns SearchResult.empty without reading files',
      () async {
        var reads = 0;
        final result = await VaultSearch.search(
          query: '',
          entries: [_entry('A.md')],
          readBytes: (entry) async {
            reads++;
            return _bytes('resolver');
          },
        );

        expect(result.matches, isEmpty);
        expect(result.fileCount, 0);
        expect(result.capped, false);
        expect(reads, 0);
      },
    );

    test('finds a case-insensitive substring match by default', () async {
      final files = {'README.md': 'Hosts that need a Resolver can supply one.'};
      final result = await VaultSearch.search(
        query: 'resolver',
        entries: [_entry('README.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.entry.relPath, 'README.md');
      expect(result.fileCount, 1);
    });

    test('reports 1-based line numbers', () async {
      final files = {'A.md': 'line one\nline two\nfind me here\n'};
      final result = await VaultSearch.search(
        query: 'find me',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
      );

      expect(result.matches.single.line, 3);
    });

    test('matches across multiple files, counting distinct files', () async {
      final files = {
        'A.md': 'the target word',
        'B.md': 'another target here',
        'C.md': 'nothing relevant',
      };
      final result = await VaultSearch.search(
        query: 'target',
        entries: [_entry('A.md'), _entry('B.md'), _entry('C.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(2));
      expect(result.fileCount, 2);
    });

    test('an unreadable file is skipped, not a failed search', () async {
      final result = await VaultSearch.search(
        query: 'anything',
        entries: [_entry('Missing.md')],
        readBytes: (entry) async => throw StateError('boom'),
      );

      expect(result.matches, isEmpty);
      expect(result.error, isNull);
    });

    test(
      'directories and non-Markdown entries in the list are ignored',
      () async {
        final dir = VaultEntry(
          name: 'docs',
          relPath: 'docs',
          isDir: true,
          children: const [],
          source: VaultSource.sample,
        );
        final notMd = VaultEntry(
          name: 'image.png',
          relPath: 'image.png',
          isDir: false,
          children: const [],
          source: VaultSource.sample,
        );

        var reads = 0;
        final result = await VaultSearch.search(
          query: 'anything',
          entries: [dir, notMd],
          readBytes: (entry) async {
            reads++;
            return _bytes('');
          },
        );

        expect(reads, 0);
        expect(result.matches, isEmpty);
      },
    );
  });

  group('VaultSearch.search — filters', () {
    test('caseSensitive: true rejects a differently-cased match', () async {
      final files = {'A.md': 'Resolver, not resolver'};
      final result = await VaultSearch.search(
        query: 'Resolver',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
        filters: const SearchFilters(caseSensitive: true),
      );

      expect(result.matches, hasLength(1));
    });

    test('regex: true treats the query as a pattern', () async {
      final files = {'A.md': 'cat123 dog456 fish789'};
      final result = await VaultSearch.search(
        query: r'[a-z]+\d+',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
        filters: const SearchFilters(regex: true),
      );

      expect(result.matches, hasLength(3));
    });

    test('regex: false escapes special characters (literal match)', () async {
      final files = {'A.md': 'a[b] literal brackets, not a class'};
      final result = await VaultSearch.search(
        query: 'a[b]',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(1));
    });

    test('wholeWord: true excludes a substring-only occurrence', () async {
      final files = {'A.md': 'catalog vs cat'};
      final result = await VaultSearch.search(
        query: 'cat',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
        filters: const SearchFilters(wholeWord: true),
      );

      expect(result.matches, hasLength(1));
      // Anchored at the standalone "cat" near the end, not "catalog"'s
      // leading substring.
      final m = result.matches.single;
      expect(m.snippet.substring(m.matchStart, m.matchEnd), 'cat');
    });

    test('wholeWord: false matches a substring inside a longer word', () async {
      final files = {'A.md': 'catalog'};
      final result = await VaultSearch.search(
        query: 'cat',
        entries: [_entry('A.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(1));
    });

    test('an invalid regex pattern returns an error, never throws', () async {
      final result = await VaultSearch.search(
        query: '(unclosed',
        entries: [_entry('A.md')],
        readBytes: (entry) async => throw StateError('should not be read'),
        filters: const SearchFilters(regex: true),
      );

      expect(result.error, isNotNull);
      expect(result.matches, isEmpty);
    });
  });

  group('VaultSearch.search — snippets', () {
    test(
      'the matched substring offsets index correctly into the snippet',
      () async {
        final files = {'A.md': 'the quick brown fox jumps over the lazy dog'};
        final result = await VaultSearch.search(
          query: 'fox',
          entries: [_entry('A.md')],
          readBytes: _reader(files),
        );

        final m = result.matches.single;
        expect(m.snippet.substring(m.matchStart, m.matchEnd), 'fox');
      },
    );

    test(
      'a long line is windowed down to roughly snippetWindow chars',
      () async {
        final long = 'x' * 500;
        final line = '${long}TARGET$long';
        final result = await VaultSearch.search(
          query: 'TARGET',
          entries: [_entry('A.md')],
          readBytes: _reader({'A.md': line}),
        );

        final m = result.matches.single;
        expect(
          m.snippet.length,
          lessThanOrEqualTo(VaultSearch.snippetWindow + 1),
        );
        expect(m.snippet.substring(m.matchStart, m.matchEnd), 'TARGET');
      },
    );

    test('a short line (shorter than the window) is returned whole', () async {
      final result = await VaultSearch.search(
        query: 'hi',
        entries: [_entry('A.md')],
        readBytes: _reader({'A.md': 'hi there'}),
      );

      expect(result.matches.single.snippet, 'hi there');
    });

    test(
      'a match near the very start of a long line still fits its window',
      () async {
        final line = 'TARGET${'y' * 500}';
        final result = await VaultSearch.search(
          query: 'TARGET',
          entries: [_entry('A.md')],
          readBytes: _reader({'A.md': line}),
        );

        final m = result.matches.single;
        expect(m.matchStart, 0);
        expect(m.snippet.substring(0, 6), 'TARGET');
      },
    );
  });

  group('VaultSearch.search — cap', () {
    test('stops at resultCap and marks the result as capped', () async {
      final lines = List.generate(VaultSearch.resultCap + 50, (i) => 'hit $i');
      final files = {'Big.md': lines.join('\n')};

      final result = await VaultSearch.search(
        query: 'hit',
        entries: [_entry('Big.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(VaultSearch.resultCap));
      expect(result.capped, true);
    });

    test('exactly resultCap matches is not marked capped', () async {
      final lines = List.generate(VaultSearch.resultCap, (i) => 'hit $i');
      final files = {'Big.md': lines.join('\n')};

      final result = await VaultSearch.search(
        query: 'hit',
        entries: [_entry('Big.md')],
        readBytes: _reader(files),
      );

      expect(result.matches, hasLength(VaultSearch.resultCap));
      expect(result.capped, false);
    });
  });

  group('VaultSearch.search — cancellation', () {
    test('a cancelled search stops scanning further files', () async {
      final files = {
        'A.md': 'target one',
        'B.md': 'target two',
        'C.md': 'target three',
      };
      var filesRead = 0;

      final result = await VaultSearch.search(
        query: 'target',
        entries: [_entry('A.md'), _entry('B.md'), _entry('C.md')],
        readBytes: (entry) async {
          filesRead++;
          return _bytes(files[entry.relPath]!);
        },
        // Cancel after the very first file has been scanned.
        isCancelled: () => filesRead >= 1,
      );

      expect(filesRead, 1);
      expect(result.matches, hasLength(1));
    });
  });

  group('VaultSearch.flattenMarkdownFiles', () {
    test('flattens nested directories to their Markdown leaves only', () {
      final image = VaultEntry(
        name: 'logo.png',
        relPath: 'img/logo.png',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final nested = VaultEntry(
        name: 'Nested.md',
        relPath: 'docs/Nested.md',
        isDir: false,
        children: const [],
        source: VaultSource.sample,
      );
      final imgDir = VaultEntry(
        name: 'img',
        relPath: 'img',
        isDir: true,
        children: [image],
        source: VaultSource.sample,
      );
      final docsDir = VaultEntry(
        name: 'docs',
        relPath: 'docs',
        isDir: true,
        children: [nested],
        source: VaultSource.sample,
      );
      final root = _entry('README.md');

      final flat = VaultSearch.flattenMarkdownFiles([root, docsDir, imgDir]);

      expect(flat.map((e) => e.relPath), ['README.md', 'docs/Nested.md']);
    });
  });
}
