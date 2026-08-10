import 'package:app/src/vault/vault_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultPath.resolve', () {
    test('resolves a same-directory relative path', () {
      expect(VaultPath.resolve('Welcome.md', 'img/logo.png'), 'img/logo.png');
    });

    test('resolves against a nested document\'s own directory', () {
      expect(
        VaultPath.resolve('docs/Design.md', 'img/logo.png'),
        'docs/img/logo.png',
      );
    });

    test('a leading ./ is a no-op', () {
      expect(
        VaultPath.resolve('docs/Design.md', './img/logo.png'),
        'docs/img/logo.png',
      );
    });

    test(
      '.. climbs out of the current directory, staying inside the vault',
      () {
        expect(
          VaultPath.resolve('docs/nested/Sub.md', '../img/logo.png'),
          'docs/img/logo.png',
        );
      },
    );

    test('.. from a root-level document escapes the vault root -> null', () {
      expect(VaultPath.resolve('Welcome.md', '../secrets.md'), null);
    });

    test(
      'two .. from a one-level-deep document escapes the vault root -> null',
      () {
        expect(VaultPath.resolve('docs/Design.md', '../../secrets.md'), null);
      },
    );

    test(
      'many .. beyond the root still just escapes -> null (not a crash)',
      () {
        expect(
          VaultPath.resolve('docs/Design.md', '../../../../../../secrets.md'),
          null,
        );
      },
    );

    test('an absolute-looking target is rejected outright', () {
      expect(VaultPath.resolve('docs/Design.md', '/etc/passwd'), null);
    });

    test('an empty target is rejected', () {
      expect(VaultPath.resolve('docs/Design.md', ''), null);
    });

    test(
      'resolving to exactly the vault root (all segments consumed) -> null',
      () {
        // '.' alone never contributes a segment, so this is really "no target".
        expect(VaultPath.resolve('Welcome.md', '.'), null);
      },
    );

    test('a deeply nested source resolves multiple levels down cleanly', () {
      expect(
        VaultPath.resolve('a/b/c/Doc.md', 'x/y/img.png'),
        'a/b/c/x/y/img.png',
      );
    });
  });
}
