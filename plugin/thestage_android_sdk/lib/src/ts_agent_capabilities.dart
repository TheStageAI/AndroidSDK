// ---------------------------------------------------------------------------
// Voice-agent capabilities payload
// ---------------------------------------------------------------------------
// Not exported: `TSVoiceAgent.capabilities` is the public surface.

/// Normalize the native `voice_agent.start` result: the four flags as
/// `bool` (missing = `false`) and `reasons` as `Map<String, String>`.
/// A `null` result (no payload) decodes to an empty map.
Map<String, dynamic> parseAgentCapabilities(Map<Object?, Object?>? raw) {
  if (raw == null) return <String, dynamic>{};
  final map = raw.map((k, v) => MapEntry(k.toString(), v));
  final reasons = (map['reasons'] as Map<Object?, Object?>? ?? const {})
      .map((k, v) => MapEntry(k.toString(), v.toString()));
  return <String, dynamic>{
    'listening': map['listening'] == true,
    'transcribing': map['transcribing'] == true,
    'responding': map['responding'] == true,
    'speaking': map['speaking'] == true,
    'reasons': reasons,
  };
}
