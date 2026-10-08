package com.v4n1lla.diligent_life

// Dependency-free checks executed by :app:stepPolicyChecks.
fun main() {
    val first = StepCursor(10, 5000, 100, "2026-10-06")
    check(StepCounterPolicy.decide(null, first).delta == 0L)
    check(StepCounterPolicy.decide(first, first).accept == false)
    check(StepCounterPolicy.decide(first, first.copy(sample=90,counter=6000)).accept == false)
    check(StepCounterPolicy.decide(first,first.copy(counter=5030,sample=200)).delta == 30L)
    // Same persisted cursor is used after a process restart.
    check(StepCounterPolicy.decide(first.copy(),first.copy(counter=5050,sample=300)).delta == 50L)
    val midnight = StepCounterPolicy.decide(first, first.copy(counter=5010,sample=200,date="2026-10-07"))
    check(midnight.delta == 10L && midnight.coverage == "boundary")
    val reboot = StepCounterPolicy.decide(first,StepCursor(11,20,10,"2026-10-06"))
    check(reboot.delta == 0L && reboot.coverage == "reboot")
    val reset = StepCounterPolicy.decide(first, first.copy(counter=3,sample=200))
    check(reset.delta == 0L && reset.coverage == "reset")
    check(!StepCounterPolicy.decide(first, first.copy(counter=-1,sample=200)).accept)
    println("9 step policy checks passed: initial baseline, duplicate, stale, delta, restart, midnight, reboot, reset, invalid")
    activityNotificationPolicyChecks()
}
