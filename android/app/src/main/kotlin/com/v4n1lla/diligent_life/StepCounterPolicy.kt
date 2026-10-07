package com.v4n1lla.diligent_life

data class StepCursor(val boot: Int, val counter: Long, val sample: Long, val date: String)
data class StepDecision(val delta: Long, val coverage: String, val accept: Boolean)

// First observation establishes a baseline. Reboots/resets never import the
// device's lifetime total. Sensor monotonic timestamps reject stale deliveries.
object StepCounterPolicy {
    fun decide(previous: StepCursor?, next: StepCursor): StepDecision {
        if (next.counter < 0 || next.sample < 0) return StepDecision(0, "invalid", false)
        if (previous == null) return StepDecision(0, "partial", true)
        if (previous.boot != next.boot) return StepDecision(0, "reboot", true)
        if (next.sample <= previous.sample) return StepDecision(0, "duplicate", false)
        if (next.counter < previous.counter) return StepDecision(0, "reset", true)
        return StepDecision(next.counter - previous.counter,
            if (previous.date != next.date) "boundary" else "observed", true)
    }
}
