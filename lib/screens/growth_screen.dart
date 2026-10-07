import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/growth_repository.dart';
import '../models/growth.dart';
import '../services/step_service.dart';
import '../services/achievement_share.dart';
import '../utils/dates.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_style.dart';
import 'portfolio_share_screen.dart';

class MovementHomeSummary extends StatefulWidget {
  const MovementHomeSummary({
    super.key,
    required this.repository,
    required this.visible,
    required this.revision,
    this.workout,
  });
  final Widget? workout;
  final GrowthRepository repository;
  final bool visible;
  final int revision;
  @override
  State<MovementHomeSummary> createState() => _MovementHomeSummaryState();
}

class _MovementHomeSummaryState extends State<MovementHomeSummary>
    with WidgetsBindingObserver {
  Timer? _timer;
  Future<GrowthSnapshot>? _data;
  AppLifecycleState? _state;
  bool _routeVisible = true;
  int _goal = 5000;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = WidgetsBinding.instance.lifecycleState;
    _load();
    _sync();
  }

  void _load() {
    _data = () async {
      _goal =
          (await SharedPreferences.getInstance()).getInt('stepGoal') ?? 5000;
      return widget.repository.refresh(DateTime.now());
    }();
    _data!.ignore();
  }

  void _sync() {
    _timer?.cancel();
    if (widget.visible &&
        _routeVisible &&
        (_state == null || _state == AppLifecycleState.resumed)) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(_load);
      });
    }
  }

  @override
  void didUpdateWidget(MovementHomeSummary old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || (!old.visible && widget.visible)) {
      _load();
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    _sync();
    if (state == AppLifecycleState.resumed) setState(_load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GrowthSnapshot>(
    future: _data,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot.hasError)
              TextButton(
                onPressed: () => setState(_load),
                child: const Text('걸음과 성장 다시 불러오기'),
              ),
            if (widget.workout != null) widget.workout!,
          ],
        );
      }
      final data = snapshot.data!;
      final today = data.days
          .where((d) => d.date == dateKey(DateTime.now()))
          .firstOrNull;
      final now = DateTime.now();
      final monday = dateKey(
        DateTime(now.year, now.month, now.day - now.weekday + 1),
      );
      final week = data.days
          .where((d) => d.date.compareTo(monday) >= 0)
          .fold<double>(0, (sum, d) => sum + d.meters);
      final daily = data.quests.where((q) => q.id.contains('.daily.'));
      final preview = [
        ...daily.where((q) => !q.complete),
        ...daily.where((q) => q.complete),
      ].take(2);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LevelProgress(data: data, onTap: () => _open(context)),
          const SizedBox(height: AppSpace.section),
          Semantics(
            button: true,
            label: '오늘 ${today?.steps ?? 0}걸음, 목표 $_goal걸음. 걸음과 나의 성장 열기',
            onTap: () => _open(context),
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppStyle.radius),
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.medium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      stepLabel(today?.steps ?? 0),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpace.small),
                    Text(
                      '오늘 걸음',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.large),
                    LinearProgressIndicator(
                      value: ((today?.steps ?? 0) / _goal).clamp(0, 1),
                    ),
                    const SizedBox(height: AppSpace.small),
                    Text(
                      '${stepLabel(today?.steps ?? 0)} / ${stepLabel(_goal)}걸음',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.workout != null) ...[
            const SizedBox(height: AppSpace.large),
            widget.workout!,
          ],
          const ActivitySection('오늘의 작은 도전', subtitle: '조금씩, 나의 속도로'),
          for (final quest in preview) GoalProgressView(goal: quest),
          TextButton(
            onPressed: () => _open(context),
            child: const Text('퀘스트와 나의 성장 모두 보기'),
          ),
          const ActivitySection('이번 주 움직임'),
          Text(
            '${(week / 1000).toStringAsFixed(1)} km',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpace.small),
          const Text('완료한 운동이 차곡차곡 쌓이고 있어요.'),
        ],
      );
    },
  );
  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GrowthScreen(repository: widget.repository),
      ),
    );
    if (mounted) setState(_load);
  }
}

class GrowthScreen extends StatefulWidget {
  const GrowthScreen({super.key, required this.repository, this.steps});
  final GrowthRepository repository;
  final StepService? steps;
  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen>
    with WidgetsBindingObserver {
  late Future<(GrowthSnapshot, StepStatus, List<Map<String, Object?>>)> _data;
  int _goal = 5000;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  AppLifecycleState? _lifecycle;
  bool _visible = true;
  StepService get _steps => widget.steps ?? StepService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _load();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (_visible &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed)) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && !_busy) setState(_load);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ModalRoute.of(context)?.isCurrent ?? true;
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncTimer();
    if (state == AppLifecycleState.resumed) setState(_load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _load() {
    _data = () async {
      final prefs = await SharedPreferences.getInstance();
      _goal = prefs.getInt('stepGoal') ?? 5000;
      await _steps.flush();
      return (
        await widget.repository.refresh(DateTime.now()),
        await _steps.status(),
        await widget.repository.database.query(
          'daily_steps',
          orderBy: 'date DESC',
        ),
      );
    }();
    _data.ignore();
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final status = await _steps.enable(value);
    if (mounted) {
      setState(() {
        _busy = false;
        _error = status.error;
        _load();
      });
    }
  }

  Future<void> _share(String headline, String detail) async {
    final brightness = Theme.of(context).brightness;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortfolioShareScreen.image(
          title: headline,
          image: () =>
              achievementShareImage(headline, detail, brightness: brightness),
          notice: '위치 정보 없이 나의 성취만 담아요.',
          fileName: 'diligent-life-achievement.png',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('나의 성장'),
      actions: [
        IconButton(
          tooltip: '새로고침',
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child:
          FutureBuilder<
            (GrowthSnapshot, StepStatus, List<Map<String, Object?>>)
          >(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('다시 불러오기'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (data, status, rows) = snapshot.data!;
              final now = DateTime.now();
              final today = dateKey(now);
              final day =
                  data.days.where((d) => d.date == today).firstOrNull ??
                  ActivityDay(today);
              final monday = dateKey(
                DateTime(now.year, now.month, now.day - now.weekday + 1),
              );
              final month = dateKey(DateTime(now.year, now.month, 1));
              int sum(String since) => data.days
                  .where((d) => d.date.compareTo(since) >= 0)
                  .fold(0, (sum, d) => sum + d.steps);
              final coverage = rows
                  .where((r) => r['date'] == today)
                  .firstOrNull?['coverage'];
              return ListView(
                padding: const EdgeInsets.all(AppSpace.page),
                children: [
                  Text(
                    '오늘 ${day.steps}걸음',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpace.large),
                  LinearProgressIndicator(
                    value: (day.steps / _goal).clamp(0, 1),
                    semanticsLabel: '오늘 걸음 목표 ${day.steps} / $_goal걸음',
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('나의 목표 $_goal걸음'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final value = await showDialog<int>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('걸음 목표'),
                          children: [
                            for (final goal in [3000, 5000, 8000, 10000])
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(context, goal),
                                child: Text('$goal걸음'),
                              ),
                          ],
                        ),
                      );
                      if (value != null) {
                        await (await SharedPreferences.getInstance()).setInt(
                          'stepGoal',
                          value,
                        );
                        if (mounted) setState(() => _goal = value);
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('일상 걸음 기록'),
                    subtitle: Text(status.message),
                    value: status.enabled,
                    onChanged: status.supported && !_busy ? _toggle : null,
                  ),
                  if (status.supported && !status.permission)
                    TextButton(
                      onPressed: () => _steps.openSettings(),
                      child: const Text('앱 권한 설정'),
                    ),
                  if (status.enabled && !status.running)
                    TextButton(
                      onPressed: _busy ? null : () => _toggle(true),
                      child: const Text('만보기 다시 시작'),
                    ),
                  if (_error != null) Text(_error!),
                  if (coverage != null && coverage != 'observed')
                    const Text('기록을 시작한 날·재부팅·자정 수신 공백은 하루 전체 걸음과 다를 수 있어요.'),
                  if ((rows
                                  .where((r) => r['date'] == today)
                                  .firstOrNull?['uncertainSteps']
                              as int? ??
                          0) >
                      0)
                    const Text('자정 경계에서 날짜를 확정할 수 없는 걸음은 일일 XP·퀘스트에서 제외해요.'),
                  const Text(
                    '최초 활성화 이후의 걸음을 기록해요. 권한 해제·강제 중지·제조사 절전으로 빠진 걸음은 만들지 않아요. 센서 반영은 잠시 늦을 수 있어요.',
                  ),
                  const SizedBox(height: 24),
                  Text('최근 7일', style: Theme.of(context).textTheme.titleLarge),
                  for (var i = 6; i >= 0; i--)
                    Builder(
                      builder: (context) {
                        final date = dateKey(
                          DateTime(now.year, now.month, now.day - i),
                        );
                        final steps =
                            rows
                                    .where((r) => r['date'] == date)
                                    .firstOrNull?['steps']
                                as int?;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(date),
                          trailing: Text(steps == null ? '기록 없음' : '$steps걸음'),
                        );
                      },
                    ),
                  Text('이번 주 ${sum(monday)}걸음 · 이번 달 ${sum(month)}걸음'),
                  const SizedBox(height: 32),
                  LevelProgress(data: data),
                  TextButton.icon(
                    onPressed: () => _share(
                      'Lv ${data.level}',
                      '${data.title}\n누적 ${data.xp} XP',
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('나의 성장 카드'),
                  ),
                  const Text(
                    '걸음·GPS 운동 거리·시간에 하루 상한이 있어요. 체중·칼로리·직접 입력에는 XP를 주지 않아요. 완료 보상은 한 번만 받아요.',
                  ),
                  const SizedBox(height: 24),
                  const ActivitySection(
                    '가볍게 도전',
                    subtitle: '완료한 보상은 자동으로 쌓여요.',
                  ),
                  const Text('오늘의 퀘스트'),
                  for (final q in data.quests.where(
                    (q) => q.id.contains('.daily.'),
                  ))
                    _goalTile(q),
                  const SizedBox(height: AppSpace.large),
                  const Text('이번 주 퀘스트'),
                  for (final q in data.quests.where(
                    (q) => q.id.contains('.weekly.'),
                  ))
                    _goalTile(q),
                  const SizedBox(height: 24),
                  Text(
                    '나의 업적과 타이틀',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final a in data.achievements)
                    _goalTile(a, achievement: true),
                  const ActivitySection('나의 타이틀', subtitle: '지금의 나를 나타내는 한마디'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('타이틀 없이 지내기'),
                    subtitle: data.titleId == null ? const Text('장착 중') : null,
                    onTap: () => _equip(null, data),
                  ),
                  for (final id in data.unlockedTitles)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(titles[id]!),
                      subtitle: data.titleId == id ? const Text('장착 중') : null,
                      trailing: Icon(
                        data.titleId == id
                            ? Icons.check_circle
                            : Icons.person_outline,
                      ),
                      onTap: () => _equip(id, data),
                    ),
                ],
              );
            },
          ),
    ),
  );
  Widget _goalTile(GoalProgress goal, {bool achievement = false}) =>
      GoalProgressView(
        goal: goal,
        achievement: achievement,
        onShare: () => _share(goal.label, '완료 · ${goal.reward} XP'),
      );
  Future<void> _equip(String? id, GrowthSnapshot data) async {
    await widget.repository.equip(id, data);
    if (mounted) setState(_load);
  }
}
