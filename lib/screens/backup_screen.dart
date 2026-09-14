import 'dart:io';

import 'package:flutter/material.dart';

import '../data/backup_repository.dart';
import '../services/backup_files.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.repository,
    required this.canImport,
    required this.onImported,
    this.files,
  });
  final BackupRepository repository;
  final bool Function() canImport;
  final Future<void> Function() onImported;
  final BackupFiles? files;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;
  BackupFiles get _files => widget.files ?? BackupFiles();
  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = '원본 기록을 파일로 모으고 있어요.';
    });
    File? file;
    try {
      file = await widget.repository.export();
      final saved = await _files.save(file);
      if (mounted) {
        setState(() => _message = saved ? '백업 파일을 저장했어요.' : '저장을 취소했어요.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '저장하지 못했어요. 저장 공간과 파일 위치를 확인해 주세요.');
      }
    } finally {
      if (file != null) await file.parent.delete(recursive: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (!widget.canImport()) {
      setState(() => _message = '진행 중인 운동을 종료하고 작성 중인 기록을 저장한 뒤 가져와 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '백업 파일을 선택해 주세요.';
    });
    File? file;
    PreparedBackup? prepared;
    try {
      file = await _files.pick();
      if (file == null) {
        if (mounted) setState(() => _message = '가져오기를 취소했어요.');
        return;
      }
      if (mounted) setState(() => _message = '기록과 원본 경로를 확인하고 있어요.');
      prepared = await widget.repository.prepare(file);
      if (!mounted) return;
      final counts = prepared.counts;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('이 백업으로 전체 기록을 교체할까요?'),
          content: SingleChildScrollView(
            child: Text(
              '백업 생성: ${prepared!.createdAt}\n일상 기록 ${counts['daily_records']}개\n운동 ${counts['exercise_sessions']}개\n경로 ${counts['route_points']}개 · 원본 GPS ${counts['raw_route_points']}개\n\n'
              '현재 운동·몸무게·경로를 모두 교체해요. 병합하지 않으며 기존 기록은 남지 않아요. 먼저 현재 데이터를 내보내 주세요.\n알림 설정은 유지해요. 백업의 미완료 운동은 일시정지 상태로 복원돼요.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('전체 기록 교체'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        if (mounted) setState(() => _message = '가져오기를 취소했어요. 기존 기록을 유지해요.');
        return;
      }
      if (!widget.canImport()) throw StateError('운동 또는 입력이 진행 중이에요.');
      await widget.repository.replace(prepared);
      await widget.onImported();
      if (mounted) setState(() => _message = '백업의 전체 기록을 복원했어요.');
    } catch (_) {
      if (mounted) {
        setState(() => _message = '가져오지 못했어요. 지원되는 정상 백업인지 확인해 주세요.');
      }
    } finally {
      await prepared?.dispose();
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('기록 백업과 복원')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('내 기록을 오래 간직하기', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 16),
          const Text(
            '몸무게와 일상 기록, 모든 운동과 전체 경로, 제외된 GPS 원본까지 하나의 파일에 보관해요. 앱 서버나 계정은 사용하지 않아요.',
          ),
          const SizedBox(height: 16),
          const Text(
            '파일에는 숨기지 않은 위치와 몸무게가 포함돼요. 기기의 로컬 폴더에 보관해 주세요. 알림 설정과 지도 캐시는 백업에 포함하지 않아요.',
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _busy ? null : _export,
            child: const Text('전체 기록 내보내기'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _import,
            child: const Text('백업 파일 가져오기'),
          ),
          const SizedBox(height: 16),
          const Text('가져오기는 확인 후 전체 교체해요. 자동 병합하지 않아요. 실패하면 교체 전 기록을 유지해요.'),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!, semanticsLabel: _message),
            ),
        ],
      ),
    ),
  );
}
