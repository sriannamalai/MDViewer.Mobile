/// The `WebViewController.addJavaScriptChannel` name the injected script
/// (below) posts code-block text to, and `reader.dart` listens on (writing
/// it to the system clipboard via `Clipboard.setData`). Named alongside
/// scrollspy.dart's [scrollSpyChannelName] — same registration pattern.
const String codeCopyChannelName = 'CodeCopy';

/// Appends the code-copy bridge `<script>` to [html] at
/// `lastIndexOf('</body>')` — the exact splice discipline
/// `injectScrollSpy` documents (scrollspy.dart): a mermaid-bearing page
/// contains decoy `</body>` substrings inside mermaid's inlined bundle, so
/// only the *last* occurrence is the document's real closing tag.
///
/// ## Why the bridge exists
///
/// `codeHeader: true` (renderer.dart) makes the library emit a Copy button
/// per code block plus an inline clipboard handler
/// (`vendor/markdownviewer/render/html/page.go`). That handler guards on
/// `navigator.clipboard`, which browsers only expose in secure contexts —
/// and a `loadHtmlString` page is a null/non-secure origin on both
/// WebView platforms, so in this app the library handler always no-ops.
/// Without a bridge the button still *looks* live (base.css gives it an
/// accent :hover/tap state) but silently copies nothing. This script
/// forwards the code text over a JavaScript channel instead, and the Dart
/// side performs the actual clipboard write.
String injectCodeCopy(String html) {
  final idx = html.lastIndexOf('</body>');
  if (idx == -1) return html + _codeCopyScript;
  return html.substring(0, idx) + _codeCopyScript + html.substring(idx);
}

/// Injected once per render, after the library's own clipboard script in
/// document order (this splice lands at the end of `<body>`; the library's
/// handler is registered earlier in it).
///
/// - **Capture phase** (`addEventListener(..., true)`): runs before the
///   library's bubble-phase document handler, independent of registration
///   order.
/// - **`navigator.clipboard` guard, inverted**: the library handler no-ops
///   exactly when `navigator.clipboard` is absent, so this bridge acts
///   only then — the two handlers are mutually exclusive by construction.
///   In a hypothetical secure-context embed the library path works
///   natively (write + "Copied" feedback) and this script stands down. No
///   `stopPropagation()` needed: letting the event bubble on is harmless
///   because whichever handler's guard fails does nothing at all.
/// - **Feedback**: flips the button label to "Copied" and reverts after
///   1.2s, mirroring the library's own timing (page.go uses 1200ms).
///   `postMessage` is fire-and-forget, so the label flip is optimistic —
///   same as the library's, which flips on the clipboard promise, not on
///   any paste-verified truth.
const String _codeCopyScript =
    '''
<script>
(function(){
  document.addEventListener('click', function(e){
    if (navigator.clipboard) return; // library's own handler covers this
    var b = e.target && e.target.closest ? e.target.closest('.md-code-copy') : null;
    if (!b) return;
    var box = b.closest('.md-code');
    var pre = box ? box.querySelector('pre') : null;
    if (!pre) return;
    if (!(window.$codeCopyChannelName && window.$codeCopyChannelName.postMessage)) return;
    window.$codeCopyChannelName.postMessage(pre.innerText);
    if (b.getAttribute('data-mdv-copied')) return; // mid-feedback re-tap: keep the original label
    b.setAttribute('data-mdv-copied', '1');
    var label = b.textContent;
    b.textContent = 'Copied';
    setTimeout(function(){
      b.textContent = label;
      b.removeAttribute('data-mdv-copied');
    }, 1200);
  }, true);
})();
</script>''';
