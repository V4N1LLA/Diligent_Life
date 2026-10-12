package com.v4n1lla.diligent_life

internal data class WidgetState(val date: String, val steps: Long, val goal: Int,
    val level: Int, val title: String, val questTarget: Int, val status: String)

internal object WidgetPolicy {
    fun percent(steps: Long, goal: Int): Int = ((steps.coerceAtLeast(0).toDouble() / goal.coerceAtLeast(1)) * 100).toInt().coerceIn(0, 100)
    fun wide(width: Int, fontScale: Float, height: Int = 180) = width >= 250 && fontScale <= 1.5f && height >= 112
    fun shouldRender(old: WidgetState?, next: WidgetState, elapsed: Long, force: Boolean): Boolean {
        if (force || old == null) return true
        if (old == next) return false
        if (old.copy(steps = next.steps) != next) return true
        return elapsed >= 30_000 || (old.steps < old.goal && next.steps >= next.goal)
    }
}
