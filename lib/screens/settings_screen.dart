import 'package:flutter/material.dart';

import '../services/reminder_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.reminders});
  final ReminderService reminders;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: reminders,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Text('설정', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
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
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),
        Text('Diligent Life', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('버전 0.1.0'),
        const SizedBox(height: 16),
        const Text(
          '가볍게 기록하고, 차분하게 변화를 확인하세요.\n\n광고와 로그인 없이, 기록은 이 기기에 저장돼요. 앱을 삭제하면 기록도 삭제돼요.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Diligent Life',
            applicationVersion: '0.1.0',
          ),
          child: const Text('오픈소스 라이선스'),
        ),
      ],
    ),
  );
}
