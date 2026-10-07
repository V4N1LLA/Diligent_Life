import 'dart:isolate';

import '../models/activity_report.dart';
import '../models/daily_record.dart';
import 'exercise_repository.dart';
import 'record_repository.dart';

class ReportRepository {
  ReportRepository(this.records, this.exercises);
  final RecordRepository records;
  final ExerciseRepository exercises;
  // Screen-lifetime summaries only; persistent GPS analysis is already versioned
  // in portfolio_analysis. Refresh/detail-return clears these lightweight values.
  final _entries = <int, (String, ReportEntry)>{};
  void invalidate() => _entries.clear();

  Future<ActivityReport> load(
    ReportPeriod period,
    DateTime anchor,
    DateTime now,
  ) async {
    final window = ReportWindow(period, anchor, now);
    final sessions = await exercises.finishedBetween(before: window.before);
    final weights = await records.list(
      since: window.start.toIso8601String().substring(0, 10),
      until: DateTime(
        window.before.year,
        window.before.month,
        window.before.day - 1,
      ).toIso8601String().substring(0, 10),
    );
    final entries = <ReportEntry>[];
    for (final session in sessions) {
      final stamp = session.toMap().toString();
      var cached = _entries[session.id];
      if (cached == null || cached.$1 != stamp) {
        cached = (
          stamp,
          ReportEntry(session, await exercises.portfolioAnalysis(session)),
        );
        _entries[session.id] = cached;
      }
      entries.add(cached.$2);
    }
    return _assemble(window, entries, weights);
  }
}

// Isolate closure captures only data, never SQLite handles.
Future<ActivityReport> _assemble(
  ReportWindow window,
  List<ReportEntry> entries,
  List<DailyRecord> weights,
) => Isolate.run(() => buildActivityReport(window, entries, weights));
