import 'package:flutter/material.dart';

import '../data/record_repository.dart';
import '../models/daily_record.dart';
import '../models/exercise_type.dart';
import '../utils/calories.dart';
import '../utils/dates.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.repository,
    required this.onSaved,
  });
  final RecordRepository repository;
  final VoidCallback onSaved;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _minutes = TextEditingController();
  final _distance = TextEditingController();
  final _weightFocus = FocusNode();
  final _minutesFocus = FocusNode();
  final _distanceFocus = FocusNode();
  int _loadGeneration = 0;
  DateTime _date = dayOnly(DateTime.now());
  DateTime _lastToday = dayOnly(DateTime.now());
  ExerciseType _exercise = ExerciseType.lightWalk;
  double? _fallback;
  bool _loading = true, _saving = false, _exists = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weight.dispose();
    _minutes.dispose();
    _distance.dispose();
    _weightFocus.dispose();
    _minutesFocus.dispose();
    _distanceFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = dayOnly(DateTime.now());
    if (state == AppLifecycleState.resumed && now != _lastToday && !_saving) {
      if (_date == _lastToday) {
        _date = now;
        _load();
      }
      _lastToday = now;
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final date = _date;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await widget.repository.forDate(dateKey(date));
      final fallback = await widget.repository.latestWeight(
        dateKey(DateTime(date.year, date.month, date.day - 1)),
      );
      if (!mounted || generation != _loadGeneration) return;
      _weight.text = record?.weightKg?.toString() ?? '';
      _minutes.text = record == null || record.durationMinutes == 0
          ? ''
          : '${record.durationMinutes}';
      _distance.text = record?.distanceKm?.toString() ?? '';
      setState(() {
        _fallback = fallback;
        _exists = record != null;
        _exercise = record?.exerciseType ?? ExerciseType.lightWalk;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '기록을 불러오지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));
  double? get _calculationWeight =>
      _weight.text.trim().isEmpty ? _fallback : _number(_weight.text);
  double? get _calories {
    final weight = _calculationWeight;
    final minutes = _minutes.text.trim().isEmpty
        ? 0
        : int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 0 || minutes > 1440) return null;
    if (_weight.text.trim().isNotEmpty &&
        (weight == null || !weight.isFinite || weight <= 0 || weight > 500)) {
      return null;
    }
    if (minutes == 0) return 0;
    if (weight == null || !weight.isFinite || weight <= 0 || weight > 500) {
      return null;
    }
    return estimateCalories(
      met: _exercise.met,
      weightKg: weight,
      durationMinutes: minutes,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(invalid.first.context, alignment: .2);
      return;
    }
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    if (_weight.text.trim().isEmpty && minutes == 0) {
      _message('몸무게 또는 운동 시간을 입력해 주세요.');
      return;
    }
    if (minutes > 0 && _calculationWeight == null) {
      _message('칼로리 계산에 사용할 몸무게를 한 번 입력해 주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await widget.repository.save(
        DailyRecord(
          date: dateKey(_date),
          weightKg: _number(_weight.text),
          exerciseType: _exercise,
          durationMinutes: minutes,
          distanceKm: _number(_distance.text),
          estimatedCalories: _calories ?? 0,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _exists = true);
      widget.onSaved();
      _message('기록을 저장했어요.');
    } catch (_) {
      if (mounted) _message('저장하지 못했어요. 입력은 유지되어 있어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        // Keep feedback above the persistent save action, including large text.
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          40 + MediaQuery.textScalerOf(context).scale(24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return Form(
      key: _form,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  _date == dayOnly(DateTime.now()) ? '오늘 기록' : '이날 기록',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text('몸무게와 움직임을 가볍게 남겨보세요.'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      '${dateKey(_date)}${_exists ? ' · 저장된 기록' : ''}',
                    ),
                    onPressed: _saving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null && mounted) {
                              _date = picked;
                              await _load();
                            }
                          },
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('weight'),
                  controller: _weight,
                  focusNode: _weightFocus,
                  onFieldSubmitted: (_) => _minutesFocus.requestFocus(),
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  style: Theme.of(context).textTheme.headlineMedium,
                  decoration: InputDecoration(
                    labelText: '몸무게',
                    suffixText: 'kg',
                    helperText: _fallback == null
                        ? '처음 운동을 기록할 때 몸무게가 필요해요.'
                        : '비워두면 최근 몸무게 $_fallback kg으로 계산해요.',
                    helperMaxLines: 3,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value!.trim().isEmpty) return null;
                    final n = _number(value);
                    return n == null || !n.isFinite || n <= 0 || n > 500
                        ? '0 초과 500 이하의 몸무게를 입력해 주세요.'
                        : null;
                  },
                ),
                const SizedBox(height: 28),
                Text('운동', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: ExerciseType.values
                      .map(
                        (type) => ChoiceChip(
                          label: Text(type.label),
                          selected: _exercise == type,
                          onSelected: _saving
                              ? null
                              : (_) {
                                  setState(() => _exercise = type);
                                  _minutesFocus.requestFocus();
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('minutes'),
                  controller: _minutes,
                  focusNode: _minutesFocus,
                  onFieldSubmitted: (_) => _distanceFocus.requestFocus(),
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '운동 시간',
                    suffixText: '분',
                    hintText: '0',
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value!.trim().isEmpty) return null;
                    final n = int.tryParse(value.trim());
                    return n == null || n < 0 || n > 1440
                        ? '0~1440분 사이의 정수를 입력해 주세요.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('distance'),
                  controller: _distance,
                  focusNode: _distanceFocus,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _distanceFocus.unfocus(),
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '운동 거리 (선택)',
                    suffixText: 'km',
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    if (value!.trim().isEmpty) return null;
                    final n = _number(value);
                    if (n == null || !n.isFinite || n < 0 || n > 1000) {
                      return '0~1000km 사이의 거리를 입력해 주세요.';
                    }
                    if (n > 0 &&
                        (int.tryParse(_minutes.text.trim()) ?? 0) == 0) {
                      return '운동 시간도 입력해 주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  _calories == null
                      ? '몸무게와 운동 시간을 확인해 주세요.'
                      : _exercise == ExerciseType.other
                      ? '기타 운동은 가벼운 활동을 기준으로 추정해요.'
                      : '운동 강도에 따른 추정치로, 실제 소모량과 다를 수 있어요.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('예상 소모 칼로리'),
                Text(
                  _calories == null
                      ? '— kcal'
                      : '약 ${_calories!.toStringAsFixed(0)} kcal',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '저장 중…'
                    : _exists
                    ? '기록 수정하기'
                    : '기록 저장하기',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
