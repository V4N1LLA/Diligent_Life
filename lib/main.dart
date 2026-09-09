import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/record_repository.dart';
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
      setState(() {
        _repository = repository;
        _reminders = reminders;
      });
      unawaited(reminders.restore());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_repository != null) {
      return AppShell(repository: _repository!, reminders: _reminders!);
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
  });
  final RecordRepository repository;
  final ReminderService reminders;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0, _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.reminders.restore());
      setState(() => _revision++);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diligent Life')),
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
              ),
              TrendsScreen(repository: widget.repository, revision: _revision),
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
        NavigationDestination(icon: Icon(Icons.show_chart), label: '추이'),
        NavigationDestination(icon: Icon(Icons.tune), label: '설정'),
      ],
    ),
  );
}
