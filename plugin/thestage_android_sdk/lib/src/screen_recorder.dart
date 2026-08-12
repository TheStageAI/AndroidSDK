import 'package:flutter/services.dart';

import 'method_channels.dart';

/// In-app screen capture → the device gallery (`Movies/`).
///
/// Captures the screen via `MediaProjection` and muxes an audio track
/// that mixes the app's playback (TTS) with the mic, so a recorded demo
/// carries both sides of the conversation. Requesting `start()` triggers
/// the one-time system screen-capture consent dialog; a foreground
/// service keeps the capture alive while recording.
class TheStageScreenRecorder {
  TheStageScreenRecorder._();

  static const MethodChannel _channel = MethodChannel(MethodChannels.main);

  /// Whether a recording is currently in progress.
  static Future<bool> isRecording() async {
    final v = await _channel.invokeMethod<bool>(
      MethodRoute.screenRecorderIsRecording,
    );
    return v ?? false;
  }

  /// Begin recording. Prompts for screen-capture consent on first use.
  static Future<void> start() =>
      _channel.invokeMethod<void>(MethodRoute.screenRecorderStart);

  /// Stop recording and save the clip to the gallery.
  static Future<void> stop() =>
      _channel.invokeMethod<void>(MethodRoute.screenRecorderStop);
}
