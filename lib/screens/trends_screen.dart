import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/record_repository.dart';
import '../models/daily_record.dart';
import '../utils/dates.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({
    super.key,
    required this.repository,
    required this.revision,
  });
  final RecordRepository repository;
  final int revision;
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  int _days = 7;
  late Future<List<DailyRecord>> _records;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(TrendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _reload();
  }

  void _reload() {
    final today = dayOnly(DateTime.now());
    _records = widget.repository.list(
      until: dateKey(today),
      since: _days == 0
          ? null
          : dateKey(DateTime(today.year, today.month, today.day - _days + 1)),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    children: [
      Text('나의 변화', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('기록이 쌓이면 흐름이 보여요.'),
      const SizedBox(height: 8),
      const Text('기록이 없는 날은 선을 잇지 않아요. 0분은 운동 없이 저장한 날이에요.'),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (days, label) in [(7, '최근 7일'), (30, '최근 30일'), (0, '전체')])
            ChoiceChip(
              label: Text(label),
              selected: _days == days,
              onSelected: (_) => setState(() {
                _days = days;
                _reload();
              }),
            ),
        ],
      ),
      const SizedBox(height: 32),
      FutureBuilder<List<DailyRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                const Text('기록을 불러오지 못했어요.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('다시 시도'),
                ),
              ],
            );
          }
          final records = snapshot.data!;
          if (records.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Column(
                children: [
                  Icon(Icons.show_chart, size: 40),
                  SizedBox(height: 16),
                  Text('아직 이 기간의 기록이 없어요.'),
                  SizedBox(height: 8),
                  Text('오늘 화면에서 첫 기록을 남겨보세요.'),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Trend(
                title: '몸무게',
                unit: 'kg',
                records: records.where((r) => r.weightKg != null).toList(),
                value: (r) => r.weightKg!,
              ),
              _Trend(
                title: '운동 시간',
                unit: '분',
                records: records,
                value: (r) => r.durationMinutes.toDouble(),
              ),
              _Trend(
                title: '예상 소모 칼로리',
                unit: 'kcal',
                records: records,
                value: (r) => r.estimatedCalories,
              ),
            ],
          );
        },
      ),
    ],
  );
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
