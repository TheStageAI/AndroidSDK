// The deterministic half of the copy-verbatim recipes: the model copies
// what is printed or said; this code turns it into a date.

// ---------------------------------------------------------------------------
// Printed fiscal-ticket date -> ISO day
// ---------------------------------------------------------------------------

/// OCR on fiscal tickets swaps letters for digits inside numeric runs.
String _repairOcrDigits(String text) {
  const swaps = {
    'O': '0', 'o': '0', 'Q': '0', 'D': '0',
    'l': '1', 'I': '1', '|': '1',
    'S': '5', 'B': '8',
  };
  return text.split('').map((c) => swaps[c] ?? c).join();
}

/// `14/O8/2026`, `03.11.25`, `02-09-2026` -> a day (null if not one).
/// Italian / German tickets print the day first: a locale fact the app
/// knows.
DateTime? normalizePrintedDate(String printed) {
  // A faithful copy often carries the time too ("14/O8/2026 08:41").
  final fields = _repairOcrDigits(printed).trim().split(RegExp(r'\s+'));
  final parts = fields.first.split(RegExp(r'[/.\-]'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  var year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (parts[2].length == 2) year += 2000;
  if (day < 1 || day > 31 || month < 1 || month > 12) return null;
  if (year < 2000 || year > 2100) return null;
  final date = DateTime(year, month, day);
  // DateTime rolls 31/02 over into March: reject that.
  if (date.day != day) return null;
  return date;
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String isoStamp(DateTime d) =>
    '${isoDay(d)}T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String _two(int n) => n.toString().padLeft(2, '0');

// ---------------------------------------------------------------------------
// Chat export -> plain thread
// ---------------------------------------------------------------------------

/// Drops the `[dd/mm/yyyy, HH:mm:ss] ` bubble prefixes of a WhatsApp
/// export, so the model never mistakes a send time for the meeting time.
String stripExportPrefixes(String export) => export.split('\n').map((line) {
      if (line.startsWith('[')) {
        final close = line.indexOf(']');
        if (close >= 0) return line.substring(close + 1).trimLeft();
      }
      return line;
    }).join('\n');

// ---------------------------------------------------------------------------
// What the thread said -> event start
// ---------------------------------------------------------------------------

/// `14/08`, `tomorrow`, `friday` + `18:30` -> a concrete time.
DateTime? resolveSaidDatetime({
  required String daySaid,
  required String startSaid,
  required DateTime today,
}) {
  final time = startSaid.split(':');
  if (time.length != 2) return null;
  final hour = int.tryParse(time[0]);
  final minute = int.tryParse(time[1]);
  if (hour == null || minute == null) return null;

  final key = daySaid.toLowerCase().trim();
  final start = DateTime(today.year, today.month, today.day);
  DateTime? day;

  if (const {'today', 'oggi', 'heute'}.contains(key)) {
    day = start;
  } else if (const {'tomorrow', 'domani', 'morgen'}.contains(key)) {
    day = DateTime(start.year, start.month, start.day + 1);
  } else if (_relative(key, start) case final DateTime d) {
    day = d;
  } else if (_weekday(key) case final int weekday) {
    // The next such day, today included.
    final ahead = (weekday - start.weekday) % 7;
    day = DateTime(start.year, start.month, start.day + ahead);
  } else {
    // dd/mm or dd/mm/yyyy as written in the body.
    final parts = key.split(RegExp(r'[/.\-]'));
    if (parts.length >= 2) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      var y = parts.length > 2 ? int.tryParse(parts[2]) : today.year;
      if (y != null && y < 100) y += 2000;
      if (d != null && m != null && y != null) day = DateTime(y, m, d);
    }
  }
  if (day == null) return null;
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// `tomorrow 18:30`, `in 3 days 10:00`, `14/08 13:00` -> a concrete time.
DateTime? parseWhen(String when, {required DateTime today}) {
  final parts = when.trim().split(' ');
  if (parts.length < 2 || !parts.last.contains(':')) return null;
  return resolveSaidDatetime(
    daySaid: parts.sublist(0, parts.length - 1).join(' '),
    startSaid: parts.last,
    today: today,
  );
}

/// `in 3 days`, `in 2 weeks`, `in 5 months` from [start].
DateTime? _relative(String key, DateTime start) {
  final words = key.split(' ');
  if (words.length != 3 || words[0] != 'in') return null;
  final n = int.tryParse(words[1]);
  if (n == null) return null;
  return switch (words[2]) {
    'day' || 'days' => DateTime(start.year, start.month, start.day + n),
    'week' || 'weeks' => DateTime(start.year, start.month, start.day + 7 * n),
    'month' || 'months' => DateTime(start.year, start.month + n, start.day),
    _ => null,
  };
}

/// A weekday name -> `DateTime.monday` … `DateTime.sunday`.
int? _weekday(String name) {
  const long = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
    'sunday',
  ];
  const short = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final i = long.indexOf(name);
  if (i >= 0) return i + 1;
  final j = short.indexOf(name);
  return j >= 0 ? j + 1 : null;
}
