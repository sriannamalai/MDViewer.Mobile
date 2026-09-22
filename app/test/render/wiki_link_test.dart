import 'package:app/src/render/wiki_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';

void main() {
  group('resolveWikiLinkUrl', () {
    test('a unique stem match at the vault root resolves directly', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'Other',
        mdRelPaths: const ['Welcome.md', 'Other.md'],
      );
      expect(url, 'Other.md');
    });

    test('matching is case-insensitive on both the target and the stem', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'oTHER page',
        mdRelPaths: const ['Other Page.md'],
      );
      expect(url, 'Other Page.md');
    });

    test('a target spelled with an extension still matches by stem', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'Other.md',
        mdRelPaths: const ['Other.md'],
      );
      expect(url, 'Other.md');
    });

    test('a match in a different directory resolves relative to the linking '
        "document's directory, ready for VaultPath.resolve", () {
      // Linking doc in Notes/, match at the vault root: climb out.
      expect(
        resolveWikiLinkUrl(
          fromRelPath: 'Notes/A.md',
          target: 'Other',
          mdRelPaths: const ['Notes/A.md', 'Other.md'],
        ),
        '../Other.md',
      );
      // Linking doc at the root, match in a subdirectory: descend.
      expect(
        resolveWikiLinkUrl(
          fromRelPath: 'Welcome.md',
          target: 'Sub',
          mdRelPaths: const ['Welcome.md', 'Notes/Sub.md'],
        ),
        'Notes/Sub.md',
      );
      // Both in the same directory: no climb needed.
      expect(
        resolveWikiLinkUrl(
          fromRelPath: 'Notes/A.md',
          target: 'B',
          mdRelPaths: const ['Notes/A.md', 'Notes/B.md'],
        ),
        'B.md',
      );
    });

    test('zero matches (unresolved) falls back to the wikiSearchUri marker '
        'carrying the RAW target', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'Nonexistent Page',
        mdRelPaths: const ['Welcome.md', 'Other.md'],
      );
      expect(url, wikiSearchUri('Nonexistent Page').toString());
      final parsed = Uri.parse(url);
      expect(parsed.scheme, wikiSearchScheme);
      expect(parsed.queryParameters['q'], 'Nonexistent Page');
    });

    test('more than one same-stem match (ambiguous) ALSO falls back to the '
        'search marker, not an arbitrary pick', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'Notes',
        mdRelPaths: const ['A/Notes.md', 'B/Notes.md'],
      );
      expect(Uri.parse(url).scheme, wikiSearchScheme);
      expect(Uri.parse(url).queryParameters['q'], 'Notes');
    });

    test('an empty candidate list always falls back to search', () {
      final url = resolveWikiLinkUrl(
        fromRelPath: 'Welcome.md',
        target: 'Anything',
        mdRelPaths: const [],
      );
      expect(Uri.parse(url).scheme, wikiSearchScheme);
    });
  });

  group('wikiLinkResolver', () {
    test('answers ONLY the wikiLink kind — link/image always decline', () {
      final resolver = wikiLinkResolver(
        fromRelPath: 'Welcome.md',
        mdRelPaths: const ['Welcome.md', 'Other.md'],
      );
      expect(resolver(MdvResolveKind.wikiLink, 'Other'), 'Other.md');
      expect(resolver(MdvResolveKind.link, 'Other'), isNull);
      expect(resolver(MdvResolveKind.image, 'Other'), isNull);
    });
  });

  group('combineResolvers', () {
    test('the first non-null answer wins, in order', () {
      final resolver = combineResolvers([
        (kind, target) => target == 'a' ? 'first' : null,
        (kind, target) => target == 'b' ? 'second' : null,
      ]);
      expect(resolver(MdvResolveKind.link, 'a'), 'first');
      expect(resolver(MdvResolveKind.link, 'b'), 'second');
      expect(resolver(MdvResolveKind.link, 'c'), isNull);
    });
  });
}
