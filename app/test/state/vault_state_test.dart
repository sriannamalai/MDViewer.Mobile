import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/state/vault_state.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A device-free stand-in for the platform channel / asset-bundle
/// providers, so VaultState's orchestration logic (recents, grant
/// persistence, resolveRelative's traversal guard) is testable without a
/// simulator/emulator. The real channel behavior is device-E2E'd
/// separately (see the task-2 report).
class FakeVaultProvider implements VaultProvider {
  FakeVaultProvider({
    this.pickResult,
    this.restoreResult = true,
    Map<String, Uint8List>? files,
  }) : files = files ?? {};

  VaultGrant? pickResult;
  bool restoreResult;
  final Map<String, Uint8List> files;

  @override
  Future<VaultGrant?> pickFolder() async => pickResult;

  @override
  Future<bool> restore(VaultGrant grant) async => restoreResult;

  @override
  Future<List<String>> list(VaultGrant grant) async => files.keys
      .where(
        (p) =>
            p.toLowerCase().endsWith('.md') ||
            p.toLowerCase().endsWith('.markdown'),
      )
      .toList();

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final bytes = files[entry.relPath];
    if (bytes == null) throw StateError('not found: ${entry.relPath}');
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VaultState.init', () {
    test(
      'populates sampleEntries always; entries stay empty without a persisted grant',
      () async {
        final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
        final state = VaultState(
          sampleProvider: sample,
          folderProvider: FakeVaultProvider(),
        );

        expect(state.ready, false);
        await state.init();

        expect(state.ready, true);
        expect(state.sampleEntries.map((e) => e.name), contains('Welcome.md'));
        expect(state.entries, isEmpty);
        expect(state.vaultName, null);
        expect(state.recents, isEmpty);
      },
    );

    test('restores a persisted grant that still resolves', () async {
      SharedPreferences.setMockInitialValues({
        'vault.grant': jsonEncode({'id': 'tree-1', 'displayName': 'My Docs'}),
      });
      final folder = FakeVaultProvider(
        restoreResult: true,
        files: {'A.md': _bytes('a')},
      );
      final state = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: folder,
      );

      await state.init();

      expect(state.vaultName, 'My Docs');
      expect(state.entries.map((e) => e.name), ['A.md']);
    });

    test(
      'a stale/revoked persisted grant is dropped, not retried blindly',
      () async {
        SharedPreferences.setMockInitialValues({
          'vault.grant': jsonEncode({'id': 'tree-1', 'displayName': 'My Docs'}),
        });
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: FakeVaultProvider(restoreResult: false),
        );

        await state.init();

        expect(state.vaultName, null);
        expect(state.entries, isEmpty);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('vault.grant'), null);
      },
    );

    test(
      'a corrupt persisted grant blob degrades to "no grant", not a crash',
      () async {
        SharedPreferences.setMockInitialValues({'vault.grant': '{not json'});
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: FakeVaultProvider(),
        );

        await expectLater(state.init(), completes);
        expect(state.vaultName, null);
      },
    );
  });

  group('VaultState.pickFolder', () {
    test(
      'a successful pick sets the grant, loads entries, and persists',
      () async {
        final folder = FakeVaultProvider(
          pickResult: const VaultGrant(id: 'tree-2', displayName: 'Notes'),
          files: {'One.md': _bytes('1')},
        );
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: folder,
        );
        await state.init();

        final ok = await state.pickFolder();

        expect(ok, true);
        expect(state.vaultName, 'Notes');
        expect(state.entries.map((e) => e.name), ['One.md']);

        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString('vault.grant')!), {
          'id': 'tree-2',
          'displayName': 'Notes',
        });
      },
    );

    test('a cancelled pick (null grant) leaves state unchanged', () async {
      final state = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(pickResult: null),
      );
      await state.init();

      final ok = await state.pickFolder();

      expect(ok, false);
      expect(state.vaultName, null);
      expect(state.entries, isEmpty);
    });
  });

  group('VaultState.readDoc — recents', () {
    test('reading a doc adds it to recents and persists', () async {
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final state = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final entry = state.sampleEntries.firstWhere(
        (e) => e.name == 'Welcome.md',
      );
      final bytes = await state.readDoc(entry);

      expect(utf8.decode(bytes), '# hi');
      expect(state.recents.single.relPath, 'Welcome.md');
      expect(state.recents.single.source, VaultSource.sample);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vault.recents'), isNotNull);
    });

    test(
      'recents persist across a fresh VaultState reading the same prefs',
      () async {
        final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
        final first = VaultState(
          sampleProvider: sample,
          folderProvider: FakeVaultProvider(),
        );
        await first.init();
        await first.readDoc(
          first.sampleEntries.firstWhere((e) => e.name == 'Welcome.md'),
        );

        final second = VaultState(
          sampleProvider: sample,
          folderProvider: FakeVaultProvider(),
        );
        await second.init();

        expect(second.recents.single.relPath, 'Welcome.md');
      },
    );
  });

  group('VaultState.resolveRelative', () {
    test('resolves and reads a sibling image from the same source', () async {
      final sample = FakeVaultProvider(
        files: {
          'Welcome.md': _bytes('# hi'),
          'img/logo.png': Uint8List.fromList([1, 2, 3]),
        },
      );
      final state = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final welcome = state.sampleEntries.firstWhere(
        (e) => e.name == 'Welcome.md',
      );
      final bytes = await state.resolveRelative(welcome, 'img/logo.png');

      expect(bytes, [1, 2, 3]);
    });

    test(
      'a path that would escape the vault root resolves to null, never throws',
      () async {
        final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
        final state = VaultState(
          sampleProvider: sample,
          folderProvider: FakeVaultProvider(),
        );
        await state.init();

        final welcome = state.sampleEntries.firstWhere(
          (e) => e.name == 'Welcome.md',
        );

        await expectLater(
          state.resolveRelative(welcome, '../../../etc/passwd'),
          completion(null),
        );
      },
    );

    test(
      'a missing (but in-bounds) target resolves to null, not a thrown exception',
      () async {
        final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
        final state = VaultState(
          sampleProvider: sample,
          folderProvider: FakeVaultProvider(),
        );
        await state.init();

        final welcome = state.sampleEntries.firstWhere(
          (e) => e.name == 'Welcome.md',
        );

        await expectLater(
          state.resolveRelative(welcome, 'img/does-not-exist.png'),
          completion(null),
        );
      },
    );
  });

  group('VaultState.readRaw', () {
    test('reads bytes without touching Recents', () async {
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final state = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final entry = state.sampleEntries.firstWhere(
        (e) => e.name == 'Welcome.md',
      );
      final bytes = await state.readRaw(entry);

      expect(utf8.decode(bytes), '# hi');
      expect(state.recents, isEmpty);
    });
  });

  group('VaultState.openSingleFile — open-with', () {
    test('registers an openedFile entry that readDoc can then read', () async {
      final state = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final entry = state.openSingleFile(
        name: 'Shared.md',
        bytes: _bytes('# shared doc'),
      );

      expect(entry.source, VaultSource.openedFile);
      expect(entry.relPath, 'Shared.md');
      expect(entry.isDir, false);

      final bytes = await state.readDoc(entry);
      expect(utf8.decode(bytes), '# shared doc');
      // readDoc's usual Recents recording still applies to an opened file.
      expect(state.recents.single.relPath, 'Shared.md');
      expect(state.recents.single.source, VaultSource.openedFile);
    });

    test(
      'resolveRelative always declines for an opened file — no folder behind it',
      () async {
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: FakeVaultProvider(),
        );
        await state.init();

        final entry = state.openSingleFile(
          name: 'Shared.md',
          bytes: _bytes('![x](img/logo.png)'),
        );

        await expectLater(
          state.resolveRelative(entry, 'img/logo.png'),
          completion(null),
        );
      },
    );

    test('opening a second file replaces the first', () async {
      final state = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final first = state.openSingleFile(name: 'One.md', bytes: _bytes('1'));
      state.openSingleFile(name: 'Two.md', bytes: _bytes('2'));

      await expectLater(state.readDoc(first), throwsA(anything));
    });
  });

  group('VaultState.findByRelPath — openedFile', () {
    test('resolves an openedFile recent back to the held file', () async {
      final state = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(),
      );
      await state.init();

      final entry = state.openSingleFile(
        name: 'Shared.md',
        bytes: _bytes('# shared doc'),
      );

      final found = state.findByRelPath(VaultSource.openedFile, 'Shared.md');
      expect(found, isNotNull);
      expect(found!.relPath, entry.relPath);
      expect(found.source, VaultSource.openedFile);
    });

    test(
      'does NOT resolve to an unrelated same-named file in the folder vault',
      () async {
        // A folder vault that happens to contain a file with the exact
        // same relPath as the currently-open single file — the bug this
        // regresses against would have returned the folder's "Shared.md"
        // (or, before that, silently missed forever) instead of correctly
        // distinguishing the two by source.
        final folder = FakeVaultProvider(
          files: {'Shared.md': _bytes('unrelated folder document')},
        );
        SharedPreferences.setMockInitialValues({
          'vault.grant': jsonEncode({'id': 'g1', 'displayName': 'My Docs'}),
        });
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: folder,
        );
        await state.init();

        state.openSingleFile(name: 'Shared.md', bytes: _bytes('opened doc'));

        // The folder lookup still finds its own (different) document...
        final folderMatch = state.findByRelPath(
          VaultSource.folder,
          'Shared.md',
        );
        expect(folderMatch, isNotNull);
        // ...while the openedFile lookup returns the held file's bytes'
        // source, never silently falling through to the folder tree.
        final openedMatch = state.findByRelPath(
          VaultSource.openedFile,
          'Shared.md',
        );
        expect(openedMatch, isNotNull);
        expect(openedMatch!.source, VaultSource.openedFile);

        final openedBytes = await state.readDoc(openedMatch);
        expect(utf8.decode(openedBytes), 'opened doc');
      },
    );

    test(
      'a vanished opened-file recent (nothing opened yet, or replaced since) drops gracefully',
      () async {
        final state = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: FakeVaultProvider(),
        );
        await state.init();

        // Nothing opened yet this app run.
        expect(state.findByRelPath(VaultSource.openedFile, 'Old.md'), isNull);

        // A different file has since replaced whatever "Old.md" was.
        state.openSingleFile(name: 'New.md', bytes: _bytes('new'));
        expect(state.findByRelPath(VaultSource.openedFile, 'Old.md'), isNull);
      },
    );
  });
}
