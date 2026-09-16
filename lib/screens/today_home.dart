import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/record_repository.dart';
import '../models/daily_record.dart';
import '../models/exercise_session.dart';
import '../models/exercise_type.dart';
import '../services/exercise_recorder.dart';
import '../theme/app_theme.dart';
import '../utils/calories.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import 'exercise_screen.dart';
import 'today_screen.dart';

class TodayHome extends StatefulWidget {
  const TodayHome({
    super.key,
    required this.repository,
    required this.onSaved,
    required this.openExercise,
    required this.revision,
    this.recorder,
  });
  final RecordRepository repository;
  final ExerciseRecorder? recorder;
  final VoidCallback onSaved, openExercise;
  final int revision;
  @override
  State<TodayHome> createState() => _TodayHomeState();
}

class _TodayHomeState extends State<TodayHome> {
  late Future<(double?, List<ExerciseSession>, DailyRecord?)> _data;
  void _load() {
    _data = () async {
      final today = dateKey(DateTime.now());
      return (
        await widget.repository.latestWeight(today),
        await widget.recorder?.repository.history() ?? <ExerciseSession>[],
        await widget.repository.forDate(today),
      );
    }();
    _data.ignore();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TodayHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load();
  }

  Future<void> _weight() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _WeightSheet(repository: widget.repository),
    );
    if (saved == true && mounted) {
      widget.onSaved();
      setState(_load);
    }
  }

  Future<void> _manual() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('직접 기록')),
          body: SafeArea(
            child: TodayScreen(
              repository: widget.repository,
              onSaved: widget.onSaved,
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(_load);
  }

  Future<void> _detail(ExerciseSession session) async {
    final repo = widget.recorder!.repository;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseDetailScreen(
          session: session,
          route: repo.route(session.id),
          analysis: (force) =>
              repo.movementAnalysis(session, recalculate: force),
          onDelete: () => repo.deleteFinished(session.id),
        ),
      ),
    );
    if (mounted) {
      widget.onSaved();
      setState(_load);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpace.page),
    children: [
      Text('오늘의 움직임', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: AppSpace.small),
      Text(
        dateKey(DateTime.now()),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpace.section),
      if (widget.recorder case final recorder?)
        ListenableBuilder(
          listenable: recorder,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recorder.active) ...[
                Text(
                  '${recorder.live!.type.label} · ${recorder.recording ? '기록 중' : '일시정지'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${elapsedLabel(recorder.elapsedSeconds)} · ${(recorder.live!.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
                if (recorder.issue != null) Text(recorder.issue!.message),
                const SizedBox(height: AppSpace.medium),
              ],
              FilledButton.icon(
                onPressed: widget.openExercise,
                icon: Icon(
                  recorder.active ? Icons.near_me_outlined : Icons.play_arrow,
                ),
                label: Text(recorder.active ? '운동으로 돌아가기' : '운동 시작'),
              ),
              const SizedBox(height: AppSpace.small),
              Text(
                recorder.active
                    ? '다른 화면을 보거나 앱을 나가도 기록은 유지돼요.'
                    : '익숙한 운동으로, 가볍게 시작하세요.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      const SizedBox(height: AppSpace.section),
      FutureBuilder<(double?, List<ExerciseSession>, DailyRecord?)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(_load),
              child: const Text('오늘 기록 다시 불러오기'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (weight, history, manual) = snapshot.data!;
          final today = history
              .where(
                (s) =>
                    dateKey(s.startedAt.toLocal()) == dateKey(DateTime.now()),
              )
              .toList();
          final summary = MovementSummary.fromSessions(today);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('몸무게'),
                subtitle: Text(
                  weight == null
                      ? '오늘의 몸무게를 남겨보세요.'
                      : '최근 ${weight.toStringAsFixed(1)} kg',
                ),
                trailing: const Icon(Icons.add),
                onTap: _weight,
              ),
              const Divider(),
              const SizedBox(height: AppSpace.large),
              Text('오늘 활동', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.small),
              Text(
                summary.count == 0
                    ? '아직 완료한 운동이 없어요.'
                    : '${(summary.meters / 1000).toStringAsFixed(2)} km · ${elapsedLabel(summary.seconds)} · ${summary.count}회',
              ),
              if (manual != null && manual.durationMinutes > 0)
                Text(
                  '직접 기록 · ${manual.exerciseType.label} ${manual.durationMinutes}분',
                ),
              const SizedBox(height: AppSpace.section),
              Text('최근 기록', style: Theme.of(context).textTheme.titleLarge),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.medium),
                  child: Text('운동을 마치면 경로와 기록이 여기에 남아요.'),
                ),
              for (final s in history.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${dateKey(s.startedAt.toLocal())} · ${s.type.label}',
                  ),
                  subtitle: Text(
                    '${(s.distanceMeters / 1000).toStringAsFixed(2)} km · ${elapsedLabel(s.elapsedSeconds)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _detail(s),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: AppSpace.large),
      TextButton.icon(
        onPressed: _manual,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('지난 기록 · 운동 직접 입력'),
      ),
    ],
  );
}

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({required this.repository});
  final RecordRepository repository;
  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _date = dateKey(DateTime.now());
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final weight = double.parse(_controller.text.trim().replaceAll(',', '.'));
      final old = await widget.repository.forDate(_date);
      final now = DateTime.now().toUtc().toIso8601String();
      final type = old?.exerciseType ?? ExerciseType.lightWalk;
      final minutes = old?.durationMinutes ?? 0;
      await widget.repository.save(
        DailyRecord(
          date: _date,
          weightKg: weight,
          exerciseType: type,
          durationMinutes: minutes,
          distanceKm: old?.distanceKm,
          estimatedCalories: estimateCalories(
            met: type.met,
            weightKg: weight,
            durationMinutes: minutes,
          ),
          createdAt: old?.createdAt ?? now,
          updatedAt: now,
        ),
      );
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '저장하지 못했어요. 입력을 유지했으니 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        0,
        AppSpace.page,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.page,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('오늘 몸무게', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.large),
            TextFormField(
              key: const ValueKey('quick-weight'),
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: '몸무게',
                suffixText: 'kg',
                errorMaxLines: 3,
              ),
              validator: (value) {
                final n = double.tryParse(value!.trim().replaceAll(',', '.'));
                return n == null || !n.isFinite || n <= 0 || n > 500
                    ? '0 초과 500 이하의 몸무게를 입력해 주세요.'
                    : null;
              },
            ),
            if (_error != null) Text(_error!),
            const SizedBox(height: AppSpace.large),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '저장 중…' : '몸무게 저장'),
            ),
          ],
        ),
      ),
    ),
  );
}
