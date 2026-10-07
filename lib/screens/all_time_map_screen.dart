import 'package:flutter/material.dart';

import '../data/exercise_repository.dart';
import '../models/exercise_session.dart';
import '../utils/portfolio_analysis.dart';
import '../widgets/exercise_route.dart';

class AllTimeMapScreen extends StatefulWidget {
  const AllTimeMapScreen({super.key, required this.repository});
  final ExerciseRepository repository;
  @override
  State<AllTimeMapScreen> createState() => _AllTimeMapScreenState();
}

class _AllTimeMapScreenState extends State<AllTimeMapScreen> {
  final _points = <RoutePoint>[];
  int _loaded = 0, _total = 0;
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
      _points.clear();
      _loaded = 0;
    });
    try {
      final now = DateTime.now();
      final sessions = await widget.repository.finishedBetween(
        before: DateTime(now.year, now.month, now.day + 1),
      );
      _total = sessions.length;
      int segment = 0;
      for (final session in sessions) {
        if (!mounted) return;
        final analysis = await widget.repository.portfolioAnalysis(session);
        // Every session/gap gets a distinct polyline; there are no invented connections.
        int? previous;
        for (final point in sampleOverviewRoute(
          analysis.route,
          (50000 / sessions.length).floor().clamp(2, 600),
        )) {
          if (previous != point.segment) segment++;
          previous = point.segment;
          _points.add(point.inSegment(segment));
        }
        if (!mounted) return;
        setState(() => _loaded++);
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('All-time Map')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _busy
                  ? '지나온 길을 모으고 있어요 · $_loaded/$_total'
                  : _failed
                  ? '지나온 길을 불러오지 못했어요.'
                  : '$_total개 운동의 발자취 · 경로는 운동별로 구분해요.\n빠른 표시를 위해 경로를 간략히 그리며 원본은 그대로 보관해요.',
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_failed)
            TextButton(
              onPressed: _load,
              child: const Text('지도를 불러오지 못했어요. 다시 시도'),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? const SizedBox.shrink()
                : _points.isEmpty
                ? const Center(child: Text('운동을 기록하면 지나온 길이 여기에 모여요.'))
                : LayoutBuilder(
                    builder: (context, size) => ExerciseRoute(
                      points: _points,
                      overview: true,
                      height: size.maxHeight,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
