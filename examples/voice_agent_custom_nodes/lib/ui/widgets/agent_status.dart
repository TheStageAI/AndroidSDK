import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../../backend/voice_agent_controller.dart';

// ============================================================================
// FRONTEND helpers — map agent state to presentation (colour + labels)
// ============================================================================
// Pure functions: agent state in, display value out. No widget state.
// ============================================================================

/// Colour of the status dot in the app bar for the current agent state.
Color agentStateColor(TSAgentState state) {
  switch (state) {
    case TSAgentState.idle:
      return Colors.grey;
    case TSAgentState.loading:
      return Colors.amber;
    case TSAgentState.sleeping:
      return Colors.blueGrey;
    case TSAgentState.listening:
      return Colors.green;
    case TSAgentState.thinking:
      return Colors.purple;
    case TSAgentState.tool_calling:
      return Colors.indigo;
    case TSAgentState.speaking:
      return Colors.blue;
  }
}

/// Human-readable status line shown in the bottom bar.
String agentStateLabel(VoiceAgentController c) {
  switch (c.state) {
    case TSAgentState.idle:
      return c.starting ? 'Starting...' : 'Idle';
    case TSAgentState.loading:
      if (c.currentLoadingModel == null) return 'Loading models...';
      return '${c.currentLoadingModel} - ${agentPhaseLabel(c)}';
    case TSAgentState.sleeping:
      return 'Waiting for wake word...';
    case TSAgentState.listening:
      return 'Listening...';
    case TSAgentState.thinking:
      return 'Thinking...';
    case TSAgentState.tool_calling:
      return 'Calling tool...';
    case TSAgentState.speaking:
      return 'Speaking...';
  }
}

/// Sub-status for the model currently loading (download → extract → compile).
String agentPhaseLabel(VoiceAgentController c) {
  switch (c.loadPhase) {
    case 'downloading':
      return 'downloading ${(c.downloadProgress * 100).toStringAsFixed(0)}%';
    case 'waiting_for_wifi':
      return 'waiting for Wi-Fi...';
    case 'waiting_for_confirmation':
      return 'confirm the download to continue';
    case 'extracting':
      return 'extracting...';
    case 'loading':
      return 'loading & compiling...';
    default:
      return 'preparing...';
  }
}
