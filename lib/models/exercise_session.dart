import 'exercise_type.dart';
import '../utils/calories.dart';

enum SessionStatus { recording, paused, finished }

// Finished GPS sessions only. Calendar boundaries are supplied as local DateTimes
// by the caller, then compared as instants; manual daily records stay separate.
class MovementSummary {
  const MovementSummary(
    this.count,
    this.meters,
    this.seconds,
    this.calories,
    this.calorieCount,
  );
  final int count, seconds, calorieCount;
  final double meters;
  final double? calories;
  factory MovementSummary.fromSessions(
    Iterable<ExerciseSession> sessions, {
    DateTime? from,
    DateTime? before,
  }) {
    int count = 0, seconds = 0, calorieCount = 0;
    double meters = 0, calories = 0;
    for (final s in sessions) {
      if (s.status != SessionStatus.finished ||
          (from != null && s.startedAt.isBefore(from)) ||
          (before != null && !s.startedAt.isBefore(before))) {
        continue;
      }
      count++;
      meters += s.distanceMeters;
      seconds += s.elapsedSeconds;
      if (s.calories != null) {
        calories += s.calories!;
        calorieCount++;
      }
    }
    return MovementSummary(
      count,
      meters,
      seconds,
      calorieCount == 0 ? null : calories,
      calorieCount,
    );
  }
}

class ExerciseSession {
  const ExerciseSession({
    required this.id,
    required this.startedAt,
    required this.type,
    this.weightKg,
    this.elapsedSeconds = 0,
    this.distanceMeters = 0,
    this.status = SessionStatus.recording,
    required this.updatedAt,
    this.endedAt,
  });
  final int id;
  final DateTime startedAt, updatedAt;
  final DateTime? endedAt;
  final ExerciseType type;
  // A calculation snapshot, not a weight measurement for today's journal.
  final double? weightKg;
  final int elapsedSeconds;
  final double distanceMeters;
  final SessionStatus status;
  double? get calories => weightKg == null
      ? null
      : estimateCalories(
          met: type.met,
          weightKg: weightKg!,
          durationMinutes: elapsedSeconds / 60,
        );
  double? get paceSeconds => distanceMeters < 20 || elapsedSeconds == 0
      ? null
      : elapsedSeconds / (distanceMeters / 1000);
  ExerciseSession copyWith({
    int? elapsedSeconds,
    double? distanceMeters,
    SessionStatus? status,
    DateTime? updatedAt,
    DateTime? endedAt,
  }) => ExerciseSession(
    id: id,
    startedAt: startedAt,
    type: type,
    weightKg: weightKg,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    endedAt: endedAt ?? this.endedAt,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'exerciseType': type.name,
    'weightKg': weightKg,
    'elapsedSeconds': elapsedSeconds,
    'distanceMeters': distanceMeters,
    'estimatedCalories': calories,
    'status': status.name,
  };
  factory ExerciseSession.fromMap(Map<String, Object?> m) => ExerciseSession(
    id: m['id'] as int,
    startedAt: DateTime.parse(m['startedAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
    endedAt: m['endedAt'] == null
        ? null
        : DateTime.parse(m['endedAt'] as String),
    type: ExerciseType.values.byName(m['exerciseType'] as String),
    weightKg: (m['weightKg'] as num?)?.toDouble(),
    elapsedSeconds: m['elapsedSeconds'] as int,
    distanceMeters: (m['distanceMeters'] as num).toDouble(),
    status: SessionStatus.values.byName(m['status'] as String),
  );
}

class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracy,
    this.segment = 0,
    this.rawSpeed,
    this.cumulativeMeters,
  });
  final double latitude, longitude, accuracy;
  final DateTime timestamp;
  // Each pause or GPS outage starts a separate polyline. Never bridge gaps.
  final int segment;
  // Sensor speed in m/s; nullable for legacy records or unavailable sensors.
  final double? rawSpeed, cumulativeMeters;
  RoutePoint inSegment(int value) => RoutePoint(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    segment: value,
    rawSpeed: rawSpeed,
    cumulativeMeters: cumulativeMeters,
  );
  RoutePoint withDistance(double meters) => RoutePoint(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    segment: segment,
    rawSpeed: rawSpeed,
    cumulativeMeters: meters,
  );
  Map<String, Object?> toMap(int sessionId) => {
    'sessionId': sessionId,
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'accuracy': accuracy,
    'segment': segment,
    'rawSpeed': rawSpeed,
    'cumulativeMeters': cumulativeMeters,
  };
  factory RoutePoint.fromMap(Map<String, Object?> m) => RoutePoint(
    latitude: (m['latitude'] as num).toDouble(),
    longitude: (m['longitude'] as num).toDouble(),
    timestamp: DateTime.parse(m['timestamp'] as String),
    accuracy: (m['accuracy'] as num).toDouble(),
    segment: m['segment'] as int,
    rawSpeed: (m['rawSpeed'] as num?)?.toDouble(),
    cumulativeMeters: (m['cumulativeMeters'] as num?)?.toDouble(),
  );
}
