// Channel contract of the voice-agent Dart API: what each call sends and
// how the start result decodes. Runs against a mocked platform channel.

// The deprecated forwarders are exercised on purpose.
// ignore_for_file: deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('thestage_android_sdk');
  final calls = <MethodCall>[];
  Object? startResult;

  setUp(() {
    calls.clear();
    startResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'voice_agent.start') return startResult;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MethodCall last(String method) =>
      calls.lastWhere((c) => c.method == method);

  test('start returns and stores normalized capabilities', () async {
    startResult = <Object?, Object?>{
      'listening': true,
      'transcribing': true,
      'responding': true,
      'speaking': false,
      'reasons': <Object?, Object?>{'speaking': 'no tts configured'},
    };
    final agent = TSVoiceAgent();
    final caps = await agent.start(config: {'vad': 'v'});
    expect(caps['speaking'], isFalse);
    expect(caps['responding'], isTrue);
    expect(caps['reasons'], {'speaking': 'no tts configured'});
    expect(agent.capabilities, caps);
    expect(
      (last('voice_agent.start').arguments as Map)
          .containsKey('require_full_stack'),
      isFalse,
    );
  });

  test('require_full_stack is sent; a null result is empty', () async {
    final agent = TSVoiceAgent();
    final caps = await agent.start(config: {}, require_full_stack: true);
    expect(caps, isEmpty);
    expect(
      (last('voice_agent.start').arguments as Map)['require_full_stack'],
      isTrue,
    );
  });

  test('set_voice sends only the given fields', () async {
    final agent = TSVoiceAgent();
    await agent.set_voice(voice_dir: '/packs/dave', language: 'french');
    expect(last('voice_agent.set_voice').arguments, {
      'voice_dir': '/packs/dave',
      'language': 'french',
    });
    await agent.set_voice(voice_dir: '');
    expect(last('voice_agent.set_voice').arguments, {'voice_dir': ''});
    final before = calls.length;
    await agent.set_voice();
    expect(calls.length, before, reason: 'no fields, no call');
  });

  test('deprecated forwarders keep working', () async {
    final agent = TSVoiceAgent();
    await agent.setVoice('paul');
    expect(last('voice_agent.set_voice').arguments, {'voice_id': 'paul'});
    await agent.updateInterruptConfig(interruptMinSpeechMs: 400);
    expect(
      last('voice_agent.update_interrupt_config').arguments,
      {'interrupt_min_speech_ms': 400},
    );
    await agent.sendRequest('hi');
    expect(last('voice_agent.send_request').arguments, {'text': 'hi'});
  });

  test('set_system_prompt and update_interrupt_config routes', () async {
    final agent = TSVoiceAgent();
    await agent.set_system_prompt('be brief');
    expect(
      last('voice_agent.set_system_prompt').arguments,
      {'system_prompt': 'be brief'},
    );
    await agent.update_interrupt_config(interrupt_mode: 'none');
    expect(
      last('voice_agent.update_interrupt_config').arguments,
      {'interrupt_mode': 'none'},
    );
  });

  test('tts_levels decodes the tts_levels event channel', () async {
    const levels =
        EventChannel('thestage_android_sdk/voice_agent_tts_levels');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      levels,
      MockStreamHandler.inline(onListen: (args, sink) {
        sink.success(0.5);
        sink.success(1);
        sink.success(0.0);
        sink.endOfStream();
      }),
    );
    final agent = TSVoiceAgent();
    expect(await agent.tts_levels.toList(), [0.5, 1.0, 0.0]);
    messenger.setMockStreamHandler(levels, null);
  });
}
