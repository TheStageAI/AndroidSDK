import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_tutor_small_llms/guides.dart';
import 'package:thestage_tutor_small_llms/tools.dart';

/// A stream that replays one scripted reply per request and records
/// each request's `input_json`.
class _Script {
  final List<List<Map<String, dynamic>>> replies;
  final requests = <Map<String, dynamic>>[];

  _Script(this.replies);

  Stream<Map<String, dynamic>> call(Map<String, dynamic> input) {
    requests.add(input);
    return Stream.fromIterable(replies[requests.length - 1]);
  }
}

Map<String, dynamic> _text(String t) => {'kind': 'text_delta', 'delta': t};

Map<String, dynamic> _call(String name, Map<String, dynamic> args) =>
    {'kind': 'tool_call', 'name': name, 'arguments': args};

Map<String, dynamic> _final(String stop, String text) => {
      'kind': 'final',
      'is_final': true,
      'stop_reason': stop,
      'final_text': text,
      'delta': '<raw markup>',
    };

void main() {
  group('CannedTools', () {
    test('weather, time and search answer from the tables', () {
      expect(
        CannedTools.run('get_weather', {'city': 'Paris'}),
        'Now in Paris: 18 °C, partly cloudy.',
      );
      expect(
        CannedTools.run('get_local_time', {'city': 'tokyo'}),
        'Local time in Tokyo: Wednesday, Apr 11 2026, 15:30.',
      );
      expect(
        CannedTools.run('web_search', {'query': 'inventor of the telephone'}),
        contains('Alexander Graham Bell'),
      );
    });

    test('unknown inputs get a sentence, unknown tools an error', () {
      expect(
        CannedTools.run('get_weather', {'city': 'Atlantis'}),
        'Could not find that city.',
      );
      expect(
        CannedTools.run('web_search', {'query': 'zzz'}),
        'No web results found for that query.',
      );
      expect(CannedTools.run('dial_phone', {}), contains('"ok":false'));
    });
  });

  group('runToolTurn', () {
    test('runs the call, sends the result back, joins the text', () async {
      final s = _Script([
        [
          _text('One moment.'),
          _call('get_weather', {'city': 'Paris'}),
          _final('tool_calls', 'One moment.'),
        ],
        [
          _text("It's 18 °C and partly cloudy in Paris."),
          _final('eos', "It's 18 °C and partly cloudy in Paris."),
        ],
      ]);
      final lines = <String>[];
      final t = await runToolTurn(
        "What's the weather in Paris right now?",
        stream: s.call,
        tools: ToolRecipes.tools,
        system: ToolRecipes.system,
        log: lines.add,
      );
      expect(t.requests, 2);
      expect(t.stopReason, 'eos');
      expect(t.answer, "One moment. It's 18 °C and partly cloudy in Paris.");
      expect(t.steps.single.name, 'get_weather');
      expect(t.steps.single.result, 'Now in Paris: 18 °C, partly cloudy.');
      expect(lines.first, '  [tool_call] get_weather {"city":"Paris"}');

      // The second request: the user turn, the call turn, the result.
      final second = s.requests[1];
      expect(second['tools'], ToolRecipes.tools);
      expect(second.containsKey('max_tool_rounds'), isFalse);
      final messages = second['messages'] as List;
      expect(messages, hasLength(3));
      expect(messages[1], {
        'role': 'assistant',
        'content': 'One moment.',
        'tool_calls': [
          {
            'name': 'get_weather',
            'arguments': {'city': 'Paris'},
          },
        ],
      });
      expect(messages[2], {
        'role': 'tool',
        'name': 'get_weather',
        'content': 'Now in Paris: 18 °C, partly cloudy.',
      });
      // The first request saw only the question.
      expect(s.requests[0]['messages'] as List, hasLength(1));
    });

    test('a reply without calls takes one request', () async {
      final s = _Script([
        [_text("You're welcome!"), _final('eos', "You're welcome!")],
      ]);
      final t = await runToolTurn(
        "Thanks, that's all for now.",
        stream: s.call,
        tools: ToolRecipes.tools,
        system: ToolRecipes.system,
      );
      expect(t.requests, 1);
      expect(t.steps, isEmpty);
      expect(t.answer, "You're welcome!");
    });

    test('after maxRounds of calls the model must answer', () async {
      final round = [
        _call('web_search', {'query': 'x'}),
        _final('tool_calls', ''),
      ];
      final s = _Script([
        round,
        round,
        [_text('I could not find it.'), _final('max_tool_rounds', '')],
      ]);
      final t = await runToolTurn(
        'Find x.',
        stream: s.call,
        tools: ToolRecipes.tools,
        system: ToolRecipes.system,
        maxRounds: 2,
      );
      expect(t.requests, 3);
      expect(t.steps, hasLength(2));
      expect(t.stopReason, 'max_tool_rounds');
      expect(s.requests[2]['max_tool_rounds'], 0);
      expect(s.requests[1].containsKey('max_tool_rounds'), isFalse);
    });
  });

  group('scoreToolTurn', () {
    ToolTurn turn(List<ToolStep> steps, String answer) =>
        ToolTurn(steps, answer, 'eos', steps.length + 1);

    final weather = Guides.toolCases[0];
    final none = Guides.toolCases[3];

    test('right tool, right argument, grounded answer', () {
      final s = scoreToolTurn(
        weather,
        turn([
          (
            name: 'get_weather',
            arguments: {'city': 'Paris, France'},
            result: '',
          ),
        ], 'It is 18 °C in Paris.'),
      );
      expect(
          (s.choice, s.arguments, s.grounded, s.points), (true, true, true, 2));
    });

    test('wrong tool and wrong argument score apart', () {
      final wrong = scoreToolTurn(
        weather,
        turn([
          (name: 'web_search', arguments: {'query': 'Paris'}, result: '')
        ], ''),
      );
      expect(wrong.points, 0);
      expect(wrong.note, 'wrong tool: web_search');
      final arg = scoreToolTurn(
        weather,
        turn([
          (name: 'get_weather', arguments: {'city': 'Rome'}, result: '')
        ], ''),
      );
      expect((arg.choice, arg.arguments, arg.points), (true, false, 1));
    });

    test('no tool wanted: a call loses both points', () {
      expect(scoreToolTurn(none, turn([], 'Bye!')).points, 2);
      final called = scoreToolTurn(
        none,
        turn([(name: 'get_weather', arguments: {}, result: '')], ''),
      );
      expect(called.points, 0);
    });
  });

  group('guide 5', () {
    test('runs every case and prints the score', () async {
      // A model that always answers without a tool.
      Stream<Map<String, dynamic>> stream(Map<String, dynamic> _) =>
          Stream.fromIterable([_text('Hello.'), _final('eos', 'Hello.')]);
      final lines = <String>[];
      await Guides('m', lines.add, stream: stream).run(5);
      expect(lines.first, contains('Guide 5 / Tool calling'));
      expect(
        lines.last,
        '  score: 2/8 (tool choice 1/4, arguments 1/4; '
        'answer from the result 1/4)',
      );
    });

    test('skips a model without tools', () async {
      final lines = <String>[];
      await Guides('m', lines.add, supportsTools: false).run(5);
      expect(lines.last, 'this model cannot call tools. skip.');
    });
  });

  test('a leaked call in the answer scores zero', () {
    expect(leaksToolMarkup('[get_weather(city="Paris")]', ['get_weather']),
        isTrue);
    expect(leaksToolMarkup('<|tool_call_start|>[x()]', const []), isTrue);
    expect(leaksToolMarkup('See [the docs](x) (soon).', ['get_weather']),
        isFalse);
  });
}
