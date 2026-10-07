import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../app_info.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_style.dart';
import '../widgets/theme_selector.dart';
import '../services/step_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.reminders,
    this.onBackup,
    this.onTracking,
    this.visible = true,
    this.revision = 0,
  });
  final ReminderService reminders;
  final VoidCallback? onBackup, onTracking;
  final bool visible;
  final int revision;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: reminders,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.medium,
        AppSpace.page,
        AppSpace.section,
      ),
      children: [
        Text('설정', style: Theme.of(context).textTheme.headlineMedium),
        const ActivitySection('화면', subtitle: '나에게 편안한 모습으로'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeController,
          builder: (context, mode, _) =>
              ThemeSelector(value: mode, onChanged: themeController.select),
        ),
        const ActivitySection('활동 기록'),
        if (onTracking != null)
          _TrackingEntry(
            onTap: onTracking!,
            visible: visible,
            revision: revision,
          ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('매일 기록 알림'),
          subtitle: const Text('오늘의 기록을 남겨볼까요?'),
          value: reminders.enabled,
          onChanged: reminders.busy
              ? null
              : (value) => reminders.update(enable: value),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('알림 시간'),
          trailing: Text(reminders.time.format(context)),
          onTap: reminders.busy
              ? null
              : () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: reminders.time,
                  );
                  if (time != null) {
                    await reminders.update(
                      enable: reminders.enabled,
                      selectedTime: time,
                    );
                  }
                },
        ),
        const Text('기기의 절전 설정에 따라 알림이 조금 늦게 도착할 수 있어요.'),
        if (reminders.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              reminders.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const ActivitySection('데이터', subtitle: '소중한 기록을 안전하게'),
        if (onBackup != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('기록 백업과 복원'),
            subtitle: const Text('전체 원본을 로컬 파일로 보관하기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onBackup,
          ),
        const ActivitySection('앱 정보'),
        Text('Diligent Life', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('버전 $appVersionLabel'),
        const SizedBox(height: 16),
        const Text(
          '가볍게 기록하고, 차분하게 변화를 확인하세요.\n\n광고와 로그인 없이, 기록은 이 기기에 저장돼요. 앱을 삭제하면 기록도 삭제돼요.',
        ),
        const SizedBox(height: 12),
        const Text(
          '운동과 몸무게의 변화를 나만의 포트폴리오로 쌓아요. 지도는 OpenStreetMap에서 불러오며, 표시하는 지도 영역과 IP 주소가 지도 제공자에게 전달돼요. 운동 원본 기록을 업로드하지는 않아요.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Diligent Life',
            applicationVersion: appVersionLabel,
          ),
          child: const Text('오픈소스 라이선스'),
        ),
      ],
    ),
  );
}

class _TrackingEntry extends StatefulWidget {
  const _TrackingEntry({
    required this.onTap,
    required this.visible,
    required this.revision,
  });
  final VoidCallback onTap;
  final bool visible;
  final int revision;
  @override
  State<_TrackingEntry> createState() => _TrackingEntryState();
}

class _TrackingEntryState extends State<_TrackingEntry> {
  Future<StepStatus>? _status;
  void _load() {
    _status = StepService().status();
    _status!.ignore();
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) _load();
  }

  @override
  void didUpdateWidget(_TrackingEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible &&
        (!oldWidget.visible || oldWidget.revision != widget.revision)) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StepStatus>(
    future: _status,
    builder: (context, snapshot) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.directions_walk),
      title: const Text('걸음 측정과 목표'),
      subtitle: Text(
        snapshot.data?.error ??
            snapshot.data?.message ??
            '측정 상태 · 권한 · 하루 목표 확인',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.onTap,
    ),
  );
}
