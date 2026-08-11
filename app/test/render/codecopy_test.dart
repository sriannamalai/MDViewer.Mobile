import 'package:app/src/render/codecopy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('injectCodeCopy', () {
    test('inserts before the last </body>, not the first', () {
      // A decoy '</body>' inside an inline script (mimics mermaid's bundled
      // HTML-serialization string), followed by the real closing tag —
      // the same failure mode injectScrollSpy documents and guards.
      const html =
          '<html><head></head><body>'
          '<script>var s = "<html><body>x</body></html>";</script>'
          '<div class="md-code"><pre><code>x</code></pre></div>'
          '</body></html>';

      final out = injectCodeCopy(html);

      final firstBodyClose = html.indexOf('</body>');
      final lastBodyClose = html.lastIndexOf('</body>');
      expect(firstBodyClose, isNot(lastBodyClose));

      // The decoy occurrence must be untouched: everything up to and
      // including it appears verbatim, unsplit by injected content.
      expect(out, startsWith(html.substring(0, lastBodyClose)));
      // The script lands between the real content and the final </body>.
      expect(
        out.indexOf('CodeCopy'),
        greaterThan(out.indexOf('md-code')),
      );
      expect(out.indexOf('CodeCopy'), lessThan(out.lastIndexOf('</body>')));
    });

    test('appends the script when there is no </body> at all', () {
      const html = '<div>fragment, no body tag</div>';
      final out = injectCodeCopy(html);
      expect(out, startsWith(html));
      expect(out, contains('CodeCopy'));
    });

    test('injected script references the channel name constant', () {
      final out = injectCodeCopy('<html><body></body></html>');
      expect(out, contains('window.$codeCopyChannelName'));
      expect(out, contains('window.$codeCopyChannelName.postMessage'));
    });

    test('listens on the capture phase and stands down when the page has a '
        'real clipboard', () {
      final out = injectCodeCopy('<html><body></body></html>');

      // Capture phase: runs before the library's bubble-phase handler
      // regardless of registration order.
      expect(out, contains("}, true);"));
      // Inverse of the library's guard (page.go no-ops WITHOUT
      // navigator.clipboard; this bridge no-ops WITH it) — the two
      // handlers are mutually exclusive, so no double-copy/double-flip
      // in either kind of origin.
      expect(out, contains('if (navigator.clipboard) return;'));
    });

    test('posts the sibling pre text and shows transient Copied feedback', () {
      final out = injectCodeCopy('<html><body></body></html>');

      expect(out, contains(".closest('.md-code-copy')"));
      expect(out, contains(".closest('.md-code')"));
      expect(out, contains(".querySelector('pre')"));
      expect(out, contains('pre.innerText'));
      // The library's own feedback contract: label flips to 'Copied' and
      // reverts after 1200ms.
      expect(out, contains("b.textContent = 'Copied';"));
      expect(out, contains('1200'));
    });
  });
}
