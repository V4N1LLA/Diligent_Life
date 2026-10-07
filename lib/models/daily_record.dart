import 'exercise_type.dart';

class DailyRecord {
  const DailyRecord({
    this.id,
    required this.date,
    this.weightKg,
    required this.exerciseType,
    required this.durationMinutes,
    this.distanceKm,
    required this.estimatedCalories,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String date;
  // Only an explicitly measured weight is stored; fallback is never a measurement.
  final double? weightKg;
  final ExerciseType exerciseType;
  final int durationMinutes;
  final double? distanceKm;
  final double estimatedCalories;
  final String createdAt;
  final String updatedAt;

  Map<String, Object?> toMap() => {
    'date': date,
    'weightKg': weightKg,
    'exerciseType': exerciseType.name,
    'durationMinutes': durationMinutes,
    'distanceKm': distanceKm,
    'estimatedCalories': estimatedCalories,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory DailyRecord.fromMap(Map<String, Object?> map) => DailyRecord(
    id: map['id'] as int,
    date: map['date'] as String,
    weightKg: (map['weightKg'] as num?)?.toDouble(),
    exerciseType: ExerciseType.values.byName(map['exerciseType'] as String),
    durationMinutes: map['durationMinutes'] as int,
    distanceKm: (map['distanceKm'] as num?)?.toDouble(),
    estimatedCalories: (map['estimatedCalories'] as num).toDouble(),
    createdAt: map['createdAt'] as String,
    updatedAt: map['updatedAt'] as String,
  );
}
