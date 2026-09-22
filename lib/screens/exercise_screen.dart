import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'portfolio_share_screen.dart';

import 'package:geolocator/geolocator.dart';

import '../data/record_repository.dart';
import '../data/portfolio_repository.dart' show averageKmh;
import '../models/exercise_session.dart';
import '../models/exercise_type.dart';
import '../services/exercise_recorder.dart';
import '../services/exercise_share.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import '../utils/movement_analysis.dart';
import '../widgets/movement_analysis_panel.dart';
import '../widgets/exercise_route.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({
    super.key,
    required this.recorder,
    required this.records,
  });
  final ExerciseRecorder recorder;
  final RecordRepository records;
  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  ExerciseType _type = ExerciseType.lightWalk;
  late Future<List<ExerciseSession>> _history;
  @override
  void initState() {
    super.initState();
    _refresh();
    _restoreType();
  }

  Future<void> _restoreType() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final name = preferences.getString('recent_exercise_type');
      if (mounted && !_typeTouched) {
        setState(
          () => _type =
              ExerciseType.values.where((t) => t.name == name).firstOrNull ??
              ExerciseType.lightWalk,
        );
      }
    } catch (_) {
      /* The default remains usable when preferences are unavailable. */
    }
  }

  bool _typeTouched = false;

  void _refresh() {
    _history = widget.recorder.repository.history();
  }

  Future<void> _start() async {
    _typeTouched = true;
    try {
      final weight = await widget.records.latestWeight(dateKey(DateTime.now()));
      if (!mounted) return;
      await widget.recorder.start(_type, weight);
      if (widget.recorder.active) {
        HapticFeedback.lightImpact();
        try {
          await (await SharedPreferences.getInstance()).setString(
            'recent_exercise_type',
            _type.name,
          );
        } catch (_) {
          /* Recording is already saved. */
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 불러오지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _finish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동을 종료할까요?'),
        content: const Text('지금까지의 경로와 기록을 저장해요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 운동'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('종료하고 저장'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();
    await widget.recorder.finish();
    if (mounted) {
      setState(_refresh);
      final session = widget.recorder.session;
      if (session != null && session.status == SessionStatus.finished) {
        await _openDetail(session);
      }
    }
  }

  Future<void> _openDetail(ExerciseSession session) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          session: session,
          route: widget.recorder.repository.route(session.id),
          analysis: (force) => widget.recorder.repository.movementAnalysis(
            session,
            recalculate: force,
          ),
          onDelete: () => widget.recorder.repository.deleteFinished(session.id),
        ),
      ),
    );
    if (mounted && deleted == true) setState(_refresh);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.recorder,
    builder: (context, _) {
      final recorder = widget.recorder;
      final session = recorder.live;
      return Scaffold(
        appBar: AppBar(title: Text(recorder.active ? '운동 기록 중' : 'GPS 운동')),
        body: recorder.active && session != null
            ? _RecordingView(recorder: recorder, finish: _finish)
            : SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpace.page),
                      children: [
                        if (recorder.issue case final issue?) ...[
                          Text(issue.message),
                          if (issue.appSettings)
                            TextButton(
                              onPressed: Geolocator.openAppSettings,
                              child: const Text('앱 설정 열기'),
                            ),
                          if (issue.locationSettings)
                            TextButton(
                              onPressed: Geolocator.openLocationSettings,
                              child: const Text('위치 설정 열기'),
                            ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          '오늘의 움직임',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text('운동을 고르고 시작하세요. 화면을 꺼도 기록이 이어져요.'),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: ExerciseType.values
                              .map(
                                (type) => ChoiceChip(
                                  label: Text(type.label),
                                  selected: _type == type,
                                  onSelected: recorder.busy
                                      ? null
                                      : (_) => setState(() {
                                          _typeTouched = true;
                                          _type = type;
                                          HapticFeedback.selectionClick();
                                        }),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: recorder.busy ? null : _start,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(recorder.busy ? '준비 중…' : '운동 시작'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '시작할 때 정확한 위치 권한이 필요해요. 예상 kcal는 최근 저장한 몸무게로 계산해요. GPS 운동은 오늘의 수동 기록과 별도로 저장돼요.',
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          '나의 운동 포트폴리오',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        FutureBuilder<List<ExerciseSession>>(
                          future: _history,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return TextButton(
                                onPressed: () => setState(_refresh),
                                child: const Text('운동 이력 다시 불러오기'),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(AppSpace.page),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.data!.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('완료한 운동이 여기에 표시돼요.'),
                              );
                            }
                            return Column(
                              children: [
                                _PortfolioOverview(sessions: snapshot.data!),
                                ...snapshot.data!.map(
                                  (s) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${dateKey(s.startedAt.toLocal())} · ${s.type.label}',
                                    ),
                                    subtitle: Text(
                                      '${(s.distanceMeters / 1000).toStringAsFixed(2)} km · ${elapsedLabel(s.elapsedSeconds)}',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(s),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );
}

class SessionStats extends StatelessWidget {
  const SessionStats({super.key, required this.session});
  final ExerciseSession session;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 300 &&
              MediaQuery.textScalerOf(context).scale(14) < 20
          ? 2
          : 1;
      final width =
          (constraints.maxWidth - (columns - 1) * AppSpace.large) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.large,
            runSpacing: AppSpace.medium,
            children: [
              for (final stat in [
                (
                  '기록 거리',
                  '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
                ('총 기록 시간', elapsedLabel(session.elapsedSeconds)),
              ])
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stat.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        stat.$2,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.medium),
          Wrap(
            spacing: AppSpace.large,
            runSpacing: AppSpace.small,
            children: [
              Text(
                '총 시간 평균 ${averageKmh(session)?.toStringAsFixed(1) ?? '—'} km/h',
              ),
              Text('페이스 ${paceLabel(session.paceSeconds)}'),
              Text(
                session.calories == null
                    ? '— kcal'
                    : '약 ${session.calories!.round()} kcal · 총 시간 기준',
              ),
            ],
          ),
        ],
      );
    },
  );
}

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.session,
    required this.route,
    required this.onDelete,
    this.analysis,
  });
  final ExerciseSession session;
  final Future<List<RoutePoint>> route;
  final Future<void> Function() onDelete;
  final Future<MovementAnalysis> Function(bool recalculate)? analysis;
  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  bool _hide = true, _sharing = false, _deleting = false;
  final _shareMap = GlobalKey<ExerciseRouteState>();
  RoutePoint? _selectedPoint;
  Future<void> _delete() async {
    if (_deleting || _sharing) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('운동 기록을 삭제할까요?'),
          content: const Text(
            '이 운동과 관련된 경로·원본 GPS 데이터가 함께 삭제돼요. 삭제한 기록은 복구할 수 없어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.onDelete();
      if (!mounted) return;
      setState(() => _deleting = false);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 삭제하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted && _deleting) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('운동 기록'),
        actions: [
          IconButton(
            tooltip: '기록 삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed:
                _sharing ||
                    _deleting ||
                    widget.session.status != SessionStatus.finished
                ? null
                : _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.page),
          children: [
            Text(
              '${dateKey(widget.session.startedAt.toLocal())} · ${widget.session.type.label}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            FutureBuilder<List<RoutePoint>>(
              future: widget.route,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpace.page),
                    child: Text('경로를 불러오지 못했어요. 화면을 다시 열어 주세요.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final points = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    if (widget.analysis != null)
                      MovementAnalysisPanel(
                        session: widget.session,
                        load: widget.analysis!,
                        summary: SessionStats(session: widget.session),
                      )
                    else ...[
                      ExerciseRoute(
                        points: points,
                        height: 340,
                        selectedPoint: _selectedPoint,
                      ),
                      const SizedBox(height: AppSpace.large),
                      SessionStats(session: widget.session),
                      const SizedBox(height: AppSpace.section),
                      SpeedAnalysis(
                        points: points,
                        onSelected: (p) => setState(() => _selectedPoint = p),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      '기록 거리·총 기록 시간은 목록·포트폴리오·공유에 동일하게 사용해요. 총 기록 시간은 정지·미분류를 포함하고 수동 일시정지는 제외해요. kcal는 이 총 시간과 운동 종류의 MET로 계산한 추정치예요.',
                    ),
                    const SizedBox(height: 32),
                    Text(
                      '공유 미리보기',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          MediaQuery.withNoTextScaling(
                            child: ExerciseRoute(
                              key: _shareMap,
                              points: _hide ? privateRoute(points) : points,
                              private: _hide,
                              interactive: false,
                              height: constraints.maxWidth * 370 / 640,
                            ),
                          ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _hide ? '시작·종료 위치 200m 숨김 켜짐' : '시작·종료 위치 숨김 꺼짐',
                      ),
                      subtitle: const Text(
                        '주변 200m를 숨겨요. 짧은 경로는 모두 숨겨질 수 있어요.',
                      ),
                      value: _hide,
                      onChanged: _sharing || _deleting
                          ? null
                          : (v) => setState(() => _hide = v),
                    ),
                    const Text(
                      '공유할 경로를 확인해 주세요. 숨김을 사용해도 주변 경로로 장소를 추측할 수 있어요.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (buttonContext) => FilledButton.icon(
                        icon: const Icon(Icons.ios_share),
                        label: Text(_sharing ? '이미지 준비 중…' : '운동 결과 공유'),
                        onPressed: _sharing || _deleting
                            ? null
                            : () async {
                                setState(() => _sharing = true);
                                ui.Image? mapImage;
                                try {
                                  final visible = _hide
                                      ? privateRoute(points)
                                      : points;
                                  if (visible.isNotEmpty) {
                                    mapImage = await _shareMap.currentState!
                                        .capture();
                                  }
                                  if (!mounted) return;
                                  final bytes = await exerciseShareImage(
                                    widget.session,
                                    points,
                                    hideEndpoints: _hide,
                                    mapImage: mapImage,
                                  );
                                  if (!context.mounted) return;
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PortfolioShareScreen.image(
                                        title: '운동 결과',
                                        image: () async => bytes,
                                        notice: _hide
                                            ? '시작·종료 위치 200m 숨김 켜짐 · 짧은 경로는 모두 숨겨질 수 있어요.'
                                            : '시작·종료 위치 숨김 꺼짐 · 전체 경로가 포함돼요.',
                                        fileName:
                                            'diligent-life-${widget.session.id}.png',
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '공유 지도를 불러오지 못했어요. 인터넷 연결과 지도 미리보기를 확인해 주세요.',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  mapImage?.dispose();
                                  if (mounted) setState(() => _sharing = false);
                                }
                              },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('GPS 거리·속도와 MET 칼로리는 추정치예요. 지도 로딩에는 인터넷 연결이 필요해요.'),
          ],
        ),
      ),
    ),
  );
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({required this.recorder, required this.finish});
  final ExerciseRecorder recorder;
  final VoidCallback finish;
  @override
  Widget build(BuildContext context) {
    final session = recorder.live!;
    final speed = recorder.currentSpeedKmh;
    final pause = FilledButton.icon(
      onPressed: recorder.busy
          ? null
          : () {
              HapticFeedback.selectionClick();
              recorder.recording ? recorder.pause() : recorder.resume();
            },
      icon: Icon(recorder.recording ? Icons.pause : Icons.play_arrow),
      label: Text(recorder.recording ? '일시정지' : '재개'),
    );
    final stop = OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: recorder.busy ? null : finish,
      child: const Text('운동 종료'),
    );
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            flex: MediaQuery.textScalerOf(context).scale(14) > 20 ? 4 : 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    ExerciseRoute(
                      points: recorder.points,
                      currentPosition: recorder.currentPosition,
                      live: true,
                      height: constraints.maxHeight,
                    ),
                    Positioned(
                      left: AppSpace.medium,
                      bottom: 36,
                      right: AppSpace.medium,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppStyle.radius),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.medium,
                              vertical: AppSpace.small,
                            ),
                            child: Text(
                              !recorder.recording
                                  ? '일시정지 · 재개하면 이어서 기록해요'
                                  : recorder.waitingForGps
                                  ? 'GPS 연결 중 · 기록은 유지돼요'
                                  : (recorder.currentPosition?.accuracy ?? 0) >
                                        30
                                  ? 'GPS 신호 약함'
                                  : 'GPS 연결됨',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: MediaQuery.textScalerOf(context).scale(14) > 20 ? 6 : 4,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppStyle.panelRadius),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${session.type.label} · ${recorder.recording ? '기록 중' : '일시정지'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          SessionStats(session: session),
                          const SizedBox(height: 16),
                          Text(
                            '현재 ${speed == null ? '—' : speed.toStringAsFixed(1)} km/h · GPS ${!recorder.recording
                                ? '일시정지'
                                : recorder.waitingForGps
                                ? '연결 중'
                                : (recorder.currentPosition?.accuracy ?? 0) > 30
                                ? '신호 약함'
                                : '연결됨'}',
                          ),
                          if (recorder.waitingForGps)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'GPS 신호를 기다리고 있어요. 실외에서 정확한 위치를 받을 수 있어요.',
                              ),
                            ),
                          if (recorder.issue case final issue?) ...[
                            Text(issue.message),
                            if (issue.appSettings)
                              TextButton(
                                onPressed: Geolocator.openAppSettings,
                                child: const Text('앱 설정 열기'),
                              ),
                            if (issue.locationSettings)
                              TextButton(
                                onPressed: Geolocator.openLocationSettings,
                                child: const Text('위치 설정 열기'),
                              ),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            '자동 저장 · 일시정지와 GPS 수신 공백은 연결하지 않아요.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (session.weightKg == null)
                            const Text(
                              '몸무게를 저장하면 다음 운동부터 예상 kcal도 함께 남겨요.',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: MediaQuery.textScalerOf(context).scale(14) > 20
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [pause, const SizedBox(height: 8), stop],
                          )
                        : Row(
                            children: [
                              Expanded(child: pause),
                              const SizedBox(width: 12),
                              Expanded(child: stop),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpeedAnalysis extends StatefulWidget {
  const SpeedAnalysis({super.key, required this.points, this.onSelected});
  final List<RoutePoint> points;
  final ValueChanged<RoutePoint>? onSelected;
  @override
  State<SpeedAnalysis> createState() => _SpeedAnalysisState();
}

class _SpeedAnalysisState extends State<SpeedAnalysis> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final sections = speedSections(widget.points);
    if (sections.isEmpty) return const Text('속도 분석 · 5초 이상 이어진 이동 구간이 아직 없어요.');
    final selected = sections[_index.clamp(0, sections.length - 1)];
    String time(DateTime value) =>
        '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}:${value.toLocal().second.toString().padLeft(2, '0')}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('움직임의 리듬', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('약 5초 구간의 거리 ÷ 시간으로 속도를 부드럽게 표시해요. GPS 공백은 제외해요.'),
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // At most 80 bars, regardless of session length.
                  final count = sections.length.clamp(1, 80);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(count, (i) {
                      final s = sections[i * sections.length ~/ count];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Container(
                            height: (s.kmh / 20 * 64).clamp(3, 64),
                            decoration: BoxDecoration(
                              color: speedColor(s.kmh),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final item in [
                  (2.0, '<4 km/h'),
                  (5.0, '4–7 km/h'),
                  (8.0, '≥7 km/h'),
                ])
                  Text(
                    '● ${item.$2}',
                    style: TextStyle(color: speedColor(item.$1), fontSize: 12),
                  ),
              ],
            ),
            if (sections.length > 1)
              Slider(
                label: '${_index + 1} 구간',
                value: _index.toDouble(),
                max: (sections.length - 1).toDouble(),
                onChanged: (value) {
                  setState(() => _index = value.round());
                  widget.onSelected?.call(sections[_index].points.last);
                },
              ),
            Text(
              '${selected.kmh.toStringAsFixed(1)} km/h · ${paceLabel(selected.paceSeconds)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${time(selected.points.first.timestamp)} – ${time(selected.points.last.timestamp)} · ${selected.meters.round()} m',
            ),
            const Text(
              '구간을 선택하면 위 지도에 위치가 표시돼요.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioOverview extends StatelessWidget {
  const _PortfolioOverview({required this.sessions});
  final List<ExerciseSession> sessions;
  @override
  Widget build(BuildContext context) {
    final summary = MovementSummary.fromSessions(sessions);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppStyle.radius),
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${summary.count}번의 움직임 · ${(summary.meters / 1000).toStringAsFixed(2)} km',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('누적 시간 ${elapsedLabel(summary.seconds)}'),
          Text(
            summary.calories == null
                ? '예상 누적 소모 — kcal'
                : '예상 누적 소모 약 ${summary.calories!.round()} kcal${summary.calorieCount < summary.count ? ' · 몸무게가 있는 ${summary.calorieCount}개 기록' : ''}',
          ),
          const SizedBox(height: 8),
          const Text(
            '완료한 GPS 운동이 차곡차곡 쌓이고 있어요.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
