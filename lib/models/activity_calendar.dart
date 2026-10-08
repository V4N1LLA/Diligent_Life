class CalendarDay {
  const CalendarDay(
    this.date, {
    this.steps = 0,
    this.workouts = 0,
    this.meters = 0,
    this.seconds = 0,
    this.regions = 0,
    this.milestones = const [],
  });
  final String date;
  final int steps, workouts, seconds, regions;
  final double meters;
  final List<String> milestones;
  bool get hasActivity =>
      steps > 0 || workouts > 0 || regions > 0 || milestones.isNotEmpty;
}

class CalendarMonth {
  const CalendarMonth(this.month, this.days);
  final DateTime month;
  final Map<String, CalendarDay> days;
  int get steps => days.values.fold(0, (n, d) => n + d.steps);
  int get workouts => days.values.fold(0, (n, d) => n + d.workouts);
  int get workoutDays => days.values.where((d) => d.workouts > 0).length;
  double get meters => days.values.fold(0, (n, d) => n + d.meters);
  int get regions => days.values.fold(0, (n, d) => n + d.regions);
  bool get hasActivity => days.values.any((d) => d.hasActivity);
  String? get highlight => days.values
      .expand((d) => d.milestones)
      .where((label) => !label.endsWith('확인'))
      .firstOrNull;
}

class TimelinePage {
  const TimelinePage(this.days, this.nextBefore);
  final List<CalendarDay> days;
  final String? nextBefore;
}
