import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../data/record_repository.dart';
import '../data/exercise_repository.dart';
import '../data/portfolio_repository.dart';
import '../data/report_repository.dart';
import '../models/daily_record.dart';
import '../models/exercise_session.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import '../widgets/exercise_route.dart';
import 'exercise_screen.dart';
import 'all_time_map_screen.dart';
import 'portfolio_share_screen.dart';
import 'report_screen.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({
    super.key,
    required this.repository,
    required this.revision,
    this.exercises,
  });
  final RecordRepository repository;
  final ExerciseRepository? exercises;
  final int revision;
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  PortfolioPeriod _period = PortfolioPeriod.month;
  DateTime _anchor = DateTime.now();
  late PortfolioRepository _repository;
  late Future<PortfolioData> _data;
  @override
  void initState() {
    super.initState();
    _repository = PortfolioRepository(widget.repository, widget.exercises);
    _reload();
  }

  @override
  void didUpdateWidget(TrendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.exercises != widget.exercises) {
      _repository = PortfolioRepository(widget.repository, widget.exercises);
      _reload();
    } else if (oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    _data = _repository.load(_period, DateTime.now(), anchor: _anchor);
    // A synchronous storage failure may arrive before the next frame attaches
    // FutureBuilder. Handle it now; FutureBuilder still displays its error.
    _data.ignore();
  }

  Future<void> _open(ExerciseSession session) async {
    final repository = widget.exercises;
    if (repository == null) return;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          session: session,
          route: repository.route(session.id),
          analysis: (force) =>
              repository.movementAnalysis(session, recalculate: force),
          onDelete: () => repository.deleteFinished(session.id),
        ),
      ),
    );
    if (mounted && deleted == true) setState(_reload);
  }

  String get _periodTitle => _period == PortfolioPeriod.month
      ? '${_anchor.year}년 ${_anchor.month}월'
      : '${_anchor.year}년';
  bool get _canNext {
    final now = DateTime.now();
    return _period == PortfolioPeriod.month
        ? DateTime(
            _anchor.year,
            _anchor.month,
          ).isBefore(DateTime(now.year, now.month))
        : _anchor.year < now.year;
  }

  void _movePeriod(int delta) => setState(() {
    _anchor = _period == PortfolioPeriod.month
        ? DateTime(_anchor.year, _anchor.month + delta)
        : DateTime(_anchor.year + delta, _anchor.month);
    _reload();
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.page,
      AppSpace.medium,
      AppSpace.page,
      AppSpace.section,
    ),
    children: [
      Text('나의 포트폴리오', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('지금까지의 움직임, 그리고 나의 변화.'),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final period in PortfolioPeriod.values)
            ChoiceChip(
              label: Text(period.label),
              selected: _period == period,
              onSelected: (_) => setState(() {
                _period = period;
                _anchor = DateTime.now();
                _reload();
              }),
            ),
        ],
      ),
      if (_period == PortfolioPeriod.month || _period == PortfolioPeriod.year)
        Row(
          children: [
            IconButton(
              tooltip: '이전 기간',
              onPressed: _anchor.year <= 1900 ? null : () => _movePeriod(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: Text(_periodTitle, textAlign: TextAlign.center)),
            IconButton(
              tooltip: '다음 기간',
              onPressed: _canNext ? () => _movePeriod(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      const SizedBox(height: 28),
      FutureBuilder<PortfolioData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                const Text('포트폴리오를 불러오지 못했어요.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('다시 시도'),
                ),
              ],
            );
          }
          final data = snapshot.data!;
          final summary = data.summary;
          final change = data.weightChange;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '함께 쌓인 기록 거리',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${(summary.meters / 1000).toStringAsFixed(2)} km',
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 20,
                children: [
                  _Metric('운동 횟수', '${summary.count}회'),
                  _Metric('총 기록 시간', elapsedLabel(summary.seconds)),
                  _Metric(
                    '예상 칼로리 · 총 시간 기준',
                    summary.calories == null
                        ? '— kcal'
                        : '약 ${summary.calories!.round()} kcal',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '완료한 GPS 운동 기준 · 수동 입력 운동은 합산하지 않아요.',
                style: TextStyle(fontSize: 12),
              ),
              if (summary.calorieCount < summary.count)
                Text(
                  summary.calorieCount == 0
                      ? '몸무게가 저장된 운동부터 예상 kcal를 계산해요.'
                      : '예상 kcal는 몸무게가 있는 ${summary.calorieCount}개 운동의 합계예요.',
                  style: const TextStyle(fontSize: 12),
                ),
              if (summary.count == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text('이 기간에 완료한 GPS 운동이 없어요. 오늘 화면에서 첫 경로를 남겨보세요.'),
                ),
              if (summary.count == 0 && data.weights.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('아직 이 기간의 기록이 없어요.'),
                ),
              const _Section('월별 움직임'),
              const Text(
                '선택한 기간에 포함된 운동만 합산해요.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              _MonthlySummary(key: ValueKey(_period), months: data.months),
              const _Section('몸무게의 변화'),
              if (change != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '기간 내 변화 ${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg · ${data.weights.length}회 측정',
                  ),
                ),
              _Trend(
                title: '몸무게',
                unit: 'kg',
                records: data.weights,
                value: (r) => r.weightKg!,
              ),
              const Text(
                '실제 측정한 값만 표시해요. 측정하지 않은 날은 선을 잇지 않아요.',
                style: TextStyle(fontSize: 12),
              ),
              const _Section('지나온 모든 길'),
              if (widget.exercises != null)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AllTimeMapScreen(repository: widget.exercises!),
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('All-time Map · 지나온 모든 길'),
                ),
              const Text('이 기간의 대표 경로'),
              if (data.representative case final session?) ...[
                Text(
                  '${dateKey(session.startedAt.toLocal())} · ${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
                const SizedBox(height: 12),
                ExerciseRoute(
                  key: ValueKey(session.id),
                  points: data.route,
                  overview: true,
                  height: 300,
                ),
                TextButton(
                  onPressed: () => _open(session),
                  child: const Text('이 운동 자세히 보기'),
                ),
              ] else
                const Text('지도에 표시할 이동 경로가 아직 없어요.'),
              const _Section('나를 보여주는 기록'),
              if (data.longest case final session?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('가장 멀리 간 운동'),
                  subtitle: Text(
                    '${(session.distanceMeters / 1000).toStringAsFixed(2)} km · ${elapsedLabel(session.elapsedSeconds)}\n${dateKey(session.startedAt.toLocal())} · ${session.type.label}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(session),
                )
              else
                const Text('운동을 마치면 나만의 대표 기록이 여기에 남아요.'),
              if (data.longestTime case final session?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('가장 오래 기록한 운동'),
                  subtitle: Text(
                    '${elapsedLabel(session.elapsedSeconds)} · ${dateKey(session.startedAt.toLocal())}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(session),
                ),
              if (data.bestAverage case final session?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('최고 평균속도 · 페이스'),
                  subtitle: Text(
                    '${averageKmh(session)!.toStringAsFixed(1)} km/h · ${paceLabel(session.paceSeconds)}\n${dateKey(session.startedAt.toLocal())} · ${session.type.label}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(session),
                ),
              if (data.fastest case final speed?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('가장 빠른 이동 구간'),
                  subtitle: Text(
                    '${speed.kmh.toStringAsFixed(1)} km/h · ${paceLabel(speed.paceSeconds)}\n${dateKey(speed.points.first.timestamp.toLocal())} · ${_time(speed.points.first.timestamp)}–${_time(speed.points.last.timestamp)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(data.fastestSession!),
                )
              else if (summary.count > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('속도를 비교할 연속 이동 구간이 아직 없어요.'),
                ),
              const Text(
                '최고속도는 센서와 좌표가 일치하는 구간만 비교해요. 기록 시간에는 정지가 포함돼요.',
                style: TextStyle(fontSize: 12),
              ),
              const _Section('최근 운동'),
              if (data.recent.isEmpty) const Text('이 기간에 완료한 운동이 아직 없어요.'),
              for (final session in data.recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${dateKey(session.startedAt.toLocal())} · ${session.type.label}',
                  ),
                  subtitle: Text(
                    '${(session.distanceMeters / 1000).toStringAsFixed(2)} km · ${elapsedLabel(session.elapsedSeconds)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(session),
                ),
              const SizedBox(height: 12),
              const _Section('기간 리포트'),
              if (widget.exercises != null)
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportScreen(
                          repository: ReportRepository(
                            widget.repository,
                            widget.exercises!,
                          ),
                        ),
                      ),
                    );
                    if (mounted) setState(_reload);
                  },
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('활동 리포트 · 이번 기간의 변화'),
                ),
              if (_period == PortfolioPeriod.month ||
                  _period == PortfolioPeriod.year)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PortfolioShareScreen(
                          data: data,
                          title: _periodTitle,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('이 기간 이미지로 공유'),
                  ),
                ),
              const Text(
                'GPS 거리·속도와 MET 칼로리는 추정치예요. 지도 로딩에는 인터넷 연결이 필요해요.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    ],
  );
}

String _time(DateTime value) {
  final t = value.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.small),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class _MonthlySummary extends StatefulWidget {
  const _MonthlySummary({super.key, required this.months});
  final List<PortfolioMonth> months;
  @override
  State<_MonthlySummary> createState() => _MonthlySummaryState();
}

class _MonthlySummaryState extends State<_MonthlySummary> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final maxDistance = widget.months.fold<double>(
      1,
      (max, m) => m.summary.meters > max ? m.summary.meters : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final month in widget.months.take(_all ? widget.months.length : 6))
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${month.month.year}.${month.month.month.toString().padLeft(2, '0')} · ${month.summary.count}회 · ${(month.summary.meters / 1000).toStringAsFixed(2)} km',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${elapsedLabel(month.summary.seconds)} · ${month.summary.calories == null ? '— kcal' : '약 ${month.summary.calories!.round()} kcal'}${month.summary.calorieCount > 0 && month.summary.calorieCount < month.summary.count ? ' (일부 기록)' : ''}',
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: month.summary.meters / maxDistance,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  semanticsLabel: '${month.month.month}월 운동 거리',
                ),
              ],
            ),
          ),
        if (widget.months.length > 6)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? '최근 6개월만 보기' : '모든 월 보기'),
          ),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.title,
    required this.unit,
    required this.records,
    required this.value,
  });
  final String title, unit;
  final List<DailyRecord> records;
  final double Function(DailyRecord) value;
  // UTC calendar days prevent DST from distorting distances on the date axis.
  double _x(DailyRecord r) =>
      DateTime.parse('${r.date}T00:00:00Z').millisecondsSinceEpoch /
      Duration.millisecondsPerDay;
  String _label(double x) {
    final day = DateTime.fromMillisecondsSinceEpoch(
      (x * Duration.millisecondsPerDay).round(),
      isUtc: true,
    );
    return dateKey(day);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Text('$title · 아직 측정한 기록이 없어요.'),
      );
    }
    final spots = records.map((r) => FlSpot(_x(r), value(r))).toList();
    final minValue = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxValue = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // At least 2 kg of vertical context avoids magnifying tiny weight changes.
    final padding = (maxValue - minValue).abs() * .2 + 1;
    final minY = unit == 'kg' && minValue > padding ? minValue - padding : 0.0;
    final maxY = maxValue + padding;
    final yInterval = unit == 'kg'
        ? ((maxY - minY) / 3 * 10).ceilToDouble() / 10
        : ((maxY - minY) / 3)
              .ceilToDouble()
              .clamp(1.0, double.infinity)
              .toDouble();
    final segments = <FlSpot>[];
    for (var i = 0; i < spots.length; i++) {
      if (i > 0 && spots[i].x - spots[i - 1].x > 1) {
        segments.add(FlSpot.nullSpot);
      }
      segments.add(spots[i]);
    }
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '${unit == 'kcal' ? '약 ' : ''}${value(records.last).toStringAsFixed(unit == 'kg' ? 1 : 0)} $unit',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            '마지막 기록 · ${records.last.date}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Semantics(
            label:
                '$title 그래프. ${records.length}개 기록. 첫 기록 ${value(records.first).toStringAsFixed(1)} $unit, 마지막 기록 ${value(records.last).toStringAsFixed(1)} $unit.',
            child: SizedBox(
              height: 180 * scale.clamp(1, 2),
              child: LineChart(
                LineChartData(
                  minX: spots.first.x - (spots.length == 1 ? 1 : 0),
                  maxX: spots.last.x + (spots.length == 1 ? 1 : 0),
                  minY: minY,
                  maxY: maxY,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48 * scale,
                        interval: yInterval,
                        minIncluded: false,
                        maxIncluded: false,
                        getTitlesWidget: (v, meta) => Text(
                          v.toStringAsFixed(unit == 'kg' ? 1 : 0),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => touched
                          .map(
                            (s) => LineTooltipItem(
                              '${_label(s.x)}\n${unit == 'kcal' ? '약 ' : ''}${s.y.toStringAsFixed(1)} $unit',
                              const TextStyle(color: Colors.white),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: segments,
                      color: color,
                      barWidth: 2.5,
                      isCurved: false,
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 48 * scale),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    records.first.date,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (records.length > 1)
                  Expanded(
                    child: Text(
                      records.last.date,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
