package com.merhii.moniz

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingAction = intent?.getStringExtra(
            MonizAppWidgetProvider.EXTRA_LAUNCH_ACTION
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Consuming rather than reading: the action describes one tap,
                // and returning it twice would open capture again on the next
                // resume.
                "consumeLaunchAction" -> {
                    val action = pendingAction
                    pendingAction = null
                    result.success(action)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // The app was already running, so the engine is configured and Dart
        // picks this up when it next resumes.
        pendingAction = intent.getStringExtra(
            MonizAppWidgetProvider.EXTRA_LAUNCH_ACTION
        )
    }

    companion object {
        private const val CHANNEL = "moniz/launch_action"
    }
}
