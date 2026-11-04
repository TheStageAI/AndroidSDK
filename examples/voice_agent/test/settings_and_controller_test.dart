// App logic that runs without a device: the settings → config map, and
// the controller's start / stop recovery against a mocked channel.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'package:voice_agent/backend/settings_model.dart';
import 'package:voice_agent/backend/voice_agent_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceAgentSettings', () {
    test('config names no device, so the SDK picks the best bundle', () {
      final c = VoiceAgentSettings().toConfig('');
      expect(c.keys.where((k) => k.endsWith('_device')), isEmpty);
      expect(c.keys.where((k) => k.endsWith('_revision')), isEmpty);
      expect(c['turn_detector'], isNotEmpty);
    });

    test('local provider sends the on-device repo, no cloud keys', () {
      final c = VoiceAgentSettings().toConfig('sk-test');
      expect(c['llm_provider'], 'local');
      expect(c['llm'], VoiceAgentSettings.hfLlmRepo);
      expect(c.containsKey('llm_api_key'), isFalse);
      expect(c['max_tokens'], 256);
    });

    test('switching to the cloud gives it a cloud model, and back', () {
      final s = VoiceAgentSettings()..selectProvider('openai_compatible');
      expect(s.llmModel, VoiceAgentSettings.cloudDefaultModel);
      final c = s.toConfig('sk-test');
      expect(c['llm_model'], VoiceAgentSettings.cloudDefaultModel);
      expect(c['llm_api_key'], 'sk-test');
      expect(c.containsKey('llm'), isFalse);

      s.selectProvider('local');
      expect(s.llmModel, VoiceAgentSettings.hfLlmRepo);
    });

    test('a typed cloud model survives a re-select', () {
      final s = VoiceAgentSettings()
        ..selectProvider('openai_compatible')
        ..llmModel = 'my-model'
        ..selectProvider('openai_compatible');
      expect(s.llmModel, 'my-model');
    });

    test('bundle voices replace the fallback list', () {
      final s = VoiceAgentSettings();
      s.applyBundleVoices(['jo', 'emma'], current: 'emma');
      expect(s.voices, ['jo', 'emma']);
      expect(s.ttsVoice, 'emma');
      s.applyBundleVoices(['nova']);
      expect(s.ttsVoice, 'nova');
      s.selectTtsRepo('TheStageAI/neutts-multilingual');
      expect(s.voices, VoiceAgentSettings.fallbackVoices);
    });
  });

  group('VoiceAgentController', () {
    const channel = MethodChannel('thestage_android_sdk');
    final calls = <String>[];
    var failStart = false;

    setUp(() {
      calls.clear();
      failStart = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'voice_agent.start' && failStart) {
          throw PlatformException(code: 'load', message: 'VAD failed');
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('a failed start returns to idle with the error shown', () async {
      failStart = true;
      final agent = TSVoiceAgent();
      final c = VoiceAgentController(agent);
      await c.start(const {});
      expect(c.state, TSAgentState.idle);
      expect(c.busy, isFalse);
      expect(c.starting, isFalse);
      expect(c.error, contains('VAD failed'));
      expect(c.currentLoadingModel, isNull);
      // The half-started agent is torn down.
      expect(calls, contains('voice_agent.stop'));
      c.dispose();
      agent.dispose();
    });

    test('start clears a previous error and can be retried', () async {
      failStart = true;
      final agent = TSVoiceAgent();
      final c = VoiceAgentController(agent);
      await c.start(const {});
      failStart = false;
      await c.start(const {});
      expect(c.error, isNull);
      expect(c.busy, isFalse);
      c.dispose();
      agent.dispose();
    });
  });
}
