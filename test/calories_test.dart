import 'package:diligent_life/utils/calories.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MET formula calculates 30 minutes at 70 kg', () {
    expect(
      estimateCalories(met: 4.3, weightKg: 70, durationMinutes: 30),
      closeTo(158.025, .000001),
    );
  });
  test('zero minutes burns zero estimated calories', () {
    expect(estimateCalories(met: 2.8, weightKg: 65, durationMinutes: 0), 0);
  });
  test('all presets use the same linear formula', () {
    for (final type in ExerciseType.values) {
      expect(
        estimateCalories(met: type.met, weightKg: 100, durationMinutes: 20),
        closeTo(type.met * 35, .000001),
      );
    }
  });
  test('invalid and nonfinite inputs are rejected', () {
    for (final weight in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => estimateCalories(met: 3, weightKg: weight, durationMinutes: 10),
        throwsArgumentError,
      );
    }
    for (final met in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => estimateCalories(met: met, weightKg: 70, durationMinutes: 10),
        throwsArgumentError,
      );
    }
    expect(
      () => estimateCalories(met: 3, weightKg: 70, durationMinutes: -1),
      throwsArgumentError,
    );
  });
}
