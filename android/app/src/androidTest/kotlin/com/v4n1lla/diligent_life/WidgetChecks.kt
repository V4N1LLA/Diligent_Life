package com.v4n1lla.diligent_life

import android.app.Activity
import android.app.Instrumentation
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.View
import android.widget.TextView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Emulator-only host/render checks. No sensors or user DB writes. */
fun Instrumentation.runWidgetChecks() {
    var checks = 0
    val result = Bundle()
    val c = targetContext
    val manager = c.getSystemService(AppWidgetManager::class.java)
    val host = AppWidgetHost(c, 812)
    val allocated = mutableListOf<Int>()
    val views = mutableListOf<AppWidgetHostView>()
    var resultCode = Activity.RESULT_OK
    fun verify(value: Boolean) { check(value) { "Widget check ${checks + 1} failed" }; checks++ }
    try {
        val state = WidgetState("2026-10-08", 8432, 10000, 12, "길 위의 탐험가", 5000, "오늘 걸음")
        for (dark in listOf(false, true)) for (scale in listOf(1f, 1.5f, 2f)) for (wide in listOf(false, true)) for (height in listOf(110, 140, 180)) {
            val config = Configuration(c.resources.configuration).apply {
                fontScale = scale
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
            }
            val themed = c.createConfigurationContext(config)
            runOnMainSync {
                val view = ActivityWidget.views(themed, state, wide && WidgetPolicy.wide(320, scale, height), height).apply(themed, null)
                view.measure(View.MeasureSpec.makeMeasureSpec((if(wide) 320 else 160).dp(themed), View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(height.dp(themed), View.MeasureSpec.EXACTLY))
                view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                verify(view.findViewById<TextView>(R.id.widget_steps).text.toString() == "8,432")
                verify(view.findViewById<TextView>(R.id.widget_start).height >= 48.dp(themed))
                val steps = view.findViewById<TextView>(R.id.widget_steps)
                verify(steps.layout != null && steps.layout.getLineBottom(0) <= steps.height)
            }
        }
        val today = java.time.LocalDate.now().toString()
        val expectedSteps = java.text.NumberFormat.getIntegerInstance(java.util.Locale.KOREA)
            .format(ActivityWidget.readSteps(c, today))
        verify(ActivityWidget.readSteps(c, "2099-01-01") == 0L)
        runOnMainSync { host.startListening() }
        for (provider in listOf(CompactActivityWidget::class.java, WideActivityWidget::class.java, CompactActivityWidget::class.java)) {
            val id = host.allocateAppWidgetId()
            allocated.add(id)
            verify(manager.bindAppWidgetIdIfAllowed(id, ComponentName(c, provider)))
            manager.updateAppWidgetOptions(id, Bundle().apply {
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, if (provider == WideActivityWidget::class.java) 320 else 160)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            })
            runOnMainSync { views.add(host.createView(c, id, manager.getAppWidgetInfo(id))) }
        }
        val done = CountDownLatch(1)
        ActivityWidget.publish(c, mapOf("level" to 12, "title" to "길 위의 탐험가", "questTarget" to 5000))
        ActivityWidget.request(c, true) { done.countDown() }
        verify(done.await(8, TimeUnit.SECONDS))
        Thread.sleep(500)
        waitForIdleSync()
        runOnMainSync {
            verify(views.all { it.findViewById<TextView>(R.id.widget_steps) != null })
            verify(views[0].findViewById<TextView>(R.id.widget_steps).text.toString() == expectedSteps)
            verify(views.map { it.findViewById<TextView>(R.id.widget_steps).text.toString() }.toSet().size == 1)
            verify(views[1].findViewById<TextView>(R.id.widget_level).text.toString().contains("Lv.12"))
        }
        verify(ActivityWidget.ids(c).toSet().containsAll(allocated))
        verify(manager.getAppWidgetInfo(allocated[0]).updatePeriodMillis == 0)
        val old = ActivityWidget.views(c, state, true).apply(c, null)
        val next = ActivityWidget.views(c, state.copy(date="2026-10-09", steps=0), true).apply(c, null)
        verify(old.findViewById<TextView>(R.id.widget_steps).text.toString() == "8,432")
        verify(next.findViewById<TextView>(R.id.widget_steps).text.toString() == "0")
        verify(next.findViewById<TextView>(R.id.widget_quest).text.toString().contains("0%"))
        for (destination in listOf("today", "profile", "growth", "exercise")) {
            verify(ActivityWidget.action(c, destination).isImmutable)
        }
    } catch (e: Throwable) {
        resultCode = Activity.RESULT_CANCELED
        result.putString("failure", e.stackTraceToString())
    } finally {
        allocated.forEach { host.deleteAppWidgetId(it) }
        runOnMainSync { host.stopListening() }
        ActivityWidget.request(c, true)
    }
    result.putString("summary", "$checks home widget checks passed")
    finish(resultCode, result)
}

private fun Int.dp(c: Context) = (this * c.resources.displayMetrics.density).toInt()
