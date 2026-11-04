import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import 'backend/settings_model.dart';
import 'ui/voice_chat_screen.dart';

// Secrets come from this app's secrets.json (TS_API_TOKEN, and
// OPENAI_API_KEY for the cloud LLM), injected at build/run time via:
//   flutter run --dart-define-from-file=secrets.json
const _apiToken = String.fromEnvironment('TS_API_TOKEN');
const _openAIKey = String.fromEnvironment('OPENAI_API_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceAgentApp());
}

class VoiceAgentApp extends StatelessWidget {
  const VoiceAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Agent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _agent = TSVoiceAgent();
  final _settings = VoiceAgentSettings();
  bool _initialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _agent.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_apiToken.isEmpty) {
      setState(() {
        _initError =
            'TS_API_TOKEN not set.\n'
            'Put it in this app\'s secrets.json, then run:\n'
            'flutter run --dart-define-from-file=secrets.json';
      });
      return;
    }
    // OPENAI_API_KEY is optional: only the remote
    // (openai_compatible) LLM provider needs it; the default is the
    // on-device LLM.
    try {
      await TheStageFlutterSDK.initialize(api_token: _apiToken);
      setState(() => _initialized = true);
    } catch (e) {
      setState(() => _initError = 'SDK initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _initError!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return VoiceChatScreen(
      agent: _agent,
      settings: _settings,
      openAIKey: _openAIKey,
    );
  }
}
