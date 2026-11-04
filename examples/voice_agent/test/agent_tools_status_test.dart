// Tool calls in the app: the `tool_calling` state's label and colour,
// and how `tool_started` / `tool_ended` events become transcript lines.
// Runs against mocked platform channels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'package:voice_agent/backend/settings_model.dart';
import 'package:voice_agent/backend/voice_agent_controller.dart';
import 'package:voice_agent/models/chat_message.dart';
import 'package:voice_agent/ui/widgets/agent_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const main = MethodChannel('thestage_android_sdk');
  const events = EventChannel('thestage_android_sdk/voice_agent_events');
  const progress = EventChannel('thestage_android_sdk/progress');
  const levels =
      EventChannel('thestage_android_sdk/voice_agent_tts_levels');

  final script = <Map<String, Object?>>[
    {'kind': 'state_changed', 'state': 'thinking'},
    {
      'kind': 'tool_started',
      'name': 'get_weather',
      'arguments': '{"city": "Paris"}',
    },
    {'kind': 'state_changed', 'state': 'tool_calling'},
    {'kind': 'tool_ended', 'name': 'get_weather', 'content': '20°C'},
  ];

  setUp(() {
    messenger.setMockMethodCallHandler(main, (call) async => null);
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (args, sink) {
        for (final e in script) {
          sink.success(e);
        }
      }),
    );
    messenger.setMockStreamHandler(
      progress,
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    messenger.setMockStreamHandler(
      levels,
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(main, null);
    messenger.setMockStreamHandler(events, null);
    messenger.setMockStreamHandler(progress, null);
    messenger.setMockStreamHandler(levels, null);
  });

  test('tool_calling has its own label and colour', () {
    expect(TSAgentState.fromString('tool_calling'),
        TSAgentState.tool_calling);
    expect(agentStateColor(TSAgentState.tool_calling), Colors.indigo);
  });

  test('tool events become tool lines; tool_calling is shown', () async {
    final c = VoiceAgentController(TSVoiceAgent());
    await c.start({'llm_tools': 'web'});
    await pumpEventQueue();

    expect(c.state, TSAgentState.tool_calling);
    expect(agentStateLabel(c), 'Calling tool...');
    expect(c.canInterrupt, isTrue);

    final tools =
        c.messages.where((m) => m.role == MessageRole.tool).toList();
    expect(tools.length, 2);
    expect(tools[0].meta?['phase'], 'started');
    expect(tools[0].text, contains('get_weather'));
    expect(tools[0].text, contains('Paris'));
    expect(tools[1].meta?['phase'], 'ended');
    expect(tools[1].meta?['content'], '20°C');
    c.dispose();
  });

  test('settings send llm_tools, default web, with the tool pattern', () {
    final s = VoiceAgentSettings();
    final config = s.toConfig('key');
    expect(config['llm_tools'], 'web');
    expect(
      config['system_prompt'] as String,
      contains('Tool pattern (always):'),
    );
  });
}
