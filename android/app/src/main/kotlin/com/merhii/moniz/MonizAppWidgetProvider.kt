package com.merhii.moniz

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

/**
 * A quick-add tile. The button opens Moniz straight into capture; the rest of
 * the tile opens the app normally.
 *
 * It used to show the installed version number, which told nobody anything.
 */
class MonizAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        /** Read on the Dart side to decide whether to open capture on launch. */
        const val EXTRA_LAUNCH_ACTION = "moniz.launch_action"
        const val ACTION_ADD_ENTRY = "add_entry"

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.moniz_app_widget)
            views.setOnClickPendingIntent(
                R.id.moniz_widget_root,
                launchIntent(context, appWidgetId, requestOffset = 0, action = null)
            )
            views.setOnClickPendingIntent(
                R.id.moniz_widget_add,
                launchIntent(
                    context,
                    appWidgetId,
                    requestOffset = 1,
                    action = ACTION_ADD_ENTRY
                )
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun launchIntent(
            context: Context,
            appWidgetId: Int,
            requestOffset: Int,
            action: String?
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (action != null) putExtra(EXTRA_LAUNCH_ACTION, action)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            // Distinct request codes, or the two taps would share one
            // PendingIntent and the second would silently reuse the first's
            // extras.
            return PendingIntent.getActivity(
                context,
                appWidgetId * 2 + requestOffset,
                intent,
                flags
            )
        }
    }
}
