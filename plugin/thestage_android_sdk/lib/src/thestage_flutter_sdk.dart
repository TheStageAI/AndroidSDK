import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// ModelAvailability
// ---------------------------------------------------------------------------
/// Whether a model bundle is available for THIS device, as reported by
/// [TheStageFlutterSDK.check_model_availability] — resolvable before
/// [TheStageFlutterSDK.initialize], with no token and no download.
enum ModelAvailability {
  /// A published remote bundle exists for this device (HF).
  remote,

  /// The given path is a local bundle present on disk.
  local,

  /// Nothing available — see [ModelAvailabilityResult.reason].
  none,

  /// Availability could not be determined (SDK not initialized, or a
  /// transport failure during the probe).
  unknown,
}

ModelAvailability _availabilityFromRaw(String? raw) {
  switch (raw) {
    case 'remote':
      return ModelAvailability.remote;
    case 'local':
      return ModelAvailability.local;
    case 'none':
      return ModelAvailability.none;
    default:
      return ModelAvailability.unknown;
  }
}

/// Detail behind a [ModelAvailability].
enum AvailabilityReason {
  repoNotFound,
  variantUnavailable,

  /// `aipack_pack` — Play AI pack delivered or fetchable
  /// (install-time and on-demand alike).
  aipackPack,
  localMissing,
  networkUnreachable,
  notInitialized,
}

AvailabilityReason? _reasonFromRaw(String? raw) {
  switch (raw) {
    case 'repo_not_found':
      return AvailabilityReason.repoNotFound;
    case 'variant_unavailable':
      return AvailabilityReason.variantUnavailable;
    case 'aipack_pack':
      return AvailabilityReason.aipackPack;
    case 'local_missing':
      return AvailabilityReason.localMissing;
    case 'network_unreachable':
      return AvailabilityReason.networkUnreachable;
    case 'not_initialized':
      return AvailabilityReason.notInitialized;
    default:
      return null;
  }
}

/// Compute backend a remote bundle targets.
enum Compute { npu, cpu, gpu }

Compute? _computeFromRaw(String? raw) {
  switch (raw) {
    case 'npu':
      return Compute.npu;
    case 'cpu':
      return Compute.cpu;
    case 'gpu':
      return Compute.gpu;
    default:
      return null;
  }
}

/// Result of [TheStageFlutterSDK.check_model_availability].
class ModelAvailabilityResult {
  /// The headline answer (remote / local / none / unknown).
  final ModelAvailability availability;

  /// Detail behind [availability], when one applies.
  final AvailabilityReason? reason;

  /// Detected device variant (SoC). Set only on a `remote` result.
  final String? variant;

  /// Backend the matched remote bundle runs on. Set only on `remote`.
  final Compute? compute;

  /// The matched URL (remote) or path (local), when one was found.
  final String? source;

  /// Compressed bundle size (remote) or on-disk size (local), bytes.
  final int? bundleSizeBytes;

  const ModelAvailabilityResult({
    required this.availability,
    this.reason,
    this.variant,
    this.compute,
    this.source,
    this.bundleSizeBytes,
  });

  factory ModelAvailabilityResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return ModelAvailabilityResult(
      availability: _availabilityFromRaw(map['availability'] as String?),
      reason: _reasonFromRaw(map['reason'] as String?),
      variant: map['variant'] as String?,
      compute: _computeFromRaw(map['compute'] as String?),
      source: map['source'] as String?,
      bundleSizeBytes: (map['bundle_size_bytes'] as num?)?.toInt(),
    );
  }
}

// ---------------------------------------------------------------------------
// Typed exceptions (Android-only error surfaces)
// ---------------------------------------------------------------------------

/// Thrown when the input exceeds the LLM bundle's compiled capacity
/// (Genie's static-cache constraint). Apps surface this with a
/// "shorten your input" UI.
class InputTooLongException implements Exception {
  InputTooLongException({required this.message});
  final String message;

  @override
  String toString() => 'InputTooLongException: $message';
}

/// Thrown when one sentence in streamed input exceeds the bundle's
/// compiled capacity. Apps typically surface a transient "sentence too
/// long" banner and continue.
class SentenceTooLongException implements Exception {
  SentenceTooLongException({required this.message});
  final String message;

  @override
  String toString() => 'SentenceTooLongException: $message';
}

/// Thrown by [TheStageFlutterSDK.start_model] when a bundle-backed
/// model can't be loaded because its on-disk files are missing,
/// incomplete or malformed — e.g. an OS cache-wipe removed the
/// extracted engines, a partial download left the bundle without its
/// `llm/` dir / `encoder_spec.json` / `metadata.json`, or a
/// Keystore/DEK reset left the sealed ctx-bins unrecoverable. Apps
/// surface this with a "reconnect and reload" UI; reloading re-fetches
/// the bundle.
class ModelUnavailableException implements Exception {
  ModelUnavailableException({required this.message});
  final String message;

  @override
  String toString() => 'ModelUnavailableException: $message';
}

/// Rethrows known PlatformExceptions as typed Dart exceptions; passes
/// everything else through. The plugin forwards the SDK's symbolic
/// error code (`INPUT_TOO_LONG` / `SENTENCE_TOO_LONG` /
/// `MODEL_UNAVAILABLE`) as `PlatformException.code`.
Never _rethrowTyped(PlatformException e) {
  if (e.code == 'INPUT_TOO_LONG') {
    throw InputTooLongException(message: e.message ?? 'Input too long');
  }
  if (e.code == 'SENTENCE_TOO_LONG') {
    throw SentenceTooLongException(
      message: e.message ?? 'One of the sentences is too long',
    );
  }
  if (e.code == 'MODEL_UNAVAILABLE') {
    throw ModelUnavailableException(
      message: e.message ?? 'Model unavailable',
    );
  }
  throw e;
}

// ---------------------------------------------------------------------------
// TheStageFlutterSDK
// ---------------------------------------------------------------------------
class TheStageFlutterSDK {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const EventChannel _progressChannel = EventChannel(
    MethodChannels.progress,
  );
  static const EventChannel _streamChannel = EventChannel(
    MethodChannels.ttsStream,
  );
  static const EventChannel _logsChannel = EventChannel(
    MethodChannels.logs,
  );
  static StreamSubscription<dynamic>? _logsSub;

  static StreamController<Map<String, dynamic>>? _streamEvents;
  static int _nextStreamOrdinal = 0;

  static void _ensureStreamChannel() {
    if (_streamEvents != null) return;
    _streamEvents = StreamController<Map<String, dynamic>>.broadcast();
    _streamChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<Object?, Object?>;
      _streamEvents!.add(
        map.map((key, value) => MapEntry(key.toString(), value)),
      );
    }, onError: (e) => _streamEvents!.addError(e));
  }

  /// Model download / preparation progress. Each event is a map,
  /// carrying `model_name` + `phase`, and exactly one of:
  ///  - `progress` (0..1) — a normal progress event; or
  ///  - `status` (no `progress`) — an AI-pack fetch is parked
  ///    waiting on the network or the user:
  ///      * `waiting_for_confirmation` — the download needs the
  ///        user's OK to use cellular (>200 MB off Wi-Fi). Show
  ///        Play's confirmation dialog from your Activity
  ///        (`AiPackManager.showConfirmationDialog(launcher)`); the
  ///        fetch resumes automatically once approved.
  ///      * `waiting_for_wifi` — parked until an unmetered network
  ///        is available; prompt the user to connect to Wi-Fi.
  ///    HF-repo and local sources never emit `status`.
  static Stream<Map<String, dynamic>> get on_progress {
    return _progressChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<Object?, Object?>;
      return map.map((key, value) => MapEntry(key.toString(), value));
    });
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  static Future<void> initialize({required String api_token}) async {
    ensureDeveloperLogs();
    await _channel.invokeMethod(
      MethodRoute.initialize,
      {'api_token': api_token},
    );
  }

  /// Mirror the SDK's developer log stream into `flutter run`.
  ///
  /// The native SDK logs its lifecycle (model load/unload, download,
  /// cache, recovery, coarse timings) to `adb logcat`, which
  /// `flutter run` does not surface. This subscribes to the plugin's
  /// `logs` EventChannel and [debugPrint]s each line so it shows up in
  /// the Flutter console. Idempotent, and a no-op in release builds.
  /// Called automatically by [initialize]; call it earlier if you want
  /// the pre-initialize lines too. Lines are path-sanitized and carry
  /// no user content. Mirrors the Apple SDK's `ensureDeveloperLogs`.
  static void ensureDeveloperLogs() {
    if (!kDebugMode) return;
    if (_logsSub != null) return;
    _logsSub = _logsChannel.receiveBroadcastStream().listen(
      (event) => debugPrint('[TheStage] $event'),
      onError: (Object e) =>
          debugPrint('[TheStage] log stream error: $e'),
    );
  }

  static Future<Map<String, dynamic>> start_model({
    required String model_name,
    required String engines_path,
    String? model_type,
    String device = 'gpu',
    String revision = '',
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>(MethodRoute.startModel, {
            'model_name': model_name,
            'engines_path': engines_path,
            'device': device,
            'revision': revision,
            if (model_type != null) 'model_type': model_type,
            if (devices != null) 'devices': devices,
            if (config != null) 'config': config,
          });
      return _asMap(result);
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  static Future<Map<String, dynamic>> stop_model({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.stopModel,
      {'model_name': model_name},
    );
    return _asMap(result);
  }

  // -------------------------------------------------------------------------
  // Batch Inference
  // -------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> infer({
    required String model_name,
    required Map<String, dynamic> input_json,
  }) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        MethodRoute.infer,
        {
          'model_name': model_name,
          'input_json': input_json,
        },
      );
      if (result == null) return [];
      return result
          .map((item) => _asMap(item as Map<Object?, Object?>))
          .toList();
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  // -------------------------------------------------------------------------
  // Streaming Inference
  // -------------------------------------------------------------------------

  /// Stream inference results (TTS audio chunks or LLM text tokens).
  ///
  /// Audio chunks: `{kind: 'audio', audio: Float32List, sample_rate, is_final}`
  /// Text chunks: `{kind: 'text', delta: String, is_final}`
  ///
  /// `input_json` accepts model-specific keys. For TTS pipelines you may
  /// pass an optional nested `stream_config` map to tune codec-side audio
  /// chunking.
  ///
  /// Pass `text: ''` to start a push-mode stream driven by [send] /
  /// [finish_stream]. Unknown keys are ignored.
  static Stream<Map<String, dynamic>> infer_stream({
    required String model_name,
    required Map<String, dynamic> input_json,
    String? stream_id,
  }) async* {
    _ensureStreamChannel();
    final id = stream_id ?? _makeStreamId(model_name);
    await _channel.invokeMethod(MethodRoute.startStream, {
      'model_name': model_name,
      'input_json': input_json,
      'stream_id': id,
    });
    await for (final chunk in _streamEvents!.stream) {
      if (chunk['stream_id'] != id) continue;
      yield chunk;
      if (chunk['is_final'] == true) return;
    }
  }

  static Future<void> send({
    required String stream_id,
    required String text,
  }) async {
    await _channel.invokeMethod(MethodRoute.send, {
      'stream_id': stream_id,
      'text': text,
    });
  }

  static Future<void> finish_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.finishStream, {
      'stream_id': stream_id,
    });
  }

  static Future<void> stop_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.stopStream, {
      'stream_id': stream_id,
    });
  }

  // -------------------------------------------------------------------------
  // Components
  // -------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> list_components({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.listComponents,
      {'model_name': model_name},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> load_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.loadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> unload_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.unloadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Utilities
  // -------------------------------------------------------------------------

  static Future<String?> get_bundled_engine_path(String filename) async {
    return await _channel.invokeMethod<String?>(
      MethodRoute.bundledEnginePath,
      {'filename': filename},
    );
  }

  // -------------------------------------------------------------------------
  // Android-only API
  // -------------------------------------------------------------------------

  /// Download + extract engines for `repo_id@revision` without loading
  /// the model into memory. Returns the local engines directory path —
  /// pass it as `engines_path` to [start_model] later to skip the
  /// download phase. Progress events are emitted on [on_progress] with
  /// the `repo_id` as the `model_name` field. Android-only.
  static Future<String> prefetch_model({
    required String repo_id,
    String? model_type,
    String revision = '',
    Map<String, dynamic>? config,
  }) async {
    try {
      final res = await _channel.invokeMethod<String>(
        MethodRoute.androidPrefetchModel,
        {
          'repo_id': repo_id,
          if (model_type != null) 'model_type': model_type,
          'revision': revision,
          if (config != null) 'config': config,
        },
      );
      return res ?? '';
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Check whether a model bundle is available for THIS device BEFORE
  /// loading it — no [initialize], no token, no download (HEAD-only for
  /// HF repos, a file stat for local paths).
  ///
  /// [model_path] is an HF repo id (e.g.
  /// `TheStageAI/thewhisper-large-v3-turbo`) or a local bundle path. Use
  /// the result to pick a model / show UI before the heavier
  /// [start_model] call. Android-only.
  static Future<ModelAvailabilityResult> check_model_availability({
    required String model_path,
    String revision = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.androidCheckModelAvailability,
        {
          'model_path': model_path,
          'revision': revision,
        },
      );
      return ModelAvailabilityResult.fromMap(_asMap(result));
    } on PlatformException {
      // Native never throws here; guard defensively anyway.
      return const ModelAvailabilityResult(
        availability: ModelAvailability.unknown,
        reason: AvailabilityReason.networkUnreachable,
      );
    }
  }

  /// Report this process's memory as the OS accounts it.
  ///
  /// `footprint_mb` is total PSS in MB (the Android analogue of iOS
  /// `phys_footprint` — what the low-memory killer tracks); `resident_mb`
  /// is RSS in MB (the smaller, secondary diagnostic). Returns `null` if
  /// the platform couldn't read the footprint.
  static Future<Map<String, double>?> memory_footprint() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.memoryFootprint,
    );
    if (result == null) return null;
    final map = _asMap(result);
    final footprint = (map['footprint_mb'] as num?)?.toDouble();
    final resident = (map['resident_mb'] as num?)?.toDouble();
    if (footprint == null || footprint < 0) return null;
    return {
      'footprint_mb': footprint,
      if (resident != null && resident >= 0) 'resident_mb': resident,
    };
  }

  // -------------------------------------------------------------------------
  // Private Helpers
  // -------------------------------------------------------------------------

  static String _makeStreamId(String model_name) {
    _nextStreamOrdinal++;
    return '${model_name}_${DateTime.now().microsecondsSinceEpoch}_'
        '$_nextStreamOrdinal';
  }

  static Map<String, dynamic> _asMap(Map<Object?, Object?>? value) {
    if (value == null) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
