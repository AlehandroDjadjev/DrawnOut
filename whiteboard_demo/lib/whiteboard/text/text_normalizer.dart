/// Normalizes action text before rendering so formulas and list items are
/// displayed consistently across whiteboard renderers.
class ScriptGlyph {
  final String value;
  final double sizeFactor;
  final double baselineShiftEm;

  const ScriptGlyph(
    this.value, {
    this.sizeFactor = 1.0,
    this.baselineShiftEm = 0.0,
  });
}

class TextNormalizer {
  static final RegExp _listPrefix = RegExp(
    r'^\s*(?:[\u2022\u25E6\-\*]|\d+\.)\s+',
  );

  static const Map<String, String> _unicodeSupToAscii = {
    '\u00B0': 'o',
    '\u00B9': '1',
    '\u00B2': '2',
    '\u00B3': '3',
    '\u2070': '0',
    '\u2074': '4',
    '\u2075': '5',
    '\u2076': '6',
    '\u2077': '7',
    '\u2078': '8',
    '\u2079': '9',
    '\u207A': '+',
    '\u207B': '-',
    '\u207C': '=',
    '\u207D': '(',
    '\u207E': ')',
    '\u1D43': 'a',
    '\u1D47': 'b',
    '\u1D9C': 'c',
    '\u1D48': 'd',
    '\u1D49': 'e',
    '\u1DA0': 'f',
    '\u1D4D': 'g',
    '\u02B0': 'h',
    '\u2071': 'i',
    '\u02B2': 'j',
    '\u1D4F': 'k',
    '\u02E1': 'l',
    '\u1D50': 'm',
    '\u207F': 'n',
    '\u1D52': 'o',
    '\u1D56': 'p',
    '\u02B3': 'r',
    '\u02E2': 's',
    '\u1D57': 't',
    '\u1D58': 'u',
    '\u1D5B': 'v',
    '\u02B7': 'w',
    '\u02E3': 'x',
    '\u02B8': 'y',
    '\u1DBB': 'z',
  };

  static const Map<String, String> _unicodeSubToAscii = {
    '\u2080': '0',
    '\u2081': '1',
    '\u2082': '2',
    '\u2083': '3',
    '\u2084': '4',
    '\u2085': '5',
    '\u2086': '6',
    '\u2087': '7',
    '\u2088': '8',
    '\u2089': '9',
    '\u208A': '+',
    '\u208B': '-',
    '\u208C': '=',
    '\u208D': '(',
    '\u208E': ')',
    '\u2090': 'a',
    '\u2091': 'e',
    '\u2095': 'h',
    '\u1D62': 'i',
    '\u2C7C': 'j',
    '\u2096': 'k',
    '\u2097': 'l',
    '\u2098': 'm',
    '\u2099': 'n',
    '\u2092': 'o',
    '\u209A': 'p',
    '\u1D63': 'r',
    '\u209B': 's',
    '\u209C': 't',
    '\u1D64': 'u',
    '\u1D65': 'v',
    '\u2093': 'x',
  };

  /// Normalize text based on action type.
  static String normalizeForAction({
    required String type,
    required String text,
  }) {
    if (text.isEmpty) return text;

    final t = type.toLowerCase();
    if (t == 'formula' || t == 'label') {
      return normalizeMathNotation(text);
    }
    if (t == 'bullet') {
      return _ensureListPrefix(text, marker: '- ');
    }
    if (t == 'subbullet') {
      return _ensureListPrefix(text, marker: '  - ');
    }
    return text;
  }

  /// Keep formulas ASCII-friendly for glyph rendering and convert existing
  /// unicode script chars into `^{...}` / `_{...}` notation.
  static String normalizeMathNotation(String text) {
    if (text.isEmpty) return text;
    return _convertUnicodeScripts(text);
  }

  /// Expand inline `^` / `_` math notation into glyph-level layout tokens.
  ///
  /// Examples:
  ///   `a^2` -> `a` + superscript `2`
  ///   `x^{10}` -> `x` + superscript `1`,`0`
  ///   `H_2O` -> `H` + subscript `2` + `O`
  static List<ScriptGlyph> expandScriptGlyphs(
    String text, {
    double scriptScale = 0.66,
    double superscriptLiftEm = 0.44,
    double subscriptDropEm = 0.20,
  }) {
    if (text.isEmpty) return const [];

    final out = <ScriptGlyph>[];
    int i = 0;

    while (i < text.length) {
      final ch = text[i];
      if ((ch == '^' || ch == '_') && (i + 1) < text.length) {
        final parsed = _readScriptToken(text, i + 1);
        if (parsed != null && parsed.token.isNotEmpty) {
          final shift = ch == '^' ? -superscriptLiftEm : subscriptDropEm;
          for (final cp in parsed.token.runes) {
            out.add(
              ScriptGlyph(
                String.fromCharCode(cp),
                sizeFactor: scriptScale,
                baselineShiftEm: shift,
              ),
            );
          }
          i = parsed.nextIndex;
          continue;
        }
      }

      out.add(ScriptGlyph(ch));
      i++;
    }

    return out;
  }

  static String _ensureListPrefix(String text, {required String marker}) {
    final trimmedLeft = text.trimLeft();
    if (trimmedLeft.isEmpty) return text;
    if (_listPrefix.hasMatch(trimmedLeft)) return text;
    final leadingSpaces = text.substring(0, text.length - trimmedLeft.length);
    return '$leadingSpaces$marker$trimmedLeft';
  }

  static String _convertUnicodeScripts(String text) {
    final out = StringBuffer();
    int i = 0;

    while (i < text.length) {
      final ch = text[i];

      if (_unicodeSupToAscii.containsKey(ch)) {
        final token = StringBuffer();
        int j = i;
        while (j < text.length && _unicodeSupToAscii.containsKey(text[j])) {
          token.write(_unicodeSupToAscii[text[j]]);
          j++;
        }
        out.write('^{${token.toString()}}');
        i = j;
        continue;
      }

      if (_unicodeSubToAscii.containsKey(ch)) {
        final token = StringBuffer();
        int j = i;
        while (j < text.length && _unicodeSubToAscii.containsKey(text[j])) {
          token.write(_unicodeSubToAscii[text[j]]);
          j++;
        }
        out.write('_{${token.toString()}}');
        i = j;
        continue;
      }

      out.write(ch);
      i++;
    }

    return out.toString();
  }

  static _ScriptToken? _readScriptToken(String text, int start) {
    if (start >= text.length) return null;

    if (text[start] != '{') {
      return _ScriptToken(text[start], start + 1);
    }

    final token = StringBuffer();
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') {
        depth++;
        if (depth > 1) token.write(ch);
        continue;
      }
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return _ScriptToken(token.toString(), i + 1);
        }
        token.write(ch);
        continue;
      }
      token.write(ch);
    }

    return null;
  }
}

class _ScriptToken {
  final String token;
  final int nextIndex;

  const _ScriptToken(this.token, this.nextIndex);
}
