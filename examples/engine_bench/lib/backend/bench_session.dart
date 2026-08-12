import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ----------------------------------------------------------------------
// Small stats helpers
// ----------------------------------------------------------------------
double? median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = List<double>.of(xs)..sort();
  final m = s.length ~/ 2;
  return s.length.isEven ? (s[m - 1] + s[m]) / 2 : s[m];
}

double? mean(List<double> xs) {
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a + b) / xs.length;
}

double? maxOf(List<double> xs) {
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a > b ? a : b);
}

// ----------------------------------------------------------------------
// BenchRecord
// ----------------------------------------------------------------------
/// One benchmark summary. Only the keys relevant to [kind] are set; the
/// rest stay out of the JSON. Mirrors the metric surface of the iOS
/// EngineBench (`llm` / `tts` / `asr` / `vlm`).
class BenchRecord {
  BenchRecord({
    required this.kind,
    required this.model,
    required this.runs,
    this.prompt,
    this.voice,
    this.maxNewTokens,
    this.metrics = const {},
    this.perRun = const {},
  }) : timestamp = DateTime.now();

  final String kind;
  final String model;
  final int runs;
  final String? prompt;
  final String? voice;
  final int? maxNewTokens;

  /// Scalar summary metrics (e.g. best_tok_s, median_tok_s, ttft_ms).
  final Map<String, double> metrics;

  /// Raw per-run series so exported sessions stay analyzable.
  final Map<String, List<double>> perRun;

  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'model': model,
      'runs': runs,
      if (prompt != null) 'prompt': prompt,
      if (voice != null) 'voice': voice,
      if (maxNewTokens != null) 'max_new_tokens': maxNewTokens,
      'timestamp': timestamp.toUtc().toIso8601String(),
      ...metrics,
      ...perRun.map((k, v) => MapEntry('per_run_$k', v)),
    };
  }
}

// ----------------------------------------------------------------------
// BenchSession — process-wide log + JSON export
// ----------------------------------------------------------------------
/// Accumulates every completed benchmark across the four tabs and
/// exports the whole session as a single `.json` FILE (device identity
/// in the envelope so results from different phones stay attributable).
class BenchSession extends ChangeNotifier {
  BenchSession._();
  static final BenchSession instance = BenchSession._();

  static const _channel = MethodChannel('engine_bench');

  final List<BenchRecord> _records = [];
  List<BenchRecord> get records => List.unmodifiable(_records);
  bool get isEmpty => _records.isEmpty;

  void add(BenchRecord record) {
    _records.add(record);
    notifyListeners();
  }

  void clear() {
    _records.clear();
    notifyListeners();
  }

  // --------------------------------------------------------------------
  // Device identity
  // --------------------------------------------------------------------
  Future<Map<String, String>> _deviceInfo() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'device_info',
      );
      if (raw != null) {
        return raw.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // Fall through to the dart:io fallback below.
    }
    return {
      'model': 'unknown',
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
    };
  }

  // --------------------------------------------------------------------
  // Export
  // --------------------------------------------------------------------
  Future<Map<String, dynamic>> _buildReport() async {
    return {
      'device': await _deviceInfo(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'results': _records.map((r) => r.toJson()).toList(),
    };
  }

  /// Serialize the session to a temp `.json` file and return its path.
  Future<String> writeReportFile() async {
    final report = await _buildReport();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    final device =
        (report['device'] as Map)['model']?.toString() ?? 'device';
    final safeDevice =
        device.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/enginebench-$safeDevice-$stamp.json';
    await File(path).writeAsString(json);
    return path;
  }

  /// Write the report and hand it to the system share sheet as a file.
  Future<String> share() async {
    final path = await writeReportFile();
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/json')],
      subject: 'EngineBench results',
    );
    return path;
  }
}
