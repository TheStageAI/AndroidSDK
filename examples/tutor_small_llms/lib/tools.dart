import 'dart:convert';

// ---------------------------------------------------------------------------
// Guide 5: the tools, their canned answers, the Flutter tool loop and the
// score. Kept apart from the SDK call so the tests can script the stream.
// ---------------------------------------------------------------------------

/// Starts one `infer_stream` request with [input] (the `input_json`).
typedef StreamFn = Stream<Map<String, dynamic>> Function(
  Map<String, dynamic> input,
);

/// What the model is told about the three tools.
class ToolRecipes {
  /// The voice assistant prompt the SDK ships as
  /// `DefaultTools.voice_system_prompt`.
  static const system =
      "You are a short on-device voice assistant. Answer in complete "
      "sentences. Use the user's language.\n\n"
      "Tools are only for live facts the user asked for (weather, time, "
      "search, wiki, math). Greetings, chit-chat, and opinions: answer "
      "yourself — no tool, no filler, no city, no weather.\n\n"
      "Tool pattern (always):\n"
      "1) Need a tool? One short filler, then the exact markup from the "
      "tools section (do not speak the markup).\n"
      "2) After the tool result: 1–2 sentences using only that result.\n"
      "3) No tool needed? Answer the question directly.\n\n"
      "Never invent facts. Never name a place, time, or number the user "
      "did not ask and the tool did not return. Never read JSON aloud. "
      "Never stop after one word.";

  /// `get_weather` (with a description that says when to use it),
  /// `get_local_time` and `web_search`.
  static const tools = <Map<String, dynamic>>[
    {
      'name': 'get_weather',
      'description': 'Current outdoor conditions and air temperature in °C '
          'at one named place. This is live data: use it whenever a '
          'correct answer depends on what the weather is like there now. '
          'Not historical or multi-day forecast data. Argument: the place '
          'the user named, in the form they said it. Returns a short '
          'plain-text summary to paraphrase; do not read it out verbatim.',
      'parameters': {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': 'City name, e.g. Paris or Tokyo',
          },
        },
        'required': ['city'],
      },
    },
    {
      'name': 'get_local_time',
      'description': 'Get the current local date and time in a city. '
          'Returns plain text — paraphrase it for the user.',
      'parameters': {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': 'City name, e.g. New York or Berlin',
          },
        },
        'required': ['city'],
      },
    },
    {
      'name': 'web_search',
      'description': 'Search the web for a short factual answer. Pass a '
          'concise query or question. The tool returns plain answer text '
          '— paraphrase it for the user; do not invent facts.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query or short question',
          },
        },
        'required': ['query'],
      },
    },
  ];
}

// ---------------------------------------------------------------------------
// Canned tools: fixed answers, no network, so every run is the same.
// ---------------------------------------------------------------------------
class CannedTools {
  static const _weather = {
    'paris': (18, 'partly cloudy'),
    'tokyo': (22, 'clear'),
    'berlin': (14, 'cloudy'),
    'london': (12, 'rainy'),
    'rome': (20, 'sunny'),
    'new york': (9, 'windy'),
  };

  static const _time = {
    'tokyo': 'Wednesday, Apr 11 2026, 15:30',
    'paris': 'Wednesday, Apr 11 2026, 08:30',
    'berlin': 'Wednesday, Apr 11 2026, 08:30',
    'london': 'Wednesday, Apr 11 2026, 07:30',
    'new york': 'Wednesday, Apr 11 2026, 02:30',
  };

  static const _search = [
    (
      ['telephone', 'phone'],
      'Alexander Graham Bell is commonly credited with inventing the '
          'telephone.',
    ),
    (['eiffel'], 'The Eiffel Tower in Paris is about 330 meters tall.'),
    (['capital of japan'], 'Tokyo is the capital of Japan.'),
  ];

  /// The result the model reads for [name] called with [args]: a short
  /// plain-text sentence, as the SDK's built-in tools return.
  static String run(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'get_weather':
        final city = _str(args['city']);
        final w = _lookup(city, _weather);
        if (w == null) return 'Could not find that city.';
        return 'Now in ${_title(city)}: ${w.$1} °C, ${w.$2}.';
      case 'get_local_time':
        final city = _str(args['city']);
        final t = _lookup(city, _time);
        if (t == null) return 'Could not find that city.';
        return 'Local time in ${_title(city)}: $t.';
      case 'web_search':
        final q = _str(args['query']).toLowerCase();
        if (q.isEmpty) return 'No search query was provided.';
        for (final (keys, answer) in _search) {
          if (keys.any(q.contains)) return answer;
        }
        return 'No web results found for that query.';
    }
    return jsonEncode({'ok': false, 'error': 'unknown tool $name'});
  }

  static String _str(Object? v) => (v is String ? v : '${v ?? ''}').trim();

  static T? _lookup<T>(String city, Map<String, T> table) {
    final k = city.toLowerCase();
    if (k.isEmpty) return null;
    // Longest name first, so "new york" wins over a shorter key.
    final names = table.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in names) {
      if (k.contains(name)) return table[name];
    }
    return null;
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// The Flutter tool loop
// ---------------------------------------------------------------------------
/// One call the model made and what the app answered.
typedef ToolStep = ({
  String name,
  Map<String, dynamic> arguments,
  String result,
});

/// One question, run to its answer.
class ToolTurn {
  final List<ToolStep> steps;

  /// Every `text_delta`, joined: what a user would see or hear.
  final String answer;
  final String stopReason;

  /// `infer_stream` requests the turn took.
  final int requests;

  const ToolTurn(this.steps, this.answer, this.stopReason, this.requests);
}

/// Asks [question] with [tools]: streams, and whenever the stream ends at
/// tool calls (`stop_reason == 'tool_calls'`), runs them with [run],
/// appends the call turn and the results to the history and asks again.
/// The request after [maxRounds] rounds of calls sends
/// `max_tool_rounds: 0`, so the model has to answer.
Future<ToolTurn> runToolTurn(
  String question, {
  required StreamFn stream,
  required List<Map<String, dynamic>> tools,
  required String system,
  String Function(String name, Map<String, dynamic> args) run = CannedTools.run,
  void Function(String line)? log,
  int maxRounds = 4,
  int maxNewTokens = 256,
}) async {
  final history = <Map<String, dynamic>>[
    {'role': 'user', 'content': question},
  ];
  final steps = <ToolStep>[];
  final answer = StringBuffer();
  var stopReason = '';
  var requests = 0;
  for (var round = 0; round <= maxRounds; round++) {
    final calls = <({String name, Map<String, dynamic> arguments})>[];
    var roundText = '';
    stopReason = '';
    requests += 1;
    final input = <String, dynamic>{
      'system_prompt': system,
      'messages': [for (final m in history) Map<String, dynamic>.from(m)],
      'tools': tools,
      if (round == maxRounds) 'max_tool_rounds': 0,
      'enable_thinking': false,
      'max_new_tokens': maxNewTokens,
    };
    // A later round's text continues the earlier one's.
    var separate = answer.isNotEmpty;
    await for (final chunk in stream(input)) {
      switch (chunk['kind']) {
        case 'text_delta':
          final delta = chunk['delta'] as String? ?? '';
          if (delta.isEmpty) break;
          if (separate && !delta.startsWith(RegExp(r'\s'))) {
            answer.write(' ');
          }
          separate = false;
          answer.write(delta);
        case 'tool_call':
          final name = chunk['name'] as String? ?? '';
          final args = Map<String, dynamic>.from(
            chunk['arguments'] as Map? ?? const {},
          );
          calls.add((name: name, arguments: args));
          log?.call('  [tool_call] $name ${jsonEncode(args)}');
        case 'final':
          stopReason = chunk['stop_reason'] as String? ?? '';
          roundText = chunk['final_text'] as String? ?? '';
      }
    }
    if (stopReason != 'tool_calls' || calls.isEmpty) break;
    history.add({
      'role': 'assistant',
      'content': roundText,
      'tool_calls': [
        for (final c in calls) {'name': c.name, 'arguments': c.arguments},
      ],
    });
    for (final c in calls) {
      final result = run(c.name, c.arguments);
      log?.call('  [tool_result] $result');
      steps.add((name: c.name, arguments: c.arguments, result: result));
      history.add({'role': 'tool', 'name': c.name, 'content': result});
    }
  }
  return ToolTurn(steps, answer.toString().trim(), stopReason, requests);
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------
/// One question of guide 5 and what a right turn looks like.
class ToolCase {
  final String ask;

  /// The tool to call, or null when the model should just answer.
  final String? tool;

  /// The argument to check, and a text it must contain (any case).
  final String? arg;
  final String? argContains;

  /// Texts from the canned result; the answer should use one of them.
  final List<String> answerUses;

  const ToolCase(
    this.ask, {
    this.tool,
    this.arg,
    this.argContains,
    this.answerUses = const [],
  });

  String get want => tool == null ? 'no tool' : '$tool($arg ≈ "$argContains")';
}

/// How a [ToolTurn] did on a [ToolCase].
class ToolScore {
  /// The first call is the right tool (or no call when none is wanted).
  final bool choice;

  /// The checked argument holds the expected text (true when no tool
  /// is wanted and none was called).
  final bool arguments;

  /// The answer repeats a fact from the result (informational).
  final bool grounded;

  final String note;

  const ToolScore(this.choice, this.arguments, this.grounded, this.note);

  int get points => (choice ? 1 : 0) + (arguments ? 1 : 0);
}

/// Tool-call markup a user would see or hear: a tagged call, or a bare
/// `[name(` for one of the offered tools.
bool leaksToolMarkup(String answer, Iterable<String> toolNames) {
  if (RegExp(r'<\|?tool_call|<function=|</?tool_call>').hasMatch(answer)) {
    return true;
  }
  return toolNames.any(
    (n) => RegExp(r'\[\s*' + RegExp.escape(n) + r'\s*\(').hasMatch(answer),
  );
}

ToolScore scoreToolTurn(
  ToolCase c,
  ToolTurn t, {
  Iterable<String> toolNames = const [],
}) {
  if (leaksToolMarkup(t.answer, toolNames)) {
    return const ToolScore(false, false, false, 'tool markup in the answer');
  }
  final first = t.steps.isEmpty ? null : t.steps.first;
  if (c.tool == null) {
    final ok = first == null;
    return ToolScore(
      ok,
      ok,
      true,
      ok
          ? 'ok — answered without a tool'
          : 'called ${first.name} (none wanted)',
    );
  }
  if (first == null) {
    return const ToolScore(false, false, false, 'no tool call');
  }
  final choice = first.name == c.tool;
  final value = '${first.arguments[c.arg] ?? ''}';
  final args =
      choice && value.toLowerCase().contains(c.argContains!.toLowerCase());
  final answer = t.answer.toLowerCase();
  final grounded = c.answerUses.isEmpty ||
      c.answerUses.any((s) => answer.contains(s.toLowerCase()));
  final String note;
  if (!choice) {
    note = 'wrong tool: ${first.name}';
  } else if (!args) {
    note = 'arguments: ${c.arg}=${jsonEncode(value)}';
  } else if (!grounded) {
    note = 'ok — tool and arguments; the answer does not use the result';
  } else {
    note = 'ok — tool, arguments, answer from the result';
  }
  return ToolScore(choice, args, grounded, note);
}
