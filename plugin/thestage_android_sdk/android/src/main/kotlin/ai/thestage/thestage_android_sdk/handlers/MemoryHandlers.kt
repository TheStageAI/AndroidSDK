package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// ----------------------------------------------------------------------
// Memory Handlers
// ----------------------------------------------------------------------
//
// Reports the process memory as Android accounts it. Mirrors the iOS
// `memory_footprint` route (`MemoryHandlers.swift`) so the shared Dart
// layer is unchanged across platforms.
//
//   * `footprint_mb` — total PSS (proportional set size) in MB. PSS is
//     the closest Android analogue to iOS `phys_footprint`: it counts
//     this process's private dirty memory plus its share of memory
//     mapped with other processes, the number the low-memory killer /
//     Android Studio profiler track. Read via
//     `ActivityManager.getProcessMemoryInfo` (falls back to
//     `Debug.getPss()`).
//   * `resident_mb` — RSS in MB (pages currently in physical RAM),
//     read from `/proc/self/statm` field 2 (resident pages) times the
//     page size. The smaller, less meaningful diagnostic number.
//
// On any failure the failing value is reported as -1.0.

internal fun TheStageFlutterPlugin.__handle_memory_footprint(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val footprint_mb = __read_pss_mb()
    val resident_mb = __read_rss_mb()
    result.success(
        mapOf(
            "footprint_mb" to footprint_mb,
            "resident_mb" to resident_mb,
        )
    )
}

// Private Methods
// ----------------------------------------------------------------------

/**
 * Total PSS in MB for this process. Prefers
 * [ActivityManager.getProcessMemoryInfo] (the same
 * accounting the OOM killer uses); falls back to
 * [Debug.getPss]. Returns -1.0 on failure.
 */
private fun TheStageFlutterPlugin.__read_pss_mb(): Double {
    return try {
        val pss_kb = __read_total_pss_kb()
        if (pss_kb < 0) -1.0 else pss_kb.toDouble() / 1024.0
    } catch (_: Throwable) {
        -1.0
    }
}

private fun TheStageFlutterPlugin.__read_total_pss_kb(): Long {
    val ctx: Context? = __app_context
    if (ctx != null) {
        val am = ctx.getSystemService(
            Context.ACTIVITY_SERVICE
        ) as? ActivityManager
        if (am != null) {
            val pid = android.os.Process.myPid()
            val infos = am.getProcessMemoryInfo(intArrayOf(pid))
            val info = infos.firstOrNull()
            if (info != null) {
                return info.totalPss.toLong()
            }
        }
    }
    // Fallback: Debug.getPss() returns total PSS in KB.
    val pss = Debug.getPss()
    return if (pss <= 0) -1L else pss.toLong()
}

/**
 * RSS in MB read from `/proc/self/statm`. Field 2 (0-based
 * index 1) is the resident set size in pages; multiply by
 * the page size. Returns -1.0 on failure.
 */
private fun __read_rss_mb(): Double {
    return try {
        val statm = File("/proc/self/statm").readText().trim()
        val fields = statm.split(" ")
        if (fields.size < 2) return -1.0
        val resident_pages = fields[1].toLongOrNull()
            ?: return -1.0
        val page_size = __page_size_bytes()
        resident_pages.toDouble() * page_size / 1_048_576.0
    } catch (_: Throwable) {
        -1.0
    }
}

private fun __page_size_bytes(): Long {
    return try {
        // android.system.Os.sysconf(_SC_PAGESIZE)
        android.system.Os.sysconf(android.system.OsConstants._SC_PAGESIZE)
    } catch (_: Throwable) {
        4096L
    }
}
