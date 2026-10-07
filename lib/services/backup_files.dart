import 'dart:io';

import 'package:flutter/services.dart';

// Platform document pickers copy streams to/from app temporary files. No broad
// storage permission, account, or network service is required.
class BackupFiles {
  static const _channel = MethodChannel('diligent_life/backup');
  Future<bool> save(File file) async =>
      await _channel.invokeMethod<bool>('save', {
        'path': file.path,
        'name':
            'diligent-life-${DateTime.now().toIso8601String().substring(0, 10)}.diligent',
      }) ??
      false;
  Future<File?> pick() async {
    final path = await _channel.invokeMethod<String>('pick');
    return path == null ? null : File(path);
  }
}
