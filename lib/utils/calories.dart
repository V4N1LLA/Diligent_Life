double estimateCalories({
  required double met,
  required double weightKg,
  required num durationMinutes,
}) {
  if (!met.isFinite ||
      met <= 0 ||
      !weightKg.isFinite ||
      weightKg <= 0 ||
      !durationMinutes.isFinite ||
      durationMinutes < 0) {
    throw ArgumentError('양의 MET·몸무게와 0 이상의 운동 시간이 필요합니다.');
  }
  return met * 3.5 * weightKg / 200 * durationMinutes;
}
