import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/record_repository.dart';
import 'data/exercise_repository.dart';
import 'services/exercise_recorder.dart';
import 'screens/exercise_screen.dart';
import 'screens/today_screen.dart';
import 'screens/trends_screen.dart';
import 'screens/settings_screen.dart';
import 'services/reminder_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiligentLifeApp());
}

class DiligentLifeApp extends StatelessWidget {
  const DiligentLifeApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Diligent Life',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home ?? const _Bootstrap(),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  RecordRepository? _repository;
  ReminderService? _reminders;
  ExerciseRecorder? _recorder;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _failed = false);
    try {
      final preferences = await SharedPreferences.getInstance();
      final repository = await RecordRepository.open();
      if (!mounted) {
        await repository.database.close();
        return;
      }
      final reminders = ReminderService(preferences);
      final recorder = ExerciseRecorder(
        ExerciseRepository(repository.database),
      );
      await recorder.restore();
      if (!mounted) {
        recorder.dispose();
        await repository.database.close();
        return;
      }
      setState(() {
        _repository = repository;
        _reminders = reminders;
        _recorder = recorder;
      });
      unawaited(reminders.restore());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_repository != null) {
      return AppShell(
        repository: _repository!,
        reminders: _reminders!,
        recorder: _recorder,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('기록 저장소를 열지 못했어요.'),
                    TextButton(onPressed: _open, child: const Text('다시 시도')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.reminders,
    this.recorder,
  });
  final RecordRepository repository;
  final ReminderService reminders;
  final ExerciseRecorder? recorder;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0, _revision = 0;
  bool _dirty = false, _leaving = false;
  bool _exerciseActive = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.recorder?.addListener(_recordingChanged);
    _exerciseActive = widget.recorder?.active ?? false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.recorder?.removeListener(_recordingChanged);
    super.dispose();
  }

  void _recordingChanged() {
    final active = widget.recorder?.active ?? false;
    if (mounted && _exerciseActive != active) {
      setState(() {
        _exerciseActive = active;
        _revision++;
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (widget.recorder?.active ?? false) {
        final finish = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('운동을 계속 기록할까요?'),
            content: const Text(
              '계속 기록을 선택하면 앱을 나가도 기록이 이어져요. 일시정지 상태는 그대로 유지돼요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 기록'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('운동 종료'),
              ),
            ],
          ),
        );
        if (finish == null || !mounted) return;
        if (finish) {
          await widget.recorder!.finish();
          if (!mounted || widget.recorder!.active) return;
        }
        // Keep the Flutter engine and its location subscription alive on Android.
        if (defaultTargetPlatform == TargetPlatform.android) {
          await const MethodChannel('diligent_life/lifecycle')
              .invokeMethod<void>('moveToBackground');
          return;
        }
        return;
      }
      if (_dirty) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('저장하지 않은 입력이 있어요.'),
            content: const Text('저장하지 않고 나갈까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 입력'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('나가기'),
              ),
            ],
          ),
        );
        if (leave != true) return;
      }
      await SystemNavigator.pop();
    } finally {
      _leaving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.reminders.restore());
      setState(() => _revision++);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !(widget.recorder?.active ?? false),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Diligent Life'),
        actions: [
          if (widget.recorder != null)
            TextButton.icon(
              onPressed: () async {
                FocusManager.instance.primaryFocus?.unfocus();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExerciseScreen(
                      recorder: widget.recorder!,
                      records: widget.repository,
                    ),
                  ),
                );
                if (mounted) setState(() => _revision++);
              },
              icon: Icon(
                widget.recorder!.active ? Icons.location_on : Icons.route,
              ),
              label: Text(widget.recorder!.active ? '기록 중' : '운동'),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: IndexedStack(
              index: _index,
              children: [
                TodayScreen(
                  repository: widget.repository,
                  onSaved: () => setState(() => _revision++),
                  onDirtyChanged: (dirty) {
                    if (mounted && _dirty != dirty) {
                      setState(() => _dirty = dirty);
                    }
                  },
                ),
                TrendsScreen(
                  repository: widget.repository,
                  revision: _revision,
                  exercises: widget.recorder?.repository,
                ),
                SettingsScreen(reminders: widget.reminders),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _index = index;
            if (index == 1) _revision++;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: '오늘',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: '포트폴리오',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: '설정'),
        ],
      ),
    ),
  );
}
