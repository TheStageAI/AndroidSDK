package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.audio.AudioStreamConfig
import ai.thestage.qlip.audio.AudioStreamPlayer
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__fail
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Audio Handlers
// ----------------------------------------------------------------------
//
// `audio_*` routes manage [AudioStreamPlayer] instances
// keyed by `player_id`. Mirrors Swift's `AudioHandlers`.

internal fun TheStageFlutterPlugin.__handle_audio_start(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    if (player_id == null) {
        __fail(result, "Missing player_id.")
        return
    }
    __audio_players.remove(player_id)?.let {
        try { it.stop() } catch (_: Throwable) {}
    }
    val sr = (args["sample_rate"] as? Number)?.toInt()
        ?: 24000
    val player = AudioStreamPlayer(
        AudioStreamConfig(sample_rate = sr)
    )
    player.start()
    __audio_players[player_id] = player
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_audio_enqueue(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    if (player_id == null) {
        result.success(null)
        return
    }
    when (val audio = args["audio"]) {
        is FloatArray ->
            __audio_players[player_id]?.enqueue(audio)
        is DoubleArray ->
            __audio_players[player_id]?.enqueue(audio)
    }
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_audio_pause(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    if (player_id == null) {
        result.success(null)
        return
    }
    __audio_players[player_id]?.pause()
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_audio_resume(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    if (player_id == null) {
        result.success(null)
        return
    }
    __audio_players[player_id]?.resume()
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_audio_drain(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    val player =
        player_id?.let { __audio_players[it] }
    if (player == null) {
        result.success(null)
        return
    }
    // drain() suspends until playout completes; run it off
    // the main thread and reply when done.
    __scope.launch(Dispatchers.Default) {
        try {
            player.drain()
        } catch (_: Throwable) {}
        withContext(Dispatchers.Main) {
            try { result.success(null) } catch (_: Throwable) {}
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_audio_stop(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val player_id = args?.get("player_id") as? String
    if (player_id == null) {
        result.success(null)
        return
    }
    __audio_players.remove(player_id)?.let {
        try { it.stop() } catch (_: Throwable) {}
    }
    result.success(null)
}
