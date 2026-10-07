import 'dart:math' as math;

const xpRuleVersion = 1;

class ActivityDay {
  const ActivityDay(
    this.date, {
    this.steps = 0,
    this.meters = 0,
    this.seconds = 0,
    this.workouts = 0,
    this.confirmedSteps,
  });
  final String date;
  final int steps, seconds, workouts;
  final int? confirmedSteps;
  final double meters;
  int get baseXp =>
      math.min((confirmedSteps ?? steps) ~/ 1000, 10) * 10 +
      math.min(meters ~/ 1000, 10) * 15 +
      math.min(seconds ~/ 600, 6) * 10;
}

class GoalProgress {
  const GoalProgress(
    this.id,
    this.label,
    this.value,
    this.target,
    this.reward, {
    this.titleId,
  });
  final String id, label;
  final double value, target;
  final int reward;
  final String? titleId;
  bool get complete => value >= target;
  double get fraction => (value / target).clamp(0, 1);
}

const titles = <String, String>{
  'title.beginner.v1': '첫 발걸음',
  'title.five_km.v1': '나만의 속도',
  'title.ten_km.v1': '꾸준한 움직임',
  'title.hundred_km.v1': '길을 만드는 나',
  'title.steps_100k.v1': '일상의 탐험가',
  'title.workouts_30.v1': '꾸준함의 힘',
};

List<GoalProgress> dailyQuests(ActivityDay day) => [
  GoalProgress(
    'quest.daily.steps_5000.v1',
    '오늘 5,000걸음',
    (day.confirmedSteps ?? day.steps).toDouble(),
    5000,
    30,
  ),
  GoalProgress(
    'quest.daily.distance_3km.v1',
    '오늘 운동 3km',
    day.meters,
    3000,
    30,
  ),
  GoalProgress(
    'quest.daily.active_30min.v1',
    '오늘 운동 30분',
    day.seconds.toDouble(),
    1800,
    30,
  ),
];

List<GoalProgress> achievements(List<ActivityDay> days, double longest) {
  final meters = days.fold<double>(0, (sum, d) => sum + d.meters);
  final steps = days.fold<int>(0, (sum, d) => sum + d.steps);
  final count = days.fold<int>(0, (sum, d) => sum + d.workouts);
  return [
    GoalProgress(
      'achievement.first_workout.v1',
      '첫 운동',
      count.toDouble(),
      1,
      50,
      titleId: 'title.beginner.v1',
    ),
    GoalProgress(
      'achievement.workout_5km.v1',
      '한 번에 5km',
      longest,
      5000,
      80,
      titleId: 'title.five_km.v1',
    ),
    GoalProgress(
      'achievement.workout_10km.v1',
      '한 번에 10km',
      longest,
      10000,
      120,
      titleId: 'title.ten_km.v1',
    ),
    GoalProgress(
      'achievement.distance_100km.v1',
      '누적 운동 100km',
      meters,
      100000,
      200,
      titleId: 'title.hundred_km.v1',
    ),
    GoalProgress(
      'achievement.steps_100k.v1',
      '누적 100,000걸음',
      steps.toDouble(),
      100000,
      150,
      titleId: 'title.steps_100k.v1',
    ),
    GoalProgress(
      'achievement.workouts_30.v1',
      '운동 30회',
      count.toDouble(),
      30,
      150,
      titleId: 'title.workouts_30.v1',
    ),
  ];
}

// Each level needs 200 + 50*(level-1) XP. No rewards depend on weight or kcal.
int levelStart(int level) => 200 * (level - 1) + 25 * (level - 1) * (level - 2);
int levelForXp(int xp) {
  var level = 1;
  while (xp >= levelStart(level + 1)) {
    level++;
  }
  return level;
}

class GrowthSnapshot {
  const GrowthSnapshot({
    required this.days,
    required this.xp,
    required this.quests,
    required this.achievements,
    required this.unlockedTitles,
    this.titleId,
  });
  final List<ActivityDay> days;
  final int xp;
  final List<GoalProgress> quests, achievements;
  final Set<String> unlockedTitles;
  final String? titleId;
  int get level => levelForXp(xp);
  int get levelXp => xp - levelStart(level);
  int get nextLevelXp => levelStart(level + 1) - levelStart(level);
  String get title => titles[titleId] ?? '나의 첫 페이지';
}
