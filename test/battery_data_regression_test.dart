import 'dart:convert';
import 'dart:io';

import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

// Baseline and real-session inputs stay private. Generate the baseline from the
// release HEAD, before changing calculations, and supply both paths locally.
void main() {
  final source = Platform.environment['S26_BATTERY_DATA'];
  final baseline = Platform.environment['S26_BATTERY_BASELINE'];
  test(
    'real S26 sessions match release HEAD including every split, best and portfolio point',
    () {
      final sourceFile = File(source!);
      final before = sourceFile.readAsStringSync();
      final data = jsonDecode(before) as Map<String, dynamic>;
      final expected = jsonDecode(File(baseline!).readAsStringSync()) as Map;
      final ids = <String>[];
      for (final row in data['exercise_sessions'] as List) {
        final s = ExerciseSession.fromMap(Map<String, Object?>.from(row));
        final raw = (data['raw_route_points'] as List)
            .where((r) => r['sessionId'] == s.id)
            .toList();
        final rows = raw.isNotEmpty
            ? raw
            : (data['route_points'] as List).where(
                (r) => r['sessionId'] == s.id,
              );
        final analyzer = MovementAnalyzer(s, rawAvailable: raw.isNotEmpty);
        for (final r in rows) {
          analyzer.addRow(Map<String, Object?>.from(r));
        }
        final a = analyzer.finish();
        final actual = {
          'recordedMeters': s.distanceMeters,
          'elapsedSeconds': s.elapsedSeconds,
          'portfolio': PortfolioAnalysis(
            sampleOverviewRoute(a.route, 600),
            a.fastest?.speed,
            movement: a,
          ).toMap(),
        };
        // Avoid exposing private coordinates in a failed assertion's diff.
        expect(
          jsonEncode(actual) == jsonEncode(expected['${s.id}']),
          isTrue,
          reason: 'Release HEAD regression for session ${s.id}',
        );
        ids.add('${s.id}');
      }
      expect(ids, expected.keys.toList());
      expect(sourceFile.readAsStringSync() == before, isTrue);
    },
    skip: source == null || baseline == null
        ? 'Private S26 data/baseline not supplied (kept outside repository)'
        : false,
  );
}
