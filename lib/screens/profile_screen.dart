import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/character_repository.dart';
import '../data/growth_repository.dart';
import '../models/character.dart';
import '../models/growth.dart';
import '../services/profile_share.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_style.dart';
import '../widgets/profile_avatar.dart';
import 'portfolio_share_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.repository});
  final CharacterRepository repository;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  late Future<CharacterSnapshot> _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _load() {
    _data = widget.repository.refresh();
    _data.ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) setState(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        HapticFeedback.selectionClick();
        setState(_load);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(CharacterSnapshot data) async {
    final brightness = Theme.of(context).brightness;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortfolioShareScreen.image(
          title: '나의 프로필 카드',
          image: () => profileShareImage(data, brightness),
          notice: '아바타와 대표 활동만 담아요. 위치·체중은 포함하지 않아요.',
          fileName: 'diligent-life-profile.png',
        ),
      ),
    );
  }

  Future<void> _inbox(CharacterSnapshot data) async {
    // The inbox's confirmation button marks only its displayed page as seen.
    // No automatic modal or notification on launch, including historical users.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _RewardInbox(repository: widget.repository, rewards: data.rewards),
      ),
    );
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('나의 프로필')),
    body: SafeArea(
      child: FutureBuilder<CharacterSnapshot>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(_load),
                child: const Text('프로필 다시 불러오기'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final growth = data.growth;
          return ListView(
            padding: const EdgeInsets.all(AppSpace.page),
            children: [
              Center(child: ProfileAvatar(data: data)),
              const SizedBox(height: AppSpace.large),
              Text(
                '조금씩, 나다운 모습으로',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.large),
              LevelProgress(data: growth),
              const ActivitySection('쌓아 온 움직임'),
              Wrap(
                spacing: AppSpace.large,
                runSpacing: AppSpace.large,
                children: [
                  _metric('누적 걸음', stepLabel(data.steps)),
                  _metric(
                    '운동 거리',
                    '${(data.meters / 1000).toStringAsFixed(1)} km',
                  ),
                  _metric('탐험 지역', '${data.regions}곳'),
                  _metric('달성 업적', '${data.achievements}개'),
                ],
              ),
              const SizedBox(height: AppSpace.large),
              OutlinedButton.icon(
                onPressed: () => _share(data),
                icon: const Icon(Icons.ios_share),
                label: const Text('프로필 카드 만들기'),
              ),
              const ActivitySection('나의 보상', subtitle: '성장의 순간을 여기 모았어요.'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(data.unread > 0 ? '새 보상 ${data.unread}개' : '보상함'),
                subtitle: const Text('레벨·업적·새 외형 한 번에 보기'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _inbox(data),
              ),
              const ActivitySection('나답게 꾸미기', subtitle: '활동하며 얻은 외형을 골라 보세요.'),
              for (final slot in CosmeticSlot.values) ...[
                Text(switch (slot) {
                  CosmeticSlot.accent => '포인트 색',
                  CosmeticSlot.background => '배경',
                  CosmeticSlot.frame => '프레임',
                  CosmeticSlot.emblem => '엠블럼',
                }, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpace.small),
                for (final c in cosmetics.where((c) => c.slot == slot))
                  _option(
                    c.name,
                    data.unlocked.contains(c.id),
                    data.selection(slot) == c.id,
                    c.requirement,
                    () => _change(() => widget.repository.equip(c.id)),
                  ),
                const SizedBox(height: AppSpace.large),
              ],
              const ActivitySection('나의 타이틀', subtitle: '지금의 나를 나타내는 한마디'),
              _option(
                '나의 첫 페이지',
                true,
                growth.titleId == null,
                '타이틀 없이 지내기',
                () => _change(
                  () =>
                      GrowthRepository(widget.repository.database)
                          .equip(null, growth),
                ),
              ),
              for (final entry in titles.entries)
                _option(
                  entry.value,
                  growth.unlockedTitles.contains(entry.key),
                  growth.titleId == entry.key,
                  growth.achievements
                          .where((a) => a.titleId == entry.key)
                          .firstOrNull
                          ?.label ??
                      '업적 달성',
                  () => _change(
                    () =>
                        GrowthRepository(widget.repository.database)
                            .equip(entry.key, growth),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _metric(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 112),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    ),
  );

  Widget _option(
    String label,
    bool unlocked,
    bool selected,
    String requirement,
    VoidCallback onTap,
  ) => Semantics(
    selected: unlocked && selected,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: AppSpace.medium,
      leading: Icon(
        !unlocked
            ? Icons.lock_outline
            : selected
            ? Icons.check_circle
            : Icons.circle_outlined,
      ),
      title: Text(label),
      subtitle: Text(
        !unlocked
            ? '$requirement · 잠김'
            : selected
            ? '장착 중'
            : '해금됨 · $requirement',
      ),
      enabled: unlocked && !_busy,
      onTap: unlocked && !_busy ? onTap : null,
    ),
  );
}

class _RewardInbox extends StatefulWidget {
  const _RewardInbox({required this.repository, required this.rewards});
  final CharacterRepository repository;
  final List<ProfileReward> rewards;
  @override
  State<_RewardInbox> createState() => _RewardInboxState();
}

class _RewardInboxState extends State<_RewardInbox> {
  int _page = 0;
  bool _busy = false;
  bool _confirmed = false;
  String? _error;
  List<ProfileReward> get _items =>
      widget.rewards.skip(_page * 10).take(10).toList();
  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await widget.repository.acknowledge(_items.map((r) => r.key).toList());
      if (mounted) {
        setState(() {
          _confirmed = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '확인 상태를 저장하지 못했어요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('나의 보상함')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.page),
        children: [
          const Text('한 걸음씩 쌓인 성장의 순간이에요.'),
          if (widget.rewards.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.section),
              child: Text('새로운 보상이 생기면 이곳에 모아 드려요.'),
            ),
          for (final r in _items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.seen || _confirmed
                    ? Icons.check_circle_outline
                    : Icons.auto_awesome_outlined,
              ),
              title: Text(r.label),
              subtitle: Text(r.seen || _confirmed ? '확인한 보상' : '새 보상'),
            ),
          if (_error != null) Text(_error!),
          if (_items.isNotEmpty)
            FilledButton(
              onPressed: _busy || _confirmed ? null : _confirm,
              child: Text(_confirmed ? '확인했어요' : '이 보상들 확인하기'),
            ),
          if ((_page + 1) * 10 < widget.rewards.length)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _page++;
                      _confirmed = false;
                    }),
              child: const Text('이전 보상 더 보기'),
            ),
        ],
      ),
    ),
  );
}
