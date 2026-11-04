import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_tutor_small_llms/normalize.dart';
import 'package:thestage_tutor_small_llms/recipes.dart';

void main() {
  final today = DateTime(2026, 8, 13); // a Thursday

  test('printed ticket dates normalise through OCR swaps', () {
    expect(isoDay(normalizePrintedDate('14/O8/2026')!), '2026-08-14');
    expect(isoDay(normalizePrintedDate('03.11.25')!), '2025-11-03');
    expect(isoDay(normalizePrintedDate('02-09-2026 O7:55')!), '2026-09-02');
    expect(normalizePrintedDate('31/02/2026'), isNull);
    expect(normalizePrintedDate('8,80'), isNull);
  });

  test('export prefixes are stripped', () {
    expect(
      stripExportPrefixes('[13/08/2026, 12:04:11] Marco: hi\nplain'),
      'Marco: hi\nplain',
    );
  });

  test('said days resolve against today', () {
    String at(String day, String time) => isoStamp(
          resolveSaidDatetime(daySaid: day, startSaid: time, today: today)!,
        );
    expect(at('14/08', '13:00'), '2026-08-14T13:00:00');
    expect(at('tomorrow', '18:30'), '2026-08-14T18:30:00');
    expect(at('friday', '09:00'), '2026-08-14T09:00:00');
    expect(at('thursday', '09:00'), '2026-08-13T09:00:00');
    expect(at('in 3 days', '10:00'), '2026-08-16T10:00:00');
    expect(isoStamp(parseWhen('tomorrow 18:30', today: today)!),
        '2026-08-14T18:30:00');
    expect(parseWhen('tomorrow', today: today), isNull);
  });

  test('the recipes keep their shape', () {
    expect(Recipes.expenseShotAssistant, startsWith('{"merchant"'));
    expect(Recipes.starbucksOcr, contains('14/O8/2026'));
    expect(Recipes.starbucksOcr, isNot(startsWith('\n')));
    expect(Recipes.calendarWhenShots, isEmpty);
  });
}
