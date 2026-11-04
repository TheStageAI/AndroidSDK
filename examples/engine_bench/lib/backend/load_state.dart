// ----------------------------------------------------------------------
// Load-state helpers shared by the tabs
// ----------------------------------------------------------------------

/// The key a tab records for what it loaded under its handle: the
/// bundle plus every load-time option that would change the model
/// (a different key means stop + start again).
String loadKey(String enginesPath, {String? modelType, bool? mtp}) =>
    [enginesPath, modelType ?? '', if (mtp != null) 'mtp=$mtp'].join('|');

/// Whether an `on_progress` event belongs to [modelName]. Every tab
/// listens to the same process-wide stream, so each one keeps only
/// the events for its own handle.
bool isProgressFor(Map<String, dynamic> event, String modelName) =>
    event['model_name'] == modelName;

/// The voices a `start_model` status lists, or [fallback] when it
/// names none.
List<String> voicesFromStatus(
  Map<String, dynamic> status, {
  List<String> fallback = const [],
}) {
  final raw = status['voices'];
  if (raw is! List) return fallback;
  final voices = [
    for (final v in raw)
      if (v != null && '$v'.isNotEmpty) '$v',
  ];
  return voices.isEmpty ? fallback : voices;
}
