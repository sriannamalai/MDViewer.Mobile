import 'package:app/src/vault/vault_grant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultGrant.fromJson', () {
    test('parses a well-formed {id, displayName} map', () {
      final grant = VaultGrant.fromJson({
        'id': 'tree-1',
        'displayName': 'My Docs',
      });
      expect(grant, isNotNull);
      expect(grant!.id, 'tree-1');
      expect(grant.displayName, 'My Docs');
    });

    test('a non-Map top level (e.g. a List, a String, null) returns null', () {
      expect(VaultGrant.fromJson(['not', 'a', 'map']), null);
      expect(VaultGrant.fromJson('just a string'), null);
      expect(VaultGrant.fromJson(null), null);
      expect(VaultGrant.fromJson(42), null);
    });

    test(
      'a wrong-typed id (e.g. a number instead of a String) returns null',
      () {
        expect(
          VaultGrant.fromJson({'id': 123, 'displayName': 'My Docs'}),
          null,
        );
      },
    );

    test('a missing id returns null', () {
      expect(VaultGrant.fromJson({'displayName': 'My Docs'}), null);
    });

    test('an empty-string id returns null', () {
      expect(VaultGrant.fromJson({'id': '', 'displayName': 'My Docs'}), null);
    });

    test('a wrong-typed displayName (e.g. a number) returns null', () {
      expect(VaultGrant.fromJson({'id': 'tree-1', 'displayName': 42}), null);
    });

    test('a missing displayName returns null', () {
      expect(VaultGrant.fromJson({'id': 'tree-1'}), null);
    });

    test('an empty-string displayName returns null', () {
      expect(VaultGrant.fromJson({'id': 'tree-1', 'displayName': ''}), null);
    });

    test('an empty map returns null', () {
      expect(VaultGrant.fromJson(<String, dynamic>{}), null);
    });

    test('round-trips through toJson', () {
      const grant = VaultGrant(id: 'tree-1', displayName: 'My Docs');
      expect(VaultGrant.fromJson(grant.toJson()), isNotNull);
      expect(VaultGrant.fromJson(grant.toJson())!.id, grant.id);
      expect(
        VaultGrant.fromJson(grant.toJson())!.displayName,
        grant.displayName,
      );
    });
  });
}
