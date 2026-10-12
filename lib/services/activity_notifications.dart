import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/exercise_session.dart';
import 'exercise_recorder.dart';

Duration Function() _monotonicClock() {
  final clock = Stopwatch()..start();
  return () => clock.elapsed;
}

String _token() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String notificationClock(int seconds) {
  final h = seconds ~/ 3600, m = seconds ~/ 60 % 60, s = seconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String workoutNotificationDetail(ExerciseSession session) {
  final km = session.distanceMeters / 1000;
  final pace = km > 0 && session.elapsedSeconds > 0
      ? '${notificationClock((session.elapsedSeconds / km).round())} /km'
      : '페이스 —';
  return '${km.toStringAsFixed(2)} km · ${notificationClock(session.elapsedSeconds)}\n$pace';
}

// Presentation only. Existing recorder owns GPS, persistence and all controls.
// One trailing callback coalesces dirty snapshots; there is no idle/periodic timer.
class ActivityNotificationController {
  ActivityNotificationController(
    this.recorder, {
    required this.onNavigate,
    MethodChannel? channel,
    Duration Function()? elapsed,
    String Function()? tokenFactory,
  }) : _channel =
           channel ??
           const MethodChannel('diligent_life/activity_notifications'),
       _elapsed = elapsed ?? _monotonicClock(),
       _tokenFactory = tokenFactory ?? _token;

  final ExerciseRecorder recorder;
  final Future<void> Function(String destination) onNavigate;
  final MethodChannel _channel;
  final Duration Function() _elapsed;
  final String Function() _tokenFactory;
  String? _state, _generation;
  Duration? _lastSent;
  Timer? _trailing;
  Future<void> _publishing = Future.value(), _actions = Future.value();
  bool _disposed = false;
  static const updateInterval = Duration(seconds: 15);

  void start() {
    recorder.addListener(_changed);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _drain();
    });
    refresh();
    unawaited(_drain());
  }

  void refresh() => _changed(force: true);

  void _changed({bool force = false}) {
    if (_disposed) return;
    final session = recorder.active ? recorder.live : null;
    final state = session == null
        ? 'idle'
        : '${session.id}/${session.startedAt.toUtc().toIso8601String()}/${session.status.name}';
    final transition = state != _state;
    if (transition) {
      _state = state;
      _generation = session == null ? null : _tokenFactory();
    }
    final now = _elapsed();
    final remaining = _lastSent == null
        ? Duration.zero
        : updateInterval - (now - _lastSent!);
    if (!force && !transition && remaining > Duration.zero) {
      if (session != null && recorder.recording) {
        _trailing ??= Timer(remaining, () {
          _trailing = null;
          refresh();
        });
      }
      return;
    }
    _trailing?.cancel();
    _trailing = null;
    if (!force && !transition && session == null) return;
    _lastSent = now;
    final snapshot = session == null
        ? null
        : <String, Object>{
            'token': _generation!,
            'recording': recorder.recording,
            'title': session.type.label,
            'seconds': session.elapsedSeconds,
            'detail': workoutNotificationDetail(session),
          };
    _publishing = _publishing.then((_) async {
      if (_disposed) return;
      try {
        await _channel.invokeMethod<void>('workout', snapshot);
      } on MissingPluginException {
        /* Other platforms keep recording normally. */
      } on PlatformException {
        /* Notification permission must not interrupt recording. */
      }
    });
  }

  Future<void> _drain() {
    _actions = _actions.then((_) async {
      if (_disposed) return;
      try {
        while (!_disposed) {
          final action = await _channel.invokeMapMethod<String, dynamic>(
            'takeAction',
          );
          if (action == null) break;
          await handleAction(action);
        }
      } on MissingPluginException {
        /* No native notification surface. */
      } on PlatformException {
        /* Keep normal in-app controls usable. */
      }
    });
    return _actions;
  }

  Future<void> handleAction(Map<String, dynamic> action) async {
    if (_disposed) return;
    final name = action['action'], token = action['token'];
    // A restored process and every state transition mint a new generation.
    if (token != '' && (token != _generation || !recorder.active)) return;
    if (['today', 'profile', 'growth'].contains(name) && token == '') {
      await onNavigate(name as String);
      return;
    }
    if (name == 'exercise') {
      await onNavigate('exercise');
      return;
    }
    if (token == null || token == '' || recorder.busy) return;
    if (name == 'pause' && recorder.recording) {
      await recorder.pause();
    }
    if (name == 'resume' && recorder.active && !recorder.recording) {
      await recorder.resume();
    }
  }

  void dispose() {
    _disposed = true;
    _trailing?.cancel();
    recorder.removeListener(_changed);
    _channel.setMethodCallHandler(null);
  }
}
