import 'package:app/src/render/scrollspy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('injectScrollSpy', () {
    test('inserts before the last </body>, not the first', () {
      // A decoy '</body>' inside an inline script (mimics mermaid's bundled
      // HTML-serialization string), followed by the real closing tag.
      const html =
          '<html><head></head><body>'
          '<script>var s = "<html><body>x</body></html>";</script>'
          '<h1>content</h1>'
          '</body></html>';

      final out = injectScrollSpy(html);

      final firstBodyClose = html.indexOf('</body>');
      final lastBodyClose = html.lastIndexOf('</body>');
      expect(firstBodyClose, isNot(lastBodyClose));

      // The decoy occurrence must be untouched: everything up to and
      // including it appears verbatim, unsplit by injected content.
      expect(out, startsWith(html.substring(0, lastBodyClose)));
      // The script lands between the real content and the final </body>.
      expect(
        out.indexOf('ScrollSpy'),
        greaterThan(out.indexOf('<h1>content</h1>')),
      );
      expect(out.indexOf('ScrollSpy'), lessThan(out.lastIndexOf('</body>')));
    });

    test('appends the script when there is no </body> at all', () {
      const html = '<div>fragment, no body tag</div>';
      final out = injectScrollSpy(html);
      expect(out, startsWith(html));
      expect(out, contains('ScrollSpy'));
    });

    test('injected script references the channel name constant', () {
      final out = injectScrollSpy('<html><body></body></html>');
      expect(out, contains('window.$scrollSpyChannelName'));
      expect(out, contains('__mdvScrollToLine'));
      expect(out, contains('__mdvScrollToProgress'));
    });

    test('__mdvScrollToLine falls back to the nearest preceding marked block '
        'when there is no exact data-md-line match', () {
      final out = injectScrollSpy('<html><body></body></html>');

      // The exact-match attempt is still tried first...
      expect(
        out,
        contains('document.querySelector(\'[data-md-line="\' + line + \'"]\')'),
      );
      // ...but falling through to null no longer just gives up: it scans
      // every marked block for the largest data-md-line <= the requested
      // line (data-md-line only marks each top-level block's *start*
      // line, not every source line, so most non-heading search matches
      // would otherwise silently no-op).
      expect(out, contains("document.querySelectorAll('[data-md-line]')"));
      expect(out, contains('candidateLine <= line'));
      expect(out, contains('candidateLine > bestLine'));
    });
  });

  group('ScrollSpyPayload.tryParse', () {
    test('parses a well-formed payload', () {
      final payload = ScrollSpyPayload.tryParse('{"p": 0.5, "h": 12}');
      expect(payload, const ScrollSpyPayload(progress: 0.5, line: 12));
    });

    test('clamps progress to 0..1', () {
      expect(ScrollSpyPayload.tryParse('{"p": 1.4, "h": 1}')!.progress, 1.0);
      expect(ScrollSpyPayload.tryParse('{"p": -0.2, "h": 1}')!.progress, 0.0);
    });

    test('coerces numeric strings', () {
      final payload = ScrollSpyPayload.tryParse('{"p": "0.75", "h": "3"}');
      expect(payload, const ScrollSpyPayload(progress: 0.75, line: 3));
    });

    test(
      'defaults a missing/garbage "h" to 0 rather than rejecting the whole payload',
      () {
        final payload = ScrollSpyPayload.tryParse('{"p": 0.3}');
        expect(payload, const ScrollSpyPayload(progress: 0.3, line: 0));

        final withGarbageH = ScrollSpyPayload.tryParse(
          '{"p": 0.3, "h": "not a number"}',
        );
        expect(withGarbageH, const ScrollSpyPayload(progress: 0.3, line: 0));
      },
    );

    test(
      'rejects a missing/garbage "p" — nothing to clamp to a sane default',
      () {
        expect(ScrollSpyPayload.tryParse('{"h": 3}'), isNull);
        expect(
          ScrollSpyPayload.tryParse('{"p": "not a number", "h": 3}'),
          isNull,
        );
        expect(ScrollSpyPayload.tryParse('{"p": null, "h": 3}'), isNull);
      },
    );

    test('never throws on malformed JSON', () {
      expect(ScrollSpyPayload.tryParse('not json at all'), isNull);
      expect(ScrollSpyPayload.tryParse('{"p": 0.5,'), isNull);
      expect(ScrollSpyPayload.tryParse(''), isNull);
    });

    test('rejects a non-object top level', () {
      expect(ScrollSpyPayload.tryParse('42'), isNull);
      expect(ScrollSpyPayload.tryParse('[1,2,3]'), isNull);
      expect(ScrollSpyPayload.tryParse('"a string"'), isNull);
    });

    test('rejects NaN/Infinity-producing values', () {
      expect(ScrollSpyPayload.tryParse('{"p": "NaN", "h": 1}'), isNull);
    });
  });

  group('script generation helpers', () {
    test('scrollToLineScript embeds the line number and guards the call', () {
      final script = scrollToLineScript(42);
      expect(
        script,
        contains('__mdvScrollToLine && window.__mdvScrollToLine(42)'),
      );
    });

    test('scrollToProgressScript embeds a clamped progress value', () {
      expect(
        scrollToProgressScript(0.5),
        contains('__mdvScrollToProgress(0.5)'),
      );
      expect(
        scrollToProgressScript(1.5),
        contains('__mdvScrollToProgress(1.0)'),
      );
      expect(
        scrollToProgressScript(-1.0),
        contains('__mdvScrollToProgress(0.0)'),
      );
    });
  });
}
