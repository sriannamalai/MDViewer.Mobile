import 'dart:convert';

import 'package:app/src/vault/recent_entry.dart';
import 'package:app/src/vault/recents_store.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';

RecentEntry _entry(
  String relPath, {
  VaultSource source = VaultSource.folder,
  int at = 0,
}) => RecentEntry(relPath: relPath, source: source, openedAtMs: at);

void main() {
  group('RecentsStore.add (cap + dedupe)', () {
    test('pushes a new entry to the front', () {
      final result = RecentsStore.add([
        _entry('a.md', at: 1),
      ], _entry('b.md', at: 2));
      expect(result.map((e) => e.relPath).toList(), ['b.md', 'a.md']);
    });

    test(
      're-opening an existing entry moves it to the front instead of duplicating it',
      () {
        final existing = [
          _entry('a.md', at: 1),
          _entry('b.md', at: 2),
          _entry('c.md', at: 3),
        ];
        final result = RecentsStore.add(existing, _entry('a.md', at: 4));
        expect(result.map((e) => e.relPath).toList(), ['a.md', 'b.md', 'c.md']);
        expect(result.length, 3);
      },
    );

    test(
      'dedupe keys on (relPath, source) — same path in a different vault is a distinct entry',
      () {
        final existing = [_entry('a.md', source: VaultSource.sample, at: 1)];
        final result = RecentsStore.add(
          existing,
          _entry('a.md', source: VaultSource.folder, at: 2),
        );
        expect(result.length, 2);
      },
    );

    test('caps at 8, dropping the oldest', () {
      var recents = <RecentEntry>[];
      for (var i = 0; i < 10; i++) {
        recents = RecentsStore.add(recents, _entry('file$i.md', at: i));
      }
      expect(recents.length, RecentsStore.cap);
      expect(recents.first.relPath, 'file9.md');
      expect(recents.map((e) => e.relPath), isNot(contains('file0.md')));
      expect(recents.map((e) => e.relPath), isNot(contains('file1.md')));
    });

    test('does not mutate the list passed in', () {
      final existing = [_entry('a.md', at: 1)];
      RecentsStore.add(existing, _entry('b.md', at: 2));
      expect(existing.length, 1);
    });
  });

  group('RecentsStore.decode / sanitize — corrupt input handling', () {
    test('round-trips a well-formed list through encode/decode', () {
      final recents = [
        _entry('a.md', source: VaultSource.sample, at: 111),
        _entry('b.md', at: 222),
      ];
      final decoded = RecentsStore.decode(RecentsStore.encode(recents));
      expect(decoded, recents);
    });

    test('unparseable JSON text falls back to an empty list, not a throw', () {
      expect(() => RecentsStore.decode('{not valid json'), returnsNormally);
      expect(RecentsStore.decode('{not valid json'), isEmpty);
    });

    test(
      'valid JSON but the wrong top-level shape (an object, not a list) -> empty list',
      () {
        expect(RecentsStore.decode(jsonEncode({'oops': true})), isEmpty);
      },
    );

    test('a list of non-objects is dropped entirely, not crashed on', () {
      expect(RecentsStore.decode(jsonEncode([1, 'two', null, true])), isEmpty);
    });

    test(
      'an entry missing relPath is dropped; well-formed siblings survive',
      () {
        final raw = jsonEncode([
          {'source': 'folder', 'openedAtMs': 1},
          {'relPath': 'ok.md', 'source': 'folder', 'openedAtMs': 2},
        ]);
        final decoded = RecentsStore.decode(raw);
        expect(decoded.length, 1);
        expect(decoded.single.relPath, 'ok.md');
      },
    );

    test('an entry with an empty relPath is dropped', () {
      final raw = jsonEncode([
        {'relPath': '', 'source': 'folder', 'openedAtMs': 1},
      ]);
      expect(RecentsStore.decode(raw), isEmpty);
    });

    test(
      'an entry with an unknown source name is dropped (no fabricated default)',
      () {
        final raw = jsonEncode([
          {'relPath': 'a.md', 'source': 'cloud-drive', 'openedAtMs': 1},
        ]);
        expect(RecentsStore.decode(raw), isEmpty);
      },
    );

    test(
      'a missing/invalid openedAtMs defaults to 0 rather than dropping the entry',
      () {
        final raw = jsonEncode([
          {'relPath': 'a.md', 'source': 'folder'},
          {'relPath': 'b.md', 'source': 'folder', 'openedAtMs': 'not-a-number'},
          {'relPath': 'c.md', 'source': 'folder', 'openedAtMs': -5},
        ]);
        final decoded = RecentsStore.decode(raw);
        expect(decoded.map((e) => e.openedAtMs).toList(), [0, 0, 0]);
      },
    );

    test('an oversized persisted list is truncated to the cap', () {
      final raw = jsonEncode(
        List.generate(
          20,
          (i) => {'relPath': 'f$i.md', 'source': 'folder', 'openedAtMs': i},
        ),
      );
      expect(RecentsStore.decode(raw).length, RecentsStore.cap);
    });
  });
}
