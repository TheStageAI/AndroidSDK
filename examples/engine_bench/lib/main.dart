import 'package:flutter/material.dart';

import 'backend/sdk_host.dart';
import 'tabs/asr_tab.dart';
import 'tabs/llm_tab.dart';
import 'tabs/tts_tab.dart';
import 'tabs/vlm_tab.dart';

// ----------------------------------------------------------------------
// EngineBench — benchmark the on-device engines (LLM / TTS / ASR / VLM)
// with the TheStage Android SDK. Each tab loads its model from Hugging
// Face on first use and reports decode tok/s, TTFT, and latency; the
// Share action exports the whole session as a JSON file.
//
// Token: TS_API_TOKEN in this app's secrets.json, injected at build
// time via
//   flutter run --dart-define-from-file=secrets.json
// ----------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EngineBenchApp());
}

class EngineBenchApp extends StatelessWidget {
  const EngineBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Engine Bench',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: SdkHost.instance.hasToken
          ? const _HomeShell()
          : const _MissingTokenScreen(),
    );
  }
}

// ----------------------------------------------------------------------
// _HomeShell — bottom-tab navigation over the four engine benches
// ----------------------------------------------------------------------
class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  static const _tabs = [LlmTab(), TtsTab(), AsrTab(), VlmTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'LLM',
          ),
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'TTS'),
          NavigationDestination(icon: Icon(Icons.mic_none), label: 'ASR'),
          NavigationDestination(icon: Icon(Icons.image_outlined), label: 'VLM'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// _MissingTokenScreen — shown when TS_API_TOKEN wasn't provided
// ----------------------------------------------------------------------
class _MissingTokenScreen extends StatelessWidget {
  const _MissingTokenScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engine Bench')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'TS_API_TOKEN not set.\n\n'
            'Put your token in this app\'s secrets.json, then run:\n'
            '  flutter run --release '
            '--dart-define-from-file=secrets.json',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
