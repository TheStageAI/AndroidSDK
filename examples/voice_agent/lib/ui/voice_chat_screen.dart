import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/settings_model.dart';
import '../backend/voice_agent_controller.dart';
import 'settings_screen.dart';
import 'widgets/agent_status.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/error_banner.dart';
import 'widgets/model_picker_bar.dart';
import 'widgets/transcript_area.dart';

// ============================================================================
// FRONTEND — top-level screen (pure composition)
// ============================================================================
// This widget owns the [VoiceAgentController] (the backend bridge) and wires
// the pieces together. It holds NO conversation logic itself — it only:
//   • creates / disposes the controller,
//   • rebuilds the tree when the controller notifies (one AnimatedBuilder),
//   • routes button taps to controller commands,
//   • builds the start config and stages the bundled turn-detector asset.
//
// Layout:
//   AppBar ............. title + settings + status dot
//   ErrorBanner ........ only when controller.error != null
//   TranscriptArea ..... loading checklist / hint / chat bubbles
//   BottomBar .......... status line, mic level, Start/Stop/Interrupt
// ============================================================================
class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({
    super.key,
    required this.agent,
    required this.settings,
    required this.openAIKey,
  });

  final TheStageVoiceAgentFlutter agent;
  final VoiceAgentSettings settings;
  final String openAIKey;

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  late final VoiceAgentController _controller =
      VoiceAgentController(widget.agent);
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll the transcript whenever the controller emits new content.
    _controller.addListener(_scrollToBottom);
    // Rebuild when the model-picker mutates settings (it's a separate
    // ChangeNotifier from the controller-driven AnimatedBuilder).
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _controller.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleRun() async {
    if (_controller.isRunning) {
      _controller.stop();
      return;
    }
    final config = widget.settings.toConfig(widget.openAIKey);
    // turn_detector engines: an HF repo, or a local bundle via
    // --dart-define=TURN_DETECTOR_ENGINES_PATH. Used only when mode is dnn.
    config['turn_detector'] = const String.fromEnvironment(
      'TURN_DETECTOR_ENGINES_PATH',
      defaultValue: 'TheStageAI/smart-turn-v3',
    );
    _controller.start(config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  settings: widget.settings,
                  agent: widget.agent,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.circle,
                  size: 14, color: agentStateColor(_controller.state)),
            ),
          ),
        ],
      ),
      // One listener for the whole screen: rebuild when the controller changes.
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Column(
            children: [
              if (_controller.error != null)
                ErrorBanner(
                  message: _controller.error!,
                  onDismiss: _controller.clearError,
                ),
              Expanded(
                child: TranscriptArea(
                  controller: _controller,
                  scrollController: _scrollController,
                ),
              ),
              // Model pickers: editable only while the agent is idle.
              ModelPickerBar(
                settings: widget.settings,
                enabled: !_controller.isRunning,
              ),
              BottomBar(controller: _controller, onToggleRun: _toggleRun),
            ],
          );
        },
      ),
    );
  }
}
