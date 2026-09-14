import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../data/exercise_repository.dart';
import '../models/exercise_session.dart';
import '../models/exercise_type.dart';
import '../utils/gps.dart';

class LocationIssue implements Exception {
  const LocationIssue(
    this.message, {
    this.appSettings = false,
    this.locationSettings = false,
  });
  final String message;
  final bool appSettings, locationSettings;
}

// Small adapter keeps permission/platform calls out of state and DB tests.
class ExerciseLocation {
  Stream<bool> serviceEnabled() => Geolocator.getServiceStatusStream().map(
    (status) => status == ServiceStatus.enabled,
  );

  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationIssue(
        '위치 서비스를 켠 뒤 다시 시작해 주세요.',
        locationSettings: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationIssue(
        '앱 설정에서 정확한 위치 권한을 허용해 주세요.',
        appSettings: true,
      );
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw const LocationIssue('운동 경로를 기록하려면 위치 권한이 필요해요.');
    }
    if (await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced) {
      throw const LocationIssue(
        '경로 기록에는 정확한 위치가 필요해요. 앱 설정에서 변경해 주세요.',
        appSettings: true,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Requested only on explicit exercise start/resume, independent of reminders.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  Stream<RoutePoint> positions() =>
      Geolocator.getPositionStream(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 0,
                intervalDuration: const Duration(seconds: 2),
                foregroundNotificationConfig:
                    const ForegroundNotificationConfig(
                      notificationTitle: 'Diligent Life · 운동 기록 중',
                      notificationText: '시간과 경로를 기록하고 있어요. 눌러서 운동을 관리하세요.',
                      enableWakeLock: true,
                      setOngoing: true,
                    ),
              )
            : AppleSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 0,
                activityType: ActivityType.fitness,
                pauseLocationUpdatesAutomatically: false,
                showBackgroundLocationIndicator: true,
              ),
      ).map(
        (p) => RoutePoint(
          latitude: p.latitude,
          longitude: p.longitude,
          timestamp: p.timestamp,
          accuracy: p.accuracy,
          rawSpeed: p.speed,
        ),
      );
}

class ExerciseRecorder extends ChangeNotifier {
  ExerciseRecorder(
    this.repository, {
    ExerciseLocation? location,
    Stopwatch? clock,
  }) : _location = location ?? ExerciseLocation(),
       _clock = clock ?? Stopwatch();
  final ExerciseRepository repository;
  final ExerciseLocation _location;
  final Stopwatch _clock;
  ExerciseSession? session;
  final List<RoutePoint> _points = [];
  List<RoutePoint> get points => List.unmodifiable(_points);
  RoutePoint? currentPosition;
  double? get currentSpeedKmh {
    if (!recording ||
        currentPosition == null ||
        DateTime.now()
                .toUtc()
                .difference(currentPosition!.timestamp)
                .inSeconds >
            10) {
      return null;
    }
    if (_points.isNotEmpty &&
        currentPosition!.timestamp
                .difference(_points.last.timestamp)
                .inSeconds >=
            5) {
      return 0;
    }
    final recent = _points.reversed
        .takeWhile(
          (p) =>
              p.segment == currentPosition!.segment &&
              currentPosition!.timestamp.difference(p.timestamp).inSeconds <=
                  15,
        )
        .toList()
        .reversed
        .toList();
    final windows = speedSections(recent);
    if (windows.isEmpty) return null;
    final last = windows.last;
    if (currentPosition!.timestamp
            .difference(last.points.last.timestamp)
            .inSeconds >
        5) {
      return 0;
    }
    return last.kmh;
  }

  GpsFilter _filter = GpsFilter();
  StreamSubscription<RoutePoint>? _subscription;
  StreamSubscription<bool>? _serviceSubscription;
  DateTime? _segmentStartedAt, _lastFixAt;
  Timer? _timer;
  Future<void> _queue = Future.value();
  int _baseSeconds = 0;
  bool busy = false;
  LocationIssue? issue;
  bool get active =>
      session != null && session!.status != SessionStatus.finished;
  bool get recording => active && session!.status == SessionStatus.recording;
  int get elapsedSeconds => _baseSeconds + _clock.elapsed.inSeconds;
  ExerciseSession? get live =>
      session?.copyWith(elapsedSeconds: elapsedSeconds);
  bool get waitingForGps =>
      recording &&
      (_lastFixAt == null ||
          DateTime.now().toUtc().difference(_lastFixAt!).inSeconds > 30);

  Future<void> restore() async {
    // Restore also runs after a confirmed backup replacement while idle.
    if (active) throw StateError('Cannot restore during an active exercise');
    session = null;
    _points.clear();
    _clock.reset();
    _baseSeconds = 0;
    currentPosition = null;
    _lastFixAt = null;
    final saved = await repository.active();
    if (saved == null) return;
    // Never count time or connect GPS segments across a killed process.
    session = saved.copyWith(
      status: SessionStatus.paused,
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.checkpoint(session!);
    _baseSeconds = saved.elapsedSeconds;
    _points.addAll(await repository.route(saved.id));
    _filter = GpsFilter(maxSpeed: TrackingPolicy.maxSpeed(saved.type));
    // Restored routes use a different segment namespace.
    for (var i = 0; i <= (_points.isEmpty ? 0 : _points.last.segment); i++) {
      _filter.breakSegment();
    }
    issue = const LocationIssue('이전 운동을 복구했어요. 재개하거나 종료할 수 있어요.');
    notifyListeners();
  }

  // Serialize sensor callbacks, timer checkpoints and user actions. A point and
  // its accumulated statistics always commit together, including while stopping.
  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.catchError((Object error) async {
      _clock.stop();
      _timer?.cancel();
      await _subscription?.cancel();
      _subscription = null;
      await _serviceSubscription?.cancel();
      _serviceSubscription = null;
      if (active) session = session!.copyWith(status: SessionStatus.paused);
      issue = error is LocationIssue
          ? error
          : const LocationIssue('기록을 잠시 멈췄어요. 저장 공간과 위치 설정을 확인한 뒤 다시 시도해 주세요.');
      notifyListeners();
    });
    return _queue;
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    await _enqueue(action);
    busy = false;
    notifyListeners();
  }

  Future<void> start(ExerciseType type, double? weight) => _action(() async {
    if (active) return;
    await _location.prepare();
    session = await repository.start(type, weight, DateTime.now().toUtc());
    _points.clear();
    _filter = GpsFilter(maxSpeed: TrackingPolicy.maxSpeed(type));
    currentPosition = null;
    _baseSeconds = 0;
    _clock.reset();
    _listen();
  });
  void _listen() {
    issue = null;
    _filter.breakSegment();
    _segmentStartedAt = DateTime.now().toUtc();
    _lastFixAt = null;
    _clock.start();
    _subscription = _location.positions().listen(
      (point) {
        final receivedAt = DateTime.now().toUtc();
        unawaited(
          _enqueue(() async {
            if (!recording) {
              return;
            }
            if (point.timestamp.isBefore(_segmentStartedAt!)) {
              await repository.checkpoint(
                live!,
                rawPoint: point.inSegment(_filter.segment),
                receivedAt: receivedAt,
                decision: 'before_segment',
                filterVersion: TrackingPolicy.version,
              );
              return;
            }
            final accepted = _filter.accept(point, receivedAt);
            if (_filter.decision == 'accepted' ||
                _filter.decision == 'stationary_noise') {
              _lastFixAt = point.timestamp;
              currentPosition = point.inSegment(_filter.segment);
            }
            final next = live!.copyWith(
              distanceMeters: session!.distanceMeters + _filter.addedMeters,
              updatedAt: DateTime.now().toUtc(),
            );
            await repository.checkpoint(
              next,
              point: accepted?.withDistance(next.distanceMeters),
              rawPoint: point
                  .inSegment(_filter.segment)
                  .withDistance(next.distanceMeters),
              receivedAt: receivedAt,
              decision: _filter.decision,
              filterVersion: TrackingPolicy.version,
            );
            session = next;
            if (accepted != null) {
              _points.add(accepted.withDistance(next.distanceMeters));
            }
            notifyListeners();
          }),
        );
      },
      onError: (Object error) => _locationLost(),
      onDone: _locationLost,
    );
    _serviceSubscription = _location.serviceEnabled().listen((enabled) {
      if (!enabled) _locationLost();
    }, onError: (Object error) => _locationLost());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      if (elapsedSeconds % 5 == 0) {
        unawaited(
          _enqueue(() async {
            if (recording) {
              final next = live!.copyWith(updatedAt: DateTime.now().toUtc());
              await repository.checkpoint(next);
              session = next;
            }
          }),
        );
      }
    });
  }

  void _locationLost() {
    unawaited(
      _enqueue(() async {
        if (!recording) return;
        await _pause();
        issue = const LocationIssue(
          '위치를 받을 수 없어 일시정지했어요. 위치 서비스를 확인하고 재개해 주세요.',
          locationSettings: true,
        );
        notifyListeners();
      }),
    );
  }

  Future<void> _pause() async {
    _clock.stop();
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _serviceSubscription?.cancel();
    _serviceSubscription = null;
    final next = live!.copyWith(
      status: SessionStatus.paused,
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.checkpoint(next);
    session = next;
  }

  Future<void> pause() => _action(() async {
    if (recording) await _pause();
  });
  Future<void> resume() => _action(() async {
    if (!active || recording) return;
    await _location.prepare();
    final next = live!.copyWith(
      status: SessionStatus.recording,
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.checkpoint(next);
    session = next;
    _listen();
  });
  Future<void> finish() => _action(() async {
    if (!active) return;
    _clock.stop();
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _serviceSubscription?.cancel();
    _serviceSubscription = null;
    final now = DateTime.now().toUtc();
    final next = live!.copyWith(
      status: SessionStatus.finished,
      updatedAt: now,
      endedAt: now,
    );
    await repository.checkpoint(next);
    session = next;
    issue = null;
  });
  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    unawaited(_subscription?.cancel());
    unawaited(_serviceSubscription?.cancel());
    super.dispose();
  }
}
