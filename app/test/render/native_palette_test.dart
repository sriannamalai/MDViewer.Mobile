import 'package:app/src/render/native_palette.dart';
import 'package:app/src/render/renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';

/// A [DocRenderer] whose palette load is canned — the seam that keeps
/// this testable on a host with no reachable `libmdviewer` (the real
/// [DocRenderer.loadPalette] goes through the FFI asset call).
class _FakePaletteRenderer extends DocRenderer {
  _FakePaletteRenderer({this.throwOn});

  /// Non-null makes [loadPalette] throw it (the unreachable-assets
  /// case every widget-test host is really in).
  final Object? throwOn;

  final List<bool> calls = <bool>[];

  @override
  Future<MdvPalette> loadPalette({required bool dark}) async {
    calls.add(dark);
    final error = throwOn;
    if (error != null) throw error;
    return dark ? _darkFixture : _lightFixture;
  }
}

const MdvPalette _lightFixture = MdvPalette(
  brightness: Brightness.light,
  background: Color(0xFFFFFFFF),
  foreground: Color(0xFF111111),
  accent: Color(0xFF0000EE),
  border: Color(0xFFCCCCCC),
  codeBackground: Color(0xFFF0F0F0),
  quoteForeground: Color(0xFF666666),
  tokenColors: {'Keyword': Color(0xFFAA0000)},
);

const MdvPalette _darkFixture = MdvPalette(
  brightness: Brightness.dark,
  background: Color(0xFF000000),
  foreground: Color(0xFFEEEEEE),
  accent: Color(0xFF4493F8),
  border: Color(0xFF333333),
  codeBackground: Color(0xFF161616),
  quoteForeground: Color(0xFF999999),
  tokenColors: {'Keyword': Color(0xFF00AA00)},
);

void main() {
  setUp(NativePalettes.resetCacheForTest);
  tearDown(NativePalettes.resetCacheForTest);

  test('forBrightness picks the matching palette', () {
    const palettes = NativePalettes(light: _lightFixture, dark: _darkFixture);

    expect(palettes.forBrightness(Brightness.light), same(_lightFixture));
    expect(palettes.forBrightness(Brightness.dark), same(_darkFixture));
  });

  test('ensureLoaded loads BOTH modes, once per process', () async {
    final renderer = _FakePaletteRenderer();

    final first = await NativePalettes.ensureLoaded(renderer);
    expect(first, isNotNull);
    expect(renderer.calls, [
      false,
      true,
    ], reason: 'both modes load together — a theme flip must not await');

    final second = await NativePalettes.ensureLoaded(renderer);
    expect(
      second,
      same(first),
      reason: 'palettes are theme assets: identical for every document',
    );
    expect(renderer.calls, [
      false,
      true,
    ], reason: 'the cached pair must not re-fetch');
  });

  test('ensureLoaded carries the loaded token colors through', () async {
    final palettes = await NativePalettes.ensureLoaded(_FakePaletteRenderer());

    expect(
      palettes!.forBrightness(Brightness.light).tokenColor('Keyword'),
      const Color(0xFFAA0000),
    );
    expect(
      palettes.forBrightness(Brightness.dark).tokenColor('Keyword'),
      const Color(0xFF00AA00),
    );
  });

  test('an unreachable asset load degrades to null, never a throw', () async {
    final renderer = _FakePaletteRenderer(throwOn: StateError('no library'));

    expect(await NativePalettes.ensureLoaded(renderer), isNull);
  });

  test(
    'a failed load is not cached — a later load can still succeed',
    () async {
      expect(
        await NativePalettes.ensureLoaded(
          _FakePaletteRenderer(throwOn: StateError('no library')),
        ),
        isNull,
      );

      expect(
        await NativePalettes.ensureLoaded(_FakePaletteRenderer()),
        isNotNull,
      );
    },
  );
}
