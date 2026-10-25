package com.intersetwq.pullread

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app_icon"

    /// alias 后缀 → 组件名。与 AndroidManifest 中三个 activity-alias 一一对应：
    /// book=摊开书（默认），page=页即箭，arrow=抽页成箭。
    private val aliases = mapOf(
        "book" to ".MainActivityBook",
        "page" to ".MainActivityPage",
        "arrow" to ".MainActivityArrow",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val key = call.argument<String>("icon")
                        if (key == null || !aliases.containsKey(key)) {
                            result.error("bad_icon", "unknown icon key: $key", null)
                            return@setMethodCallHandler
                        }
                        try {
                            setLauncherAlias(key)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 启用选中的 alias、停用其余；重启 launcher 后桌面图标生效。
    private fun setLauncherAlias(selected: String) {
        val pm = applicationContext.packageManager
        for ((key, suffix) in aliases) {
            val component = ComponentName(applicationContext, packageName + suffix)
            val state =
                if (key == selected) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            pm.setComponentEnabledSetting(
                component,
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
