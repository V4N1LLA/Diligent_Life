package com.v4n1lla.diligent_life

fun widgetPolicyChecks() {
    val old = WidgetState("2026-10-08", 4200, 10000, 3, "나의 첫 페이지", 5000, "오늘 걸음")
    check(!WidgetPolicy.shouldRender(old, old, 60000, false))
    check(!WidgetPolicy.shouldRender(old, old.copy(steps=4300), 29000, false))
    check(WidgetPolicy.shouldRender(old, old.copy(steps=4300), 30000, false))
    check(WidgetPolicy.shouldRender(old, old.copy(date="2026-10-09", steps=0), 1, false))
    check(WidgetPolicy.shouldRender(old, old.copy(level=4), 1, false))
    check(WidgetPolicy.shouldRender(old, old.copy(title="첫 발걸음"), 1, false))
    check(WidgetPolicy.shouldRender(old, old.copy(goal=5000), 1, false))
    check(WidgetPolicy.shouldRender(old, old.copy(steps=10000), 1, false))
    check(WidgetPolicy.shouldRender(old, old, 1, true))
    check(WidgetPolicy.percent(Long.MAX_VALUE, 1)==100)
    check(WidgetPolicy.percent(-1, 0)==0)
    check(WidgetPolicy.percent(8432, 10000)==84)
    check(!WidgetPolicy.wide(249, 1f) && WidgetPolicy.wide(250, 1.5f) && !WidgetPolicy.wide(300, 2f))
    println("13 home widget policy checks passed")
}
