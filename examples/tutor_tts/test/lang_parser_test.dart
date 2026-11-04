import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_tutor_tts/lang_parser.dart';
import 'package:thestage_tutor_tts/phrases.dart';

void main() {
  test('paired tags become ordered spans with their language', () {
    expect(
      LangTagParser.parse('<en>Hello:</en>\n<es>Hola.</es>'),
      const [
        LangSegment('en', 'english', 'Hello:'),
        LangSegment('es', 'spanish', 'Hola.'),
      ],
    );
  });

  test('untagged glue is spoken in the default language', () {
    expect(
      LangTagParser.parse('Say it: <fr>Bonjour</fr> thanks'),
      const [
        LangSegment('en', 'english', 'Say it:'),
        LangSegment('fr', 'french', 'Bonjour'),
        LangSegment('en', 'english', 'thanks'),
      ],
    );
  });

  test('an unknown tag or an empty script is an error', () {
    expect(() => LangTagParser.parse('<xx>hi</xx>'),
        throwsA(isA<LangParseError>()));
    expect(() => LangTagParser.parse('  '), throwsA(isA<LangParseError>()));
  });

  test('every stock phrase parses', () {
    for (final p in TutorPhraseBook.all) {
      expect(LangTagParser.parse(p.tagged), isNotEmpty, reason: p.id);
    }
  });
}
