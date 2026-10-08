package com.v4n1lla.diligent_life

import java.text.NumberFormat
import java.util.Locale

data class StepNotice(val date: String, val steps: Long, val goal: Int) {
    val reached: Boolean get() = steps >= goal
    val title: String get() = "${NumberFormat.getIntegerInstance(Locale.KOREA).format(steps)} 걸음" +
        if (reached) " · 오늘 목표 달성" else ""
    val detail: String get() = "목표 ${NumberFormat.getIntegerInstance(Locale.KOREA).format(goal)} · " +
        "${(steps.toDouble() / goal * 100).toInt().coerceIn(0, 100)}%"
}

// Monotonic time only. No sensor/DB or wakeup responsibility.
class NoticeThrottle(private val interval: Long) {
    private var last: Long? = null
    fun delay(now: Long): Long = last?.let { (interval - (now - it)).coerceAtLeast(0) } ?: 0
    fun posted(now: Long) { last = now }
    fun reset() { last = null }
}
