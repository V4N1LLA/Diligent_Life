import 'package:flutter/material.dart';

import '../data/exercise_repository.dart';
import '../models/exercise_session.dart';
import '../utils/portfolio_analysis.dart';
import '../widgets/exercise_route.dart';
import '../data/exploration_repository.dart';
import '../data/growth_repository.dart';
import '../models/exploration.dart';
import '../services/exploration_share.dart';
import '../theme/app_theme.dart';
import 'portfolio_share_screen.dart';

class AllTimeMapScreen extends StatefulWidget {
  const AllTimeMapScreen({
    super.key,
    required this.repository,
    this.highlightSessionId,
  });
  final ExerciseRepository repository;
  final int? highlightSessionId;
  @override
  State<AllTimeMapScreen> createState() => _AllTimeMapScreenState();
}

class _AllTimeMapScreenState extends State<AllTimeMapScreen> {
  final _points = <RoutePoint>[];
  int _loaded = 0, _total = 0;
  bool _busy = true, _failed = false;
  bool _importing = false;
  int _processed = 0;
  ExplorationSummary _explored = const ExplorationSummary([], 0, {});
  String? _notice;
  late final _exploration = ExplorationRepository(widget.repository);
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
      _explored = await _exploration.summary(
        now,
        sessionId: widget.highlightSessionId,
      );
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

  Future<void> _historical() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지난 운동의 탐험도 추가할까요?'),
        content: const Text(
          '원본 GPS가 있는 완료 운동만 확인해요. 기록을 바꾸지 않으며 이미 발견한 지역은 중복 추가하지 않아요. 발견 날짜와 보상은 운동 종료일 기준이에요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('추가하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (await widget.repository.active() != null) {
      if (mounted) setState(() => _notice = '운동을 종료한 뒤 지난 탐험을 추가해 주세요.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _importing = true;
      _processed = 0;
      _notice = null;
    });
    int added = 0;
    try {
      final now = DateTime.now();
      final sessions = await widget.repository.finishedBetween(before: now);
      // Historical attribution is oldest-first, independent of list UI order.
      sessions.sort(
        (a, b) =>
            (a.endedAt ?? a.updatedAt).compareTo(b.endedAt ?? b.updatedAt),
      );
      for (final session in sessions) {
        if (!mounted) return;
        added += (await _exploration.discover(session)).length;
        if (mounted) setState(() => _processed++);
        await Future<void>.delayed(Duration.zero);
      }
      await GrowthRepository(widget.repository.database).refresh(now);
      final summary = await _exploration.summary(
        now,
        sessionId: widget.highlightSessionId,
      );
      if (mounted) {
        setState(() {
          _explored = summary;
          _notice = '새로운 지역 $added곳을 발견했어요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = '확인을 잠시 멈췄어요. 완료한 지역은 보존되며 다시 시도할 수 있어요.');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _share() async {
    final data = _explored, brightness = Theme.of(context).brightness;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortfolioShareScreen.image(
          title: '나의 탐험',
          image: () => explorationShareImage(
            total: data.cells.length,
            discovered: widget.highlightSessionId == null
                ? data.monthCount
                : data.newIds.length,
            workout: widget.highlightSessionId != null,
            brightness: brightness,
          ),
          notice: '발견 개수만 담아요. 지도와 위치 정보는 포함하지 않아요.',
          fileName: 'diligent-life-exploration.png',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_importing,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('나의 탐험 지도'),
        actions: [
          IconButton(
            tooltip: '탐험 카드',
            onPressed: _busy || _importing || _failed ? null : _share,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_busy && !_failed)
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.large),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${_explored.cells.length}개 지역 탐험',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text('이번 달 새 지역 ${_explored.monthCount}곳'),
                          if (widget.highlightSessionId != null)
                            Text(
                              '이번 운동 새 지역 ${_explored.newIds.length}곳 · 보라색으로 표시해요.',
                            ),
                          const Text('초록은 방문 영역 · 축소하면 발견 위치를 점으로 묶어요.'),
                          if (_notice != null) Text(_notice!),
                          TextButton.icon(
                            onPressed: _importing ? null : _historical,
                            icon: const Icon(Icons.history),
                            label: Text(
                              _importing
                                  ? '지난 운동 확인 중 · $_processed개'
                                  : '지난 운동의 탐험 추가',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _busy
                    ? '지나온 길을 모으고 있어요 · $_loaded/$_total'
                    : _failed
                    ? '지나온 길을 불러오지 못했어요.'
                    : '$_total개 운동으로 쌓은 발자취',
              ),
            ),
            if (_busy || _importing) const LinearProgressIndicator(),
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
                  : _points.isEmpty && _explored.cells.isEmpty
                  ? const Center(child: Text('운동을 기록하면 지나온 길이 여기에 모여요.'))
                  : LayoutBuilder(
                      builder: (context, size) => ExerciseRoute(
                        points: _points,
                        overview: true,
                        exploredCells: _explored.cells,
                        newCellIds: _explored.newIds,
                        height: size.maxHeight,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
