import 'growth.dart';

const unlockRuleVersion = 1;

enum CosmeticSlot { accent, background, frame, emblem }

class Cosmetic {
  const Cosmetic(this.id, this.slot, this.name, this.requirement);
  final String id, name, requirement;
  final CosmeticSlot slot;
}

const cosmetics = [
  Cosmetic('accent.sage.v1', CosmeticSlot.accent, '세이지', '기본'),
  Cosmetic('accent.purple.v1', CosmeticSlot.accent, '라일락', 'Lv. 5'),
  Cosmetic('background.mist.v1', CosmeticSlot.background, '안개', '기본'),
  Cosmetic('background.dawn.v1', CosmeticSlot.background, '새벽', '첫 운동 업적'),
  Cosmetic('frame.none.v1', CosmeticSlot.frame, '가볍게', '기본'),
  Cosmetic('frame.level.v1', CosmeticSlot.frame, '성장', 'Lv. 10'),
  Cosmetic('frame.walking.v1', CosmeticSlot.frame, '발자취', '누적 운동 50km'),
  Cosmetic('emblem.none.v1', CosmeticSlot.emblem, '심플', '기본'),
  Cosmetic('emblem.explorer.v1', CosmeticSlot.emblem, '탐험가', '10개 지역 탐험'),
  Cosmetic('emblem.steady.v1', CosmeticSlot.emblem, '꾸준함', '운동 30회 업적'),
];

String defaultCosmetic(CosmeticSlot slot) =>
    cosmetics.firstWhere((c) => c.slot == slot).id;

class ProfileReward {
  const ProfileReward(this.key, this.label, this.seen);
  final String key, label;
  final bool seen;
}

class CharacterSnapshot {
  const CharacterSnapshot({
    required this.growth,
    required this.regions,
    required this.unlocked,
    required this.equipped,
    required this.rewards,
  });
  final GrowthSnapshot growth;
  final int regions;
  final Set<String> unlocked;
  final Map<CosmeticSlot, String> equipped;
  final List<ProfileReward> rewards;
  int get steps => growth.days.fold(0, (sum, d) => sum + d.steps);
  double get meters => growth.days.fold(0, (sum, d) => sum + d.meters);
  int get achievements => growth.achievements.where((a) => a.complete).length;
  int get unread => rewards.where((r) => !r.seen).length;
  String selection(CosmeticSlot slot) =>
      equipped[slot] ?? defaultCosmetic(slot);
}

bool qualifies(
  Cosmetic cosmetic,
  GrowthSnapshot growth,
  int regions,
) => switch (cosmetic.id) {
  'accent.purple.v1' => growth.level >= 5,
  'frame.level.v1' => growth.level >= 10,
  'frame.walking.v1' =>
    growth.days.fold<double>(0, (sum, d) => sum + d.meters) >= 50000,
  'emblem.explorer.v1' => regions >= 10,
  'background.dawn.v1' => growth.unlockedTitles.contains('title.beginner.v1'),
  'emblem.steady.v1' => growth.unlockedTitles.contains('title.workouts_30.v1'),
  _ => cosmetic.requirement == '기본',
};
