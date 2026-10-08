package com.v4n1lla.diligent_life

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.hardware.Sensor
import android.hardware.SensorManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.util.TypedValue
import android.widget.RemoteViews
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors

/** Presentation only: never opens a sensor, starts a service or writes the DB. */
object ActivityWidget {
    private val worker = Executors.newSingleThreadExecutor()
    private var scheduledMidnight = 0L
    private var shown: WidgetState? = null
    private var postedAt = 0L
    private val main = Handler(Looper.getMainLooper())
    // Only dirty trailing work; never an idle/recurring timer or wakeup.
    private var trailing: Runnable? = null
    private fun prefs(c: Context) = c.getSharedPreferences("activity_widget", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(AppWidgetManager::class.java)
    fun ids(c: Context): IntArray = listOf(CompactActivityWidget::class.java, WideActivityWidget::class.java)
        .flatMap { manager(c).getAppWidgetIds(ComponentName(c, it)).toList() }.toIntArray()

    fun publish(c: Context, value: Map<*, *>) {
        val cache = prefs(c)
        val level = (value["level"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 1
        val title = (value["title"] as? String)?.take(80) ?: "나의 첫 페이지"
        val quest = (value["questTarget"] as? Number)?.toInt()?.coerceIn(1, 1000000) ?: 5000
        if (cache.getInt("level", 1) != level || cache.getString("title", "나의 첫 페이지") != title ||
            cache.getInt("questTarget", 5000) != quest) {
            cache.edit().putInt("level", level).putString("title", title).putInt("questTarget", quest).apply()
        }
        if (ids(c).isNotEmpty()) request(c)
    }

    fun request(context: Context, force: Boolean = false, finished: () -> Unit = {}) {
        val c = context.applicationContext
        worker.execute {
            try {
                val widgets = ids(c)
                if (widgets.isEmpty()) { if (force || scheduledMidnight != 0L) cancelMidnight(c); return@execute }
                val date = LocalDate.now()
                val cache = prefs(c)
                var steps = if (cache.getString("date", null) == date.toString()) cache.getLong("steps", 0) else 0
                // Read-only, bounded lock wait, and only one indexed row. Migration/restore owns writes.
                val file = c.getDatabasePath("diligent_life.db")
                var available = file.exists()
                if (available) {
                    try {
                        SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                            db.execSQL("PRAGMA busy_timeout=500")
                            steps = db.rawQuery("SELECT steps FROM daily_steps WHERE date=?", arrayOf(date.toString())).use {
                                if (it.moveToFirst()) it.getLong(0).coerceAtLeast(0) else 0
                            }
                        }
                        if (cache.getString("date", null) != date.toString() || cache.getLong("steps", -1) != steps) {
                            cache.edit().putString("date", date.toString()).putLong("steps", steps).apply()
                        }
                    } catch (_: Exception) { available = false /* Retain only a same-date snapshot; retry on the next event. */ }
                }
                val settings = c.getSharedPreferences("daily_steps", Context.MODE_PRIVATE)
                val supported = c.getSystemService(SensorManager::class.java).getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
                val status = when {
                    !available -> "오늘부터 기록해볼까요?"
                    !supported -> "걸음 기록을 확인해 보세요"
                    !StepTrackingService.allowed(c) -> "걸음 권한을 확인해 주세요"
                    !settings.getBoolean("enabled", false) -> "앱에서 만보기를 켜 주세요"
                    else -> "오늘 걸음"
                }
                val state = WidgetState(date.toString(), steps, settings.getInt("goal", 5000).coerceAtLeast(1),
                    cache.getInt("level", 1), cache.getString("title", "나의 첫 페이지")!!,
                    cache.getInt("questTarget", 5000).coerceAtLeast(1), status)
                val now = SystemClock.elapsedRealtime()
                if (WidgetPolicy.shouldRender(shown, state, now - postedAt, force)) {
                    trailing?.let(main::removeCallbacks)
                    trailing = null
                    widgets.forEach { id ->
                        val options = manager(c).getAppWidgetOptions(id)
                        val wide = manager(c).getAppWidgetInfo(id)?.provider?.className == WideActivityWidget::class.java.name &&
                            WidgetPolicy.wide(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH), c.resources.configuration.fontScale, options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180))
                        manager(c).updateAppWidget(id, views(c, state, wide, options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)))
                    }
                    shown = state
                    postedAt = now
                } else if (shown != state && trailing == null) {
                    val task = Runnable { worker.execute { trailing = null; request(c) } }
                    trailing = task
                    main.postDelayed(task, (30_000 - (now - postedAt)).coerceAtLeast(1))
                }
                scheduleMidnight(c, date)
            } catch (_: Exception) { /* A removed host or transient storage failure must never affect recording. */ }
            finally { finished() }
        }
    }

    internal fun views(c: Context, state: WidgetState, wide: Boolean, height: Int = 180): RemoteViews {
        val n = NumberFormat.getIntegerInstance(java.util.Locale.KOREA)
        return RemoteViews(c.packageName, if (wide) R.layout.activity_widget_wide else R.layout.activity_widget_compact).apply {
            setTextViewText(R.id.widget_steps, n.format(state.steps))
            setTextViewText(R.id.widget_label, if (state.status == "오늘 걸음") "${state.date.substring(5).replace('-', '.')} 걸음" else state.status)
            setTextViewText(R.id.widget_goal, "목표 ${n.format(state.goal)} · ${WidgetPolicy.percent(state.steps, state.goal)}%")
            setProgressBar(R.id.widget_progress, 100, WidgetPolicy.percent(state.steps, state.goal), false)
            setContentDescription(R.id.widget_steps, "${state.date} ${n.format(state.steps)} 걸음")
            setOnClickPendingIntent(R.id.widget_steps_area, action(c, "today"))
            setOnClickPendingIntent(R.id.widget_start, action(c, "exercise"))
            val scale = c.resources.configuration.fontScale
            if (height < 165 || scale > 1.5f) {
                val padding = if (height < 120) 6 else 8
                setViewPadding(R.id.widget_root, padding.dp(c), padding.dp(c), padding.dp(c), padding.dp(c))
                setViewVisibility(R.id.widget_label, View.GONE)
                setViewVisibility(R.id.widget_progress, View.GONE)
                setTextViewTextSize(R.id.widget_steps, TypedValue.COMPLEX_UNIT_SP, if (height < 120) 18f else 22f)
                setTextViewTextSize(R.id.widget_goal, TypedValue.COMPLEX_UNIT_SP, 10f)
                setTextViewTextSize(R.id.widget_start, TypedValue.COMPLEX_UNIT_SP, 12f)
                if (height < 140 && scale > 1.25f) setViewVisibility(R.id.widget_goal, View.GONE)
            }
            setContentDescription(R.id.widget_steps_area, "${state.status}, ${state.steps} 걸음, 목표 ${state.goal}")
            if (wide) {
                setTextViewText(R.id.widget_level, "Lv.${state.level} · ${state.title}")
                setTextViewText(R.id.widget_quest, "오늘 걸음 퀘스트 · ${WidgetPolicy.percent(state.steps, state.questTarget)}%")
                setOnClickPendingIntent(R.id.widget_level, action(c, "profile"))
                setOnClickPendingIntent(R.id.widget_quest, action(c, "growth"))
            }
        }
    }

    private fun Int.dp(c: Context) = (this * c.resources.displayMetrics.density).toInt()

    internal fun action(c: Context, destination: String): PendingIntent = PendingIntent.getActivity(c, 0,
        Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("diligent-life://activity/$destination?token="))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun midnightIntent(c: Context) = PendingIntent.getBroadcast(c, 806,
        Intent(c, CompactActivityWidget::class.java).setAction("com.v4n1lla.diligent_life.WIDGET_DATE"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun scheduleMidnight(c: Context, date: LocalDate) {
        val at = date.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        if (at == scheduledMidnight) return
        // One necessary date transition, RTC (NOT RTC_WAKEUP), no exact-alarm permission.
        // If asleep, delivery waits until the device next wakes. No polling or new service.
        c.getSystemService(AlarmManager::class.java).set(AlarmManager.RTC, at, midnightIntent(c))
        scheduledMidnight = at
    }
    private fun cancelMidnight(c: Context) {
        c.getSystemService(AlarmManager::class.java).cancel(midnightIntent(c))
        scheduledMidnight = 0
        trailing?.let(main::removeCallbacks)
        trailing = null
        shown = null
    }
}

open class CompactActivityWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf("com.v4n1lla.diligent_life.WIDGET_DATE", Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_LOCALE_CHANGED)) {
            val pending = goAsync()
            ActivityWidget.request(context, true) { pending.finish() }
        }
    }
    override fun onUpdate(c: Context, manager: AppWidgetManager, ids: IntArray) { update(c) }
    override fun onAppWidgetOptionsChanged(c: Context, manager: AppWidgetManager, id: Int, options: Bundle) { update(c) }
    override fun onDeleted(c: Context, ids: IntArray) { update(c) }
    override fun onDisabled(c: Context) { update(c) }
    private fun update(c: Context) {
        val pending = goAsync()
        ActivityWidget.request(c, true) { pending.finish() }
    }
}
class WideActivityWidget : CompactActivityWidget()
