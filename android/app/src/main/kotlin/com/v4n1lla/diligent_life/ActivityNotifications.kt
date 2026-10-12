package com.v4n1lla.diligent_life

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel

// Keep the geolocator foreground-service ID; never create a second location service.
object ActivityNotifications {
    const val STEP_ID = 140
    const val WORKOUT_ID = 75415
    private const val STEP_CHANNEL = "daily_steps"
    private const val WORKOUT_CHANNEL = "exercise_activity"
    private val main = Handler(Looper.getMainLooper())
    private val throttle = NoticeThrottle(30_000)
    private var steps: StepNotice? = null
    private var shown: StepNotice? = null
    private var scheduled: Runnable? = null
    private var exercise = false
    private var workoutToken: String? = null
    private var settling: Runnable? = null

    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    private fun channels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        manager(c).createNotificationChannel(NotificationChannel(STEP_CHANNEL, "일상 걸음", NotificationManager.IMPORTANCE_LOW).apply {
            description = "오늘 걸음과 목표를 조용히 표시해요."
        })
        if (manager(c).getNotificationChannel(WORKOUT_CHANNEL) == null) {
            val old = manager(c).getNotificationChannel("geolocator_channel_01")
            // The plugin creates IMPORTANCE_NONE by default. Preserve explicit user choices,
            // but use LOW for the new presentation channel when no choice was made.
            val importance = when {
                old == null -> NotificationManager.IMPORTANCE_LOW
                // Older Android cannot distinguish the plugin default from a user block.
                Build.VERSION.SDK_INT < 29 -> old.importance
                old.hasUserSetImportance() -> old.importance
                else -> NotificationManager.IMPORTANCE_LOW
            }
            manager(c).createNotificationChannel(NotificationChannel(WORKOUT_CHANNEL, "운동 활동", importance).apply {
                description = "진행 중인 운동과 일시정지 상태를 표시해요."
                setSound(null, null)
                enableVibration(false)
            })
        }
    }

    private fun intent(c: Context, action: String, token: String = ""): PendingIntent {
        val uri = Uri.Builder().scheme("diligent-life").authority("activity")
            .appendPath(action).appendQueryParameter("token", token).build()
        return PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java).apply {
            this.action = Intent.ACTION_VIEW
            data = uri
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun builder(c: Context, channel: String): Notification.Builder {
        channels(c)
        return (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c))
            .setSmallIcon(R.drawable.ic_notification).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setPriority(Notification.PRIORITY_LOW)
            .setGroup("diligent.activity").setShowWhen(false)
    }

    fun stepNotification(c: Context): Notification {
        val s = steps
        val detail = if (s == null) "오늘 기록을 불러오고 있어요." else
            (if (exercise) "운동 기록 중 · " else "") + s.detail
        return builder(c, STEP_CHANNEL)
            .setContentTitle(s?.title ?: "오늘의 걸음").setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(detail)).setSortKey("1.steps")
            .setContentIntent(intent(c, "today"))
            .addAction(Notification.Action.Builder(null, "오늘 보기", intent(c, "today")).build())
            .addAction(Notification.Action.Builder(null, "운동 시작", intent(c, "exercise")).build()).build()
    }

    fun steps(c: Context, next: StepNotice, force: Boolean = false) {
        main.post {
            val important = steps?.let { it.date != next.date || it.goal != next.goal || it.reached != next.reached } ?: true
            steps = next
            scheduled?.let(main::removeCallbacks)
            scheduled = null
            if (next == shown && !force) return@post
            val task = Runnable {
                scheduled = null
                if (!StepTrackingService.running) return@Runnable
                safely { manager(c).notify(STEP_ID, stepNotification(c)) }
                shown = steps
                throttle.posted(SystemClock.elapsedRealtime())
            }
            if (force || important || throttle.delay(SystemClock.elapsedRealtime()) == 0L) task.run()
            else { scheduled = task; main.postDelayed(task, throttle.delay(SystemClock.elapsedRealtime())) }
        }
    }

    fun stoppedSteps() {
        main.post { scheduled?.let(main::removeCallbacks); scheduled = null; steps = null; shown = null; throttle.reset() }
    }

    fun workout(c: Context, value: Map<*, *>?) {
        val active = value != null
        if (exercise != active) {
            exercise = active
            if (StepTrackingService.running) safely { manager(c).notify(STEP_ID, stepNotification(c)) }
        }
        if (value == null) {
            workoutToken = null
            settling?.let(main::removeCallbacks)
            settling = null
            manager(c).cancel(WORKOUT_ID)
            return
        }
        val token = value["token"] as String
        val recording = value["recording"] == true
        val seconds = (value["seconds"] as Number).toLong().coerceAtLeast(0)
        val text = value["detail"] as String
        val n = builder(c, WORKOUT_CHANNEL)
            .setContentTitle((value["title"] as String) + if (recording) " · 기록 중" else " · 일시정지")
            .setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
            .setSortKey("0.exercise").setContentIntent(intent(c, "exercise", token))
            .setWhen(System.currentTimeMillis() - seconds * 1000).setShowWhen(true)
            .setUsesChronometer(recording)
            .addAction(Notification.Action.Builder(null, if (recording) "일시정지" else "재개",
                intent(c, if (recording) "pause" else "resume", token)).build())
            .addAction(Notification.Action.Builder(null, "운동 열기", intent(c, "exercise", token)).build()).build()
        safely { manager(c).notify(WORKOUT_ID, n) }
        if (workoutToken != token) {
            workoutToken = token
            settling?.let(main::removeCallbacks)
            // geolocator startForeground/stopForeground completes asynchronously.
            // Reconcile only around transitions; no recurring background polling.
            val context = c.applicationContext
            var attempts = 0
            val task = object : Runnable {
                override fun run() {
                    if (workoutToken != token) return
                    safely {
                        val current = manager(context).activeNotifications.singleOrNull { it.id == WORKOUT_ID }?.notification
                        if (current == null || current.extras.getCharSequence(Notification.EXTRA_TITLE) != n.extras.getCharSequence(Notification.EXTRA_TITLE) || current.actions?.size != 2 ||
                            (Build.VERSION.SDK_INT >= 26 && current.channelId != WORKOUT_CHANNEL)) {
                            manager(context).notify(WORKOUT_ID, n)
                        }
                    }
                    attempts++
                    if (attempts < 3) main.postDelayed(this, 1000L * attempts)
                    else settling = null
                }
            }
            settling = task
            main.postDelayed(task, 500)
        }
    }

    private inline fun safely(action: () -> Unit) { try { action() } catch (_: SecurityException) { /* Recording remains independent of drawer permission. */ } }
}

class ActivityNotificationBridge(private val activity: Activity, private val channel: MethodChannel) {
    private val pending = java.util.ArrayDeque<Map<String, String>>()
    fun accept(intent: Intent?) {
        val uri = intent?.data ?: return
        if (intent.action != Intent.ACTION_VIEW || uri.scheme != "diligent-life" || uri.host != "activity") return
        val action = uri.lastPathSegment ?: return
        if (action !in setOf("today", "exercise", "profile", "growth", "pause", "resume")) return
        if (pending.size >= 16) pending.removeFirst()
        pending.addLast(mapOf("action" to action, "token" to (uri.getQueryParameter("token") ?: "")))
        channel.invokeMethod("pending", null)
    }
    fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        when (method) {
            "takeAction" -> { result.success(pending.pollFirst()) }
            "workout" -> { ActivityNotifications.workout(activity, arguments as? Map<*, *>); result.success(null) }
            // compileSdk 36 lacks the public promotion request API (36.1).
            "capability" -> result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "style" to "standard"))
            else -> result.notImplemented()
        }
    }
}
