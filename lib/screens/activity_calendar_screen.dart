import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/activity_calendar_repository.dart';
import '../data/exercise_repository.dart';
import '../models/activity_calendar.dart';
import '../models/exercise_session.dart';
import '../services/monthly_share.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/activity_style.dart';
import 'exercise_screen.dart';
import 'portfolio_share_screen.dart';

String _monthLabel(DateTime month) => '${month.year}년 ${month.month}월';
String _daySummary(CalendarDay day) => [
  '${stepLabel(day.steps)}걸음',
  if (day.workouts > 0)
    '${(day.meters / 1000).toStringAsFixed(1)} km · ${day.workouts}회 운동',
  if (day.regions > 0) '새로운 지역 ${day.regions}곳 발견',
  ...day.milestones.take(2),
  if (day.milestones.length > 2) '성장 기록 ${day.milestones.length - 2}개 더 보기',
].join('\n');

AppBar _calendarAppBar(BuildContext context, String title) => AppBar(
  toolbarHeight: math.max(
    kToolbarHeight,
    52 * MediaQuery.textScalerOf(context).scale(1),
  ),
  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
);

class ActivityCalendarScreen extends StatefulWidget {
  const ActivityCalendarScreen({
    super.key,
    required this.repository,
    required this.exercises,
    this.now,
  });
  final ActivityCalendarRepository repository;
  final ExerciseRepository exercises;
  final DateTime Function()? now;
  @override
  State<ActivityCalendarScreen> createState() => _ActivityCalendarScreenState();
}

class _ActivityCalendarScreenState extends State<ActivityCalendarScreen>
    with WidgetsBindingObserver {
  late DateTime _month;
  late Future<(CalendarMonth, CalendarMonth)> _data;
  bool _timeline = false;
  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toLocal();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _month = DateTime(_now.year, _now.month);
    _reload();
  }

  void _reload() {
    _data = widget.repository.month(_month, _now);
    _data.ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_reload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _day(String date) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityDayScreen(
          date: DateTime.parse(date),
          repository: widget.repository,
          exercises: widget.exercises,
          now: widget.now,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  void _move(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _reload();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _calendarAppBar(context, '움직임 기록'),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: Wrap(
            spacing: AppSpace.small,
            children: [
              ChoiceChip(
                label: const Text('캘린더'),
                selected: !_timeline,
                onSelected: (_) => setState(() => _timeline = false),
              ),
              ChoiceChip(
                label: const Text('타임라인'),
                selected: _timeline,
                onSelected: (_) => setState(() => _timeline = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: _timeline
              ? ActivityTimeline(
                  key: ValueKey(_data),
                  repository: widget.repository,
                  now: widget.now,
                  onDay: _day,
                )
              : FutureBuilder<(CalendarMonth, CalendarMonth)>(
                  future: _data,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _LoadError(onRetry: () => setState(_reload));
                    }
                    if (snapshot.connectionState != ConnectionState.done ||
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final (month, previous) = snapshot.data!;
                    return ListView(
                      padding: const EdgeInsets.all(AppSpace.page),
                      children: [
                        Text(
                          _monthLabel(_month),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Wrap(
                          spacing: AppSpace.small,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              tooltip: '이전 달',
                              onPressed: () => _move(-1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _month = DateTime(_now.year, _now.month);
                                _reload();
                              }),
                              child: const Text('이번 달'),
                            ),
                            IconButton(
                              tooltip: '다음 달',
                              onPressed:
                                  _month.isBefore(
                                    DateTime(_now.year, _now.month),
                                  )
                                  ? () => _move(1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.medium),
                        ActivitySurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('이번 달의 움직임'),
                              const SizedBox(height: AppSpace.small),
                              Text(
                                '${stepLabel(month.steps)} 걸음',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: AppSpace.medium),
                              Text(
                                '${(month.meters / 1000).toStringAsFixed(1)} km 운동 · ${month.workouts}회',
                              ),
                              Text('새로운 지역 ${month.regions}곳 발견'),
                              if (month.workoutDays > 0)
                                Text('${month.workoutDays}일 동안 운동을 기록했어요'),
                              if (previous.steps > 0 ||
                                  previous.workouts > 0) ...[
                                const SizedBox(height: AppSpace.medium),
                                if (previous.steps > 0)
                                  Text(
                                    '지난달보다 ${month.steps - previous.steps >= 0 ? '+' : ''}${stepLabel(month.steps - previous.steps)} 걸음',
                                  ),
                                if (previous.workouts > 0)
                                  Text(
                                    '운동 거리 ${month.meters - previous.meters >= 0 ? '+' : ''}${((month.meters - previous.meters) / 1000).toStringAsFixed(1)} km',
                                  ),
                                if (_month.year == _now.year &&
                                    _month.month == _now.month)
                                  const Text('이번 달 현재까지와 지난달 전체 비교'),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpace.large),
                        CalendarGrid(month: month, today: _now, onDay: _day),
                        const SizedBox(height: AppSpace.medium),
                        const Text('배경은 걸음량 · ● 운동 · ◆ 탐험 · ✦ 성취'),
                        const SizedBox(height: AppSpace.small),
                        const Text('빈 날도 자연스러운 기록의 일부예요.'),
                        const SizedBox(height: AppSpace.large),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.ios_share),
                          label: const Text('월간 기록 공유'),
                          onPressed: () {
                            final brightness = Theme.of(context).brightness;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PortfolioShareScreen.image(
                                  title: '월간 기록',
                                  image: () =>
                                      monthlyShareImage(month, brightness),
                                  notice:
                                      '월간 합계와 대표 성취만 포함해요. 위치·경로·체중은 공유하지 않아요.',
                                  fileName:
                                      'diligent-life-month-${dateKey(_month).substring(0, 7)}.png',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    super.key,
    required this.month,
    required this.today,
    required this.onDay,
  });
  final CalendarMonth month;
  final DateTime today;
  final ValueChanged<String> onDay;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.month.year, month.month.month);
    final count = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday % 7;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(7 * AppStyle.touchTarget, constraints.maxWidth);
        final cellWidth = width / 7;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (width > constraints.maxWidth)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpace.small),
                child: Text('달력을 좌우로 밀어 모든 요일을 볼 수 있어요.'),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final label in ['일', '월', '화', '수', '목', '금', '토'])
                          SizedBox(
                            width: cellWidth,
                            child: Center(child: Text(label)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.small),
                    for (
                      var week = 0;
                      week < ((offset + count) / 7).ceil();
                      week++
                    )
                      Row(
                        children: [
                          for (var weekday = 0; weekday < 7; weekday++)
                            _cell(
                              context,
                              first,
                              week * 7 + weekday - offset + 1,
                              count,
                              cellWidth,
                              scheme,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime first,
    int number,
    int count,
    double width,
    ColorScheme scheme,
  ) {
    if (number < 1 || number > count) return SizedBox(width: width, height: 64);
    final date = DateTime(first.year, first.month, number), key = dateKey(date);
    final future = date.isAfter(dayOnly(today.toLocal()));
    final day = future ? CalendarDay(key) : month.days[key] ?? CalendarDay(key);
    final intensity = day.steps == 0
        ? 0.0
        : day.steps < 2500
        ? .08
        : day.steps < 5000
        ? .16
        : day.steps < 10000
        ? .26
        : .38;
    final current = key == dateKey(today.toLocal());
    return SizedBox(
      width: width,
      height: 64,
      child: Semantics(
        label:
            '$key${current ? ', 오늘' : ''}, ${future ? '미래 날짜' : _daySummary(day).replaceAll('\n', ', ')}',
        button: !future,
        enabled: !future,
        onTap: future ? null : () => onDay(key),
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.zero,
            child: Material(
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: intensity),
                scheme.surface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpace.medium),
                side: current
                    ? BorderSide(color: scheme.primary)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: future ? null : () => onDay(key),
                borderRadius: BorderRadius.circular(AppSpace.medium),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Compact visual numerals; the full scalable date is in Day Detail and semantics.
                    Text(
                      '$number',
                      textScaler: const TextScaler.linear(1),
                      style: TextStyle(
                        fontSize: 16,
                        color: future
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (day.workouts > 0)
                          Text(
                            '●',
                            textScaler: const TextScaler.linear(1),
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.primary,
                            ),
                          ),
                        if (day.regions > 0)
                          Text(
                            '◆',
                            textScaler: const TextScaler.linear(1),
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.primary,
                            ),
                          ),
                        if (day.milestones.isNotEmpty)
                          Text(
                            '✦',
                            textScaler: const TextScaler.linear(1),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityDayScreen extends StatefulWidget {
  const ActivityDayScreen({
    super.key,
    required this.date,
    required this.repository,
    required this.exercises,
    this.now,
  });
  final DateTime date;
  final ActivityCalendarRepository repository;
  final ExerciseRepository exercises;
  final DateTime Function()? now;
  @override
  State<ActivityDayScreen> createState() => _ActivityDayScreenState();
}

class _ActivityDayScreenState extends State<ActivityDayScreen>
    with WidgetsBindingObserver {
  late Future<(CalendarDay, List<ExerciseSession>)> _data;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_reload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _reload() {
    final now = widget.now?.call() ?? DateTime.now();
    _data = Future(
      () async => (
        await widget.repository.day(widget.date, now),
        await widget.repository.sessions(widget.date, now),
      ),
    );
    _data.ignore();
  }

  Future<void> _open(ExerciseSession session) async {
    final repo = widget.exercises;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => ExerciseDetailScreen(
          session: session,
          route: repo.route(session.id),
          analysis: (force) =>
              repo.movementAnalysis(session, recalculate: force),
          onDelete: () => repo.deleteFinished(session.id),
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _calendarAppBar(context, '하루의 움직임'),
    body: FutureBuilder<(CalendarDay, List<ExerciseSession>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(onRetry: () => setState(_reload));
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (day, sessions) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(AppSpace.page),
          children: [
            Text(
              '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpace.large),
            ActivitySurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stepLabel(day.steps)} 걸음',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpace.medium),
                  Text(
                    '${day.workouts}회 운동 · ${(day.meters / 1000).toStringAsFixed(1)} km',
                  ),
                  Text(
                    '${day.seconds ~/ 3600}시간 ${day.seconds % 3600 ~/ 60}분 운동',
                  ),
                  Text('새로운 지역 ${day.regions}곳 발견'),
                ],
              ),
            ),
            if (!day.hasActivity)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.large),
                child: Text('이 날에는 저장된 움직임 기록이 없어요.'),
              ),
            const ActivitySection(
              '운동 기록',
              subtitle: '자정을 넘긴 운동은 시작한 날에 모아 보여줘요.',
            ),
            for (final s in sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${s.type.label} · ${(s.distanceMeters / 1000).toStringAsFixed(1)} km',
                ),
                subtitle: Text(
                  '${s.startedAt.toLocal().hour.toString().padLeft(2, '0')}:${s.startedAt.toLocal().minute.toString().padLeft(2, '0')} · ${s.elapsedSeconds ~/ 60}분',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(s),
              ),
            if (day.milestones.isNotEmpty) ...[
              const ActivitySection(
                '성장의 기록',
                subtitle: '업적·타이틀은 보상이 기록된 날, 레벨은 프로필에서 확인한 날이에요.',
              ),
              for (final label in day.milestones)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.medium),
                  child: Text(label),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class ActivityTimeline extends StatefulWidget {
  const ActivityTimeline({
    super.key,
    required this.repository,
    required this.onDay,
    this.now,
  });
  final ActivityCalendarRepository repository;
  final Future<void> Function(String) onDay;
  final DateTime Function()? now;
  @override
  State<ActivityTimeline> createState() => _ActivityTimelineState();
}

class _ActivityTimelineState extends State<ActivityTimeline> {
  final _days = <CalendarDay>[];
  String? _before;
  bool _loading = false, _more = true;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.timeline(
        widget.now?.call() ?? DateTime.now(),
        before: _before,
      );
      if (!mounted) return;
      setState(() {
        _days.addAll(page.days);
        _before = page.nextBefore;
        _more = _before != null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(AppSpace.page),
    itemCount: _days.length + 1,
    itemBuilder: (context, index) {
      if (index == _days.length) {
        return Column(
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpace.large),
                child: CircularProgressIndicator(),
              ),
            if (_error != null) _LoadError(onRetry: _load),
            if (!_loading && _error == null && _more)
              OutlinedButton(onPressed: _load, child: const Text('이전 기록 더 보기')),
            if (!_loading && _error == null && _days.isEmpty && !_more)
              const Text('움직임이 쌓이면 이곳에서 돌아볼 수 있어요.'),
          ],
        );
      }
      final day = _days[index];
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.large),
        child: ActivitySurface(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(day.date.replaceAll('-', '.')),
            subtitle: Text(_daySummary(day)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await widget.onDay(day.date);
              if (!mounted) return;
              setState(() {
                _days.clear();
                _before = null;
                _more = true;
              });
              await _load();
            },
          ),
        ),
      );
    },
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('기록을 불러오지 못했어요.'),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}
