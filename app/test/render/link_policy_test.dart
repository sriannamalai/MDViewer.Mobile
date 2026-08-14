import 'package:app/src/render/link_policy.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `reader_test.dart`'s webview navigation-policy cases
/// test-for-test (plus the internal-`.md` stripping rules from
/// `_openInternalRelative`), so the native engine's pure decision table
/// and the webview delegate can never drift silently. Every case runs on
/// BOTH platforms: v2's table is platform-uniform by design — the one
/// v1 platform split (Android's internal-nav no-op) is retired.
void main() {
  const platforms = [TargetPlatform.android, TargetPlatform.iOS];

  group('external (http/https)', () {
    test('http and https launch externally on BOTH platforms', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('https://example.com/a?b=1#c', platform: platform),
          LinkExternal(Uri.parse('https://example.com/a?b=1#c')),
        );
        expect(
          decideLinkTap('http://example.com', platform: platform),
          LinkExternal(Uri.parse('http://example.com')),
        );
      }
    });

    test('scheme matching is case-insensitive (Uri normalizes the scheme)', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('HTTPS://EXAMPLE.COM/Doc', platform: platform),
          isA<LinkExternal>(),
        );
      }
    });
  });

  group('internal relative .md', () {
    test('.md and .markdown targets open in-app on BOTH platforms '
        '(the Android no-op is retired)', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('Other.md', platform: platform),
          const LinkInternalMd('Other.md'),
        );
        expect(
          decideLinkTap('docs/Nested.markdown', platform: platform),
          const LinkInternalMd('docs/Nested.markdown'),
        );
        expect(
          decideLinkTap('../up/Sibling.md', platform: platform),
          const LinkInternalMd('../up/Sibling.md'),
        );
      }
    });

    test('#fragment and ?query suffixes are stripped from the target', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('Other.md#section', platform: platform),
          const LinkInternalMd('Other.md'),
        );
        expect(
          decideLinkTap('Other.md?x=1', platform: platform),
          const LinkInternalMd('Other.md'),
        );
        expect(
          decideLinkTap('Other.md?x=1#section', platform: platform),
          const LinkInternalMd('Other.md'),
        );
      }
    });

    test('the extension check is case-insensitive', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('Other.MD', platform: platform),
          const LinkInternalMd('Other.MD'),
        );
        expect(
          decideLinkTap('Other.Markdown', platform: platform),
          const LinkInternalMd('Other.Markdown'),
        );
      }
    });

    test('an absolute-path .md is still an internalMd DECISION — rejecting '
        'it is VaultPath.resolve\'s job in the consumer, exactly as the '
        'webview path splits the same duties', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('/abs/Other.md', platform: platform),
          const LinkInternalMd('/abs/Other.md'),
        );
      }
    });
  });

  group('decline table (mirrors the webview delegate)', () {
    test('mailto/tel/data/file/unknown schemes all decline', () {
      for (final platform in platforms) {
        for (final url in [
          'mailto:a@b.c',
          'tel:+15551234567',
          'data:text/html,x',
          'file:///etc/passwd',
          'ftp://example.com/x',
          'foo:bar',
        ]) {
          expect(
            decideLinkTap(url, platform: platform),
            const LinkDecline(),
            reason: '$url must decline on $platform',
          );
        }
      }
    });

    test('about:* declines on BOTH platforms — a native tap has no '
        'API-initiated load to disambiguate, so the webview delegate\'s '
        'iOS about:blank allowance does not apply here', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('about:blank', platform: platform),
          const LinkDecline(),
        );
        expect(
          decideLinkTap('about:config', platform: platform),
          const LinkDecline(),
        );
      }
    });

    test('a pure #fragment (and a pure ?query) declines — the documented '
        'v2 native limitation; the webview engine handles anchors in-page', () {
      for (final platform in platforms) {
        expect(
          decideLinkTap('#section', platform: platform),
          const LinkDecline(),
        );
        expect(decideLinkTap('?q=1', platform: platform), const LinkDecline());
      }
    });

    test('a non-Markdown relative target declines', () {
      for (final platform in platforms) {
        for (final url in [
          'image.png',
          'notes.txt',
          'README',
          'Other.md.bak',
        ]) {
          expect(
            decideLinkTap(url, platform: platform),
            const LinkDecline(),
            reason: '$url must decline on $platform',
          );
        }
      }
    });

    test('empty and unparseable urls decline, never throw', () {
      for (final platform in platforms) {
        expect(decideLinkTap('', platform: platform), const LinkDecline());
        expect(
          decideLinkTap('http://[invalid', platform: platform),
          const LinkDecline(),
        );
      }
    });
  });
}
