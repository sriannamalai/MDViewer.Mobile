# Bundled fonts

All three families are bundled as static-weight TTFs (no network font
loading, per `design/README.md` §Assets: "bundle with the app, never
network-load"). All are licensed under the **SIL Open Font License 1.1**
(OFL) — free to bundle, modify, and redistribute with the app; see each
project's license text at the links below.

| File | Family | Weight | Source |
|---|---|---|---|
| `IBMPlexSans-Regular.ttf` | IBM Plex Sans | 400 | [IBM/plex](https://github.com/IBM/plex) release `@ibm/plex-sans@1.1.0` |
| `IBMPlexSans-Medium.ttf` | IBM Plex Sans | 500 | same |
| `IBMPlexSans-SemiBold.ttf` | IBM Plex Sans | 600 | same |
| `IBMPlexSans-Bold.ttf` | IBM Plex Sans | 700 | same |
| `SourceSerif4-SemiBold.ttf` | Source Serif 4 | 600 | [adobe-fonts/source-serif](https://github.com/adobe-fonts/source-serif) release `4.005R` (Desktop instances) |
| `SourceSerif4-Bold.ttf` | Source Serif 4 | 700 | same |
| `JetBrainsMono-Regular.ttf` | JetBrains Mono | 400 | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) release `v2.304` |
| `JetBrainsMono-Medium.ttf` | JetBrains Mono | 500 | same |

Weights fetched match exactly what `design/TOKENS.md` and
`design/README.md` §Fidelity use: IBM Plex Sans needs 400/500/600/700
(UI text through UI labels), Source Serif 4 only ever appears at 600/700
(H1–H3 headings), JetBrains Mono needs 400/500 (code + UI meta/mono).

Registered as Flutter font families `IBMPlexSans`, `SourceSerif4`,
`JetBrainsMono` in `pubspec.yaml` — see `lib/src/tokens.dart`'s
`AppFonts` class for the family-name constants later tasks should use
instead of repeating string literals.

## Licenses

- IBM Plex Sans: OFL 1.1 — <https://github.com/IBM/plex/blob/master/LICENSE.txt>
- Source Serif 4: OFL 1.1 — <https://github.com/adobe-fonts/source-serif/blob/release/LICENSE.md>
- JetBrains Mono: OFL 1.1 — <https://github.com/JetBrains/JetBrainsMono/blob/master/OFL.txt>
