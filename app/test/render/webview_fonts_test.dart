import 'package:app/src/render/webview_fonts.dart';
import 'package:app/src/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(WebviewFonts.resetCacheForTest);
  tearDown(WebviewFonts.resetCacheForTest);

  test('embeds an @font-face rule for every bundled weight of all three '
      'families', () async {
    final css = await WebviewFonts.ensureLoaded();

    expect(css, isNotNull);
    // IBM Plex Sans: Regular/Medium/SemiBold/Bold (400/500/600/700).
    for (final weight in [400, 500, 600, 700]) {
      expect(
        css,
        contains(
          "@font-face{font-family:'${AppFonts.ibmPlexSans}';"
          'font-weight:$weight;',
        ),
      );
    }
    // Source Serif 4: SemiBold/Bold only (600/700) — matches pubspec.yaml.
    for (final weight in [600, 700]) {
      expect(
        css,
        contains(
          "@font-face{font-family:'${AppFonts.sourceSerif4}';"
          'font-weight:$weight;',
        ),
      );
    }
    // JetBrains Mono: Regular/Medium (400/500).
    for (final weight in [400, 500]) {
      expect(
        css,
        contains(
          "@font-face{font-family:'${AppFonts.jetBrainsMono}';"
          'font-weight:$weight;',
        ),
      );
    }
    // Every @font-face carries a base64 data: URI, not an asset path
    // (which a `loadHtmlString` page could never resolve).
    expect(css, contains('src:url(data:font/ttf;base64,'));
  });

  test('re-points body/heading/code selectors at the embedded families, '
      'keeping the ORIGINAL system stack as a fallback', () async {
    final css = await WebviewFonts.ensureLoaded();

    expect(
      css,
      contains("body.markdown-body{font-family:'${AppFonts.ibmPlexSans}',"),
    );
    expect(css, contains('-apple-system')); // fallback stack survives
    expect(
      css,
      contains(
        '.markdown-body h1,.markdown-body h2,.markdown-body h3{'
        "font-family:'${AppFonts.sourceSerif4}',",
      ),
    );
    expect(
      css,
      contains(
        '.markdown-body code,.markdown-body pre,.markdown-body kbd,'
        ".markdown-body .md-code-lang,.markdown-body .md-code-copy{"
        "font-family:'${AppFonts.jetBrainsMono}',",
      ),
    );
    // h4-h6 are NOT re-pointed — native only customizes h1-h3
    // (tokens.dart's AppTheme), so the two engines must match exactly.
    expect(css, isNot(contains('h4,')));
  });

  test('loads once per process — a second call returns the SAME cached '
      'string instance', () async {
    final first = await WebviewFonts.ensureLoaded();
    final second = await WebviewFonts.ensureLoaded();

    expect(identical(first, second), isTrue);
  });
}
