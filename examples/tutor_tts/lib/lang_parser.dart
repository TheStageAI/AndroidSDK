// ---------------------------------------------------------------------------
// LangSegment / LangTagParser — split `<xx>…</xx>` tutor scripts into spans
// ---------------------------------------------------------------------------

/// One language span of a tagged script.
class LangSegment {
  /// Short tag from the markup (`en`, `es`, …).
  final String tag;

  /// NeuTTS `language` for the span (`english`, `spanish`, …).
  final String language;

  /// The text spoken for this span.
  final String text;

  const LangSegment(this.tag, this.language, this.text);

  @override
  bool operator ==(Object other) =>
      other is LangSegment &&
      other.tag == tag &&
      other.language == language &&
      other.text == text;

  @override
  int get hashCode => Object.hash(tag, language, text);

  @override
  String toString() => '<$tag>$text';
}

class LangParseError implements Exception {
  final String message;
  const LangParseError(this.message);

  @override
  String toString() => message;
}

class LangTagParser {
  /// Tag → the NeuTTS multilingual language (docs/tts.md).
  static const tagToLanguage = {
    'en': 'english',
    'es': 'spanish',
    'fr': 'french',
    'de': 'german',
    'pt': 'portuguese',
    'ja': 'japanese',
    'ko': 'korean',
    'zh': 'chinese',
    'ur': 'urdu',
  };

  static final _paired = RegExp(r'<([a-zA-Z]{2})\b[^>]*>([\s\S]*?)</\1>');

  /// Parses paired tags in order; untagged text between them is spoken
  /// in [defaultTag]. Throws [LangParseError] on an unknown tag or a
  /// script with nothing to speak.
  static List<LangSegment> parse(String input, {String defaultTag = 'en'}) {
    _language(defaultTag);
    final segments = <LangSegment>[];
    var cursor = 0;
    for (final m in _paired.allMatches(input)) {
      if (m.start > cursor) {
        _appendUntagged(input.substring(cursor, m.start), defaultTag, segments);
      }
      final tag = m.group(1)!.toLowerCase();
      final body = m.group(2)!.trim();
      if (body.isNotEmpty) {
        segments.add(LangSegment(tag, _language(tag), body));
      }
      cursor = m.end;
    }
    if (cursor < input.length) {
      _appendUntagged(input.substring(cursor), defaultTag, segments);
    }
    if (segments.isEmpty) throw const LangParseError('no speakable segments');
    return segments;
  }

  static void _appendUntagged(
    String raw,
    String defaultTag,
    List<LangSegment> into,
  ) {
    final t = raw.trim();
    if (t.isEmpty) return;
    final tag = defaultTag.toLowerCase();
    into.add(LangSegment(tag, _language(tag), t));
  }

  static String _language(String tag) {
    final name = tagToLanguage[tag.toLowerCase()];
    if (name == null) throw LangParseError('unknown tag <$tag>');
    return name;
  }
}
