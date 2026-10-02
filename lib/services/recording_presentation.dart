import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/exercise_session.dart';
import 'exercise_recorder.dart';

class RecordingMapSnapshot {
  const RecordingMapSnapshot(this.points, this.position);
  final List<RoutePoint> points;
  final RoutePoint? position;
}

// Presentation has no responsibility for sensors, persistence or the clock.
// Hidden screens receive no ticks; their next visible snapshot catches up.
class RecordingPresentation extends ChangeNotifier {
  RecordingPresentation(this.recorder) {
    recorder.addListener(_changed);
    _rememberState();
  }
  final ExerciseRecorder recorder;
  final map = ValueNotifier<RecordingMapSnapshot>(
    const RecordingMapSnapshot([], null),
  );
  Timer? _uiTimer;
  bool _visible = false;
  bool? _busy;
  SessionStatus? _status;
  LocationIssue? _issue;
  int? _sessionId;
  int _ticks = 0;
  double? speedKmh;

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _syncTimer();
    if (visible) _refresh(mapToo: true);
  }

  void _rememberState() {
    _busy = recorder.busy;
    _status = recorder.session?.status;
    _issue = recorder.issue;
    _sessionId = recorder.session?.id;
  }

  void _changed() {
    final controlsChanged =
        _busy != recorder.busy ||
        _status != recorder.session?.status ||
        _issue != recorder.issue ||
        _sessionId != recorder.session?.id;
    _rememberState();
    if (!controlsChanged) return; // GPS callbacks do not drive rendering.
    _syncTimer();
    if (_visible) _refresh(mapToo: true);
  }

  void _syncTimer() {
    if (!_visible || !recorder.recording) {
      _uiTimer?.cancel();
      _uiTimer = null;
      return;
    }
    _uiTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _ticks++;
      _refresh(mapToo: _ticks.isEven);
    });
  }

  void _refresh({required bool mapToo}) {
    speedKmh = recorder.currentSpeedKmh;
    if (mapToo) {
      final points = recorder.points;
      final position = recorder.currentPosition;
      if (!identical(map.value.points, points) ||
          map.value.position != position) {
        map.value = RecordingMapSnapshot(points, position);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    recorder.removeListener(_changed);
    map.dispose();
    super.dispose();
  }
}
