package com.v4n1lla.diligent_life

import android.app.Activity
import android.app.Instrumentation
import android.app.Notification
import android.app.NotificationManager
import android.os.Bundle

// Framework-only instrumentation: synthetic presentation fixtures, no sensors,
// no DB writes and no extra dependency. This does NOT validate a health FGS.
class NotificationChecks : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val c = targetContext
        val manager = c.getSystemService(NotificationManager::class.java)
        fun barrier() { waitForIdleSync(); Thread.sleep(1000) }
        fun notice(id: Int): Notification {
            repeat(20) {
                manager.activeNotifications.singleOrNull { it.id == id }?.let { return it.notification }
                Thread.sleep(250)
            }
            error("Notification $id was not posted; enabled=${manager.areNotificationsEnabled()}, running=${StepTrackingService.running}")
        }
        var checks = 0
        var resultCode = Activity.RESULT_OK
        val result = Bundle()
        fun verify(value: Boolean) { check(value) { "Notification check ${checks + 1} failed" }; checks++ }
        try {
            runOnMainSync {
                StepTrackingService.running = true
                ActivityNotifications.steps(c, StepNotice("2026-10-08", 7324, 10000), true)
            }
            barrier()
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "7,324 걸음")
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("73%"))
            verify(notice(140).actions.map { it.title.toString() } == listOf("오늘 보기", "운동 시작"))
            if (android.os.Build.VERSION.SDK_INT >= 31) verify(notice(140).contentIntent.isImmutable)
            runOnMainSync {
                ActivityNotifications.steps(c, StepNotice("2026-10-08", 7330, 10000))
                ActivityNotifications.steps(c, StepNotice("2026-10-08", 7360, 10000))
            }
            barrier()
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "7,324 걸음")
            Thread.sleep(30_100)
            barrier()
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "7,360 걸음")
            runOnMainSync { ActivityNotifications.steps(c, StepNotice("2026-10-08", 10284, 10000)) }
            barrier()
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TITLE).toString().contains("오늘 목표 달성"))
            runOnMainSync { ActivityNotifications.steps(c, StepNotice("2026-10-09", 0, 10000)) }
            barrier()
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "0 걸음")
            val workout = mapOf("token" to "instrumentation-current", "recording" to true,
                "seconds" to 1752, "title" to "걷기", "detail" to "2.43 km · 29:12\n12:01 /km")
            runOnMainSync { ActivityNotifications.workout(c, workout) }
            barrier()
            verify(notice(75415).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "걷기 · 기록 중")
            verify(notice(75415).channelId == "exercise_activity")
            verify(notice(75415).actions[0].title.toString() == "일시정지")
            verify(notice(75415).extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            verify(notice(140).extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("운동 기록 중"))
            runOnMainSync {
                ActivityNotifications.workout(c, workout + mapOf("token" to "race-fixture"))
                manager.notify(75415, Notification.Builder(c, "exercise_activity")
                    .setSmallIcon(R.drawable.ic_notification).setContentTitle("Plugin startup fixture").build())
            }
            barrier()
            verify(notice(75415).extras.getCharSequence(Notification.EXTRA_TITLE).toString() == "걷기 · 기록 중")
            runOnMainSync { ActivityNotifications.workout(c, workout + mapOf("recording" to false, "token" to "paused")) }
            barrier()
            verify(notice(75415).extras.getCharSequence(Notification.EXTRA_TITLE).toString().contains("일시정지"))
            verify(notice(75415).actions[0].title.toString() == "재개")
            verify(!notice(75415).extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            verify(manager.activeNotifications.count { it.id == 75415 } == 1)
            verify(!notice(75415).extras.getBoolean("android.requestPromotedOngoing"))
            runOnMainSync { ActivityNotifications.workout(c, null) }
            barrier()
            verify(manager.activeNotifications.none { it.id == 75415 })
            verify(!notice(140).extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("운동 기록 중"))
            result.putString("stream", "$checks Android notification checks passed; synthetic render fixtures only\n")
        } catch (e: Throwable) {
            resultCode = Activity.RESULT_CANCELED
            result.putString("stream", e.stackTraceToString())
        } finally {
            runOnMainSync {
                StepTrackingService.running = false
                ActivityNotifications.stoppedSteps()
                ActivityNotifications.workout(c, null)
                manager.cancel(140)
            }
        }
        finish(resultCode, result)
    }
}
