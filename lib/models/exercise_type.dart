enum ExerciseType {
  // Fixed representative intensities, not inferred from distance or sensors.
  // See README's MET review; "other" is only a light-activity approximation.
  lightWalk('가벼운 걷기', 2.8),
  briskWalk('빠른 걷기', 4.3),
  jogging('조깅', 7.0),
  running('달리기', 9.8),
  other('기타', 3.0);

  const ExerciseType(this.label, this.met);
  final String label;
  final double met;
}
