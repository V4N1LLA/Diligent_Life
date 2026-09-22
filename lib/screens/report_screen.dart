import 'package:flutter/material.dart';

import '../data/report_repository.dart';
import '../models/activity_report.dart';
import '../models/exercise_session.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import '../services/report_share.dart';
import 'exercise_screen.dart';
import 'portfolio_share_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.repository, this.now});
  final ReportRepository repository;
  final DateTime? now;
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportPeriod _period = ReportPeriod.month;
  late DateTime _anchor;
  late Future<ActivityReport> _data;
  DateTime get _now => widget.now ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _anchor = _now;
    _reload();
  }

  void _reload() {
    _data = widget.repository.load(_period, _anchor, _now);
    _data.ignore();
  }

  void _move(int delta) => setState(() {
    _anchor = _period.shift(_period.start(_anchor), delta);
    _reload();
  });
  Future<void> _open(ExerciseSession session) async {
    final repo = widget.repository.exercises;
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
    if (mounted) {
      widget.repository.invalidate();
      setState(_reload);
    }
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  String _speed(double? value) => value == null
      ? '데이터 부족'
      : '${value.toStringAsFixed(1)} km/h · ${(60 / value).toStringAsFixed(1)}분/km';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('활동 리포트'),
      actions: [
        IconButton(
          tooltip: '리포트 새로고침',
          onPressed: () {
            widget.repository.invalidate();
            setState(_reload);
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final period in ReportPeriod.values)
                ChoiceChip(
                  label: Text(period.label),
                  selected: _period == period,
                  onSelected: (_) => setState(() {
                    _period = period;
                    _anchor = _now;
                    _reload();
                  }),
                ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: '이전 리포트',
                onPressed: _anchor.year <= 1900 ? null : () => _move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _period == ReportPeriod.year
                      ? '${_anchor.year}년'
                      : _period == ReportPeriod.month
                      ? '${_anchor.year}년 ${_anchor.month}월'
                      : '${dateKey(_period.start(_anchor))} 주',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: '다음 리포트',
                onPressed: _period.start(_anchor).isBefore(_period.start(_now))
                    ? () => _move(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          FutureBuilder<ActivityReport>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('리포트를 불러오지 못했어요. 다시 시도'),
                );
              }
              final d = snapshot.data!;
              final kcalAvailable =
                  d.current.count > 0 &&
                  d.previous.count > 0 &&
                  d.current.calorieCount == d.current.count &&
                  d.previous.calorieCount == d.previous.count;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    d.insight,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(d.window.dates),
                  Text('비교: ${d.window.previousDates}'),
                  if (d.window.partial)
                    const Text(
                      '진행 중인 기간 · 이전 기간의 같은 경과 일수와 비교해요. 짧은 이전 기간은 마지막 날까지 포함해요.',
                    ),
                  _heading('이전 기간에서 이번 기간으로'),
                  _comparison(
                    '거리',
                    '${(d.previous.meters / 1000).toStringAsFixed(2)} → ${(d.current.meters / 1000).toStringAsFixed(2)} km',
                    d.delta(d.current.meters, d.previous.meters),
                  ),
                  _comparison(
                    '시간',
                    '${elapsedLabel(d.previous.seconds)} → ${elapsedLabel(d.current.seconds)}',
                    d.delta(
                      d.current.seconds.toDouble(),
                      d.previous.seconds.toDouble(),
                    ),
                  ),
                  _comparison(
                    '운동 횟수',
                    '${d.previous.count} → ${d.current.count}회',
                    d.delta(
                      d.current.count.toDouble(),
                      d.previous.count.toDouble(),
                    ),
                  ),
                  _comparison(
                    '예상 kcal',
                    '${d.previous.calories?.round() ?? '—'} → ${d.current.calories?.round() ?? '—'} kcal',
                    d.delta(
                      d.current.calories ?? 0,
                      d.previous.calories ?? 0,
                      available: kcalAvailable,
                    ),
                  ),
                  Text(
                    '완료 GPS 운동의 기록 거리·총 기록 시간 합계 · 수동 운동은 중복 합산하지 않아요. kcal는 정지를 포함한 총 시간 기준이며 몸무게가 있는 ${d.current.calorieCount}/${d.current.count}회만 합산해요. 누락이 있으면 kcal 증감률을 표시하지 않아요.',
                  ),
                  _heading('이동속도와 페이스'),
                  const Text(
                    '같은 운동 종류끼리 비교 · 유효 이동거리 ÷ 이동시간. 기간당 2회 이상, 각 100m·이동 1분 이상 기록이 필요해요.',
                  ),
                  if (d.speeds.isEmpty) const Text('데이터 부족'),
                  for (final s in d.speeds)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.type.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '이전 ${_speed(s.previous)}\n이번 ${_speed(s.current)}',
                          ),
                          Text(
                            '분석 가능 기록: 이전 ${s.previousCount}회 · 이번 ${s.currentCount}회',
                          ),
                          Text(
                            s.increasing
                                ? '최근 완료된 4주 평균 이동속도가 점진적으로 증가했습니다.'
                                : '4주 연속 상승 추세: ${s.weeks.any((v) => v == null) ? '데이터 부족' : '뚜렷하지 않아요'}',
                          ),
                          Text(
                            [
                              for (var i = 0; i < 4; i++)
                                '${dateKey(d.weekStarts[i])}: ${s.weeks[i]?.toStringAsFixed(1) ?? '—'}',
                            ].join(' · '),
                          ),
                        ],
                      ),
                    ),
                  _heading('몸무게와 운동량의 흐름'),
                  Text(
                    d.weightChange == null
                        ? '몸무게 변화: 데이터 부족 (측정일 2개 이상 필요)'
                        : '몸무게 ${d.weightChange! > 0 ? '+' : ''}${d.weightChange!.toStringAsFixed(1)} kg · ${d.weights.length}회 측정',
                  ),
                  const Text('같은 기간의 추세를 나란히 보여줘요. 운동이 몸무게 변화를 일으켰다는 뜻은 아니에요.'),
                  const SizedBox(height: 12),
                  // One aligned timeline; no dual axes or inferred measurements.
                  for (final b in d.buckets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${dateKey(b.start)} · ${(b.summary.meters / 1000).toStringAsFixed(2)} km · 평균 몸무게 ${b.meanWeight?.toStringAsFixed(1) ?? '—'} kg',
                          ),
                          LinearProgressIndicator(
                            value: d.current.meters <= 0
                                ? 0
                                : b.summary.meters / d.current.meters,
                            minHeight: 3,
                          ),
                        ],
                      ),
                    ),
                  _heading('자주 움직인 때'), Text(d.pattern),
                  _heading('자주 이용한 경로'),
                  const Text(
                    '약 100m 격자에서 70% 이상 겹치고 거리가 비슷한 경로를 묶은 추정이에요. 방향은 구분하지 않으며 정확한 경로 식별은 아니에요.',
                  ),
                  if (d.routes.isEmpty)
                    const Text('데이터 부족 · 비슷한 경로를 2회 이상 기록하면 요약해요.'),
                  for (var i = 0; i < d.routes.length; i++)
                    TextButton(
                      onPressed: () =>
                          _open(d.routes[i].representative.session),
                      child: Text(
                        '유사 경로 ${i + 1} · ${d.routes[i].entries.length}회 · 약 ${(d.routes[i].representative.movingMeters / 1000).toStringAsFixed(1)} km · 대표 운동 열기',
                      ),
                    ),
                  _heading('개인 최고와 이번 기간의 개선'),
                  const Text(
                    '선택 기간 마지막 날까지의 개인 최고 · 처음 남긴 기록과 GPS 오차 이내의 차이는 개선으로 세지 않아요.',
                  ),
                  if (d.records.isEmpty) const Text('개인 최고 기록: 데이터 부족'),
                  for (final r in d.records)
                    TextButton(
                      onPressed: () => _open(r.entry.session),
                      child: Text(
                        '${r.label} · ${r.formatted} · ${dateKey(r.entry.session.startedAt.toLocal())}',
                      ),
                    ),
                  if (d.improvements.isEmpty)
                    const Text('이번 기간에 확인된 개인 최고 갱신이 없어요.'),
                  for (final r in d.improvements)
                    Text(
                      '최근 개선 · ${r.label}: ${r.previous!.toStringAsFixed(1)} → ${r.formatted} (${dateKey(r.entry.session.startedAt.toLocal())})',
                    ),
                  _heading('이번 기간의 대표 기록'),
                  const Text(
                    '유효 이동거리가 가장 긴 운동을 선정해요. 분석이 없으면 기록 시간이 긴 운동을 선택해요.',
                  ),
                  if (d.representative == null)
                    const Text('데이터 부족')
                  else
                    TextButton(
                      onPressed: () => _open(d.representative!.session),
                      child: Text(
                        '${dateKey(d.representative!.session.startedAt.toLocal())} · ${d.representative!.session.type.label} · 운동 열기',
                      ),
                    ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PortfolioShareScreen.report(
                          title: '${d.window.title} · ${d.window.dates}',
                          image: () => reportShareImage(d),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('리포트 이미지 공유'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
  Widget _comparison(String label, String values, String delta) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · $delta', style: Theme.of(context).textTheme.titleMedium),
        Text(values),
      ],
    ),
  );
}
