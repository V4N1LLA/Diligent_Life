package com.v4n1lla.diligent_life

fun activityNotificationPolicyChecks() {
    val first = StepNotice("2026-10-08", 7324, 10000)
    check(first.title == "7,324 걸음")
    check(first.detail == "목표 10,000 · 73%")
    check(!first.reached)
    val goal = first.copy(steps = 10284)
    check(goal.title == "10,284 걸음 · 오늘 목표 달성" && goal.detail.endsWith("100%"))
    check(first.copy(date="2026-10-09", steps=0).detail.endsWith("0%"))
    check(first.copy(goal=5000).reached)
    val throttle = NoticeThrottle(30000)
    check(throttle.delay(100) == 0L)
    throttle.posted(100)
    check(throttle.delay(200) == 29900L)
    check(throttle.delay(30100) == 0L)
    throttle.reset()
    check(throttle.delay(1) == 0L)
    println("10 activity notification policy checks passed")
}
