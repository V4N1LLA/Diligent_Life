import 'package:flutter/material.dart';

import '../models/growth.dart';
import '../theme/app_theme.dart';

String stepLabel(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

class ActivitySurface extends StatelessWidget {
  const ActivitySurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(AppStyle.radius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(AppSpace.large), child: child),
  );
}

class ActivitySection extends StatelessWidget {
  const ActivitySection(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpace.section,
      bottom: AppSpace.large,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpace.small),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class LevelProgress extends StatelessWidget {
  const LevelProgress({super.key, required this.data, this.onTap});
  final GrowthSnapshot data;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ActivitySurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(
              Icons.person_outline,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          title: Text(
            'Lv. ${data.level}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: Text(data.title),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const SizedBox(height: AppSpace.medium),
        LinearProgressIndicator(
          value: data.levelXp / data.nextLevelXp,
          color: Theme.of(context).colorScheme.tertiary,
          semanticsLabel: '레벨 경험치 ${data.levelXp} / ${data.nextLevelXp} XP',
        ),
        const SizedBox(height: AppSpace.small),
        Text(
          '다음 레벨까지 ${data.nextLevelXp - data.levelXp} XP',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class GoalProgressView extends StatelessWidget {
  const GoalProgressView({
    super.key,
    required this.goal,
    this.onShare,
    this.achievement = false,
  });
  final GoalProgress goal;
  final VoidCallback? onShare;
  final bool achievement;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpace.tiny,
                  right: AppSpace.medium,
                ),
                child: Icon(
                  goal.complete
                      ? Icons.check_circle_rounded
                      : achievement
                      ? Icons.lock_outline
                      : goal.id.contains('steps')
                      ? Icons.directions_walk
                      : goal.id.contains('active')
                      ? Icons.schedule
                      : Icons.route,
                  color: goal.complete
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.tiny),
                    Text(
                      '${goal.complete
                          ? achievement
                                ? '해금'
                                : '완료'
                          : '${(goal.fraction * 100).floor()}%'} · +${goal.reward} XP',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (onShare != null && goal.complete)
                IconButton(
                  tooltip: '${goal.label} 성취 카드',
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.medium),
          LinearProgressIndicator(
            value: goal.fraction,
            semanticsLabel: '${goal.label} ${(goal.fraction * 100).floor()}%',
          ),
        ],
      ),
    );
  }
}
