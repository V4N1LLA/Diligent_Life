import 'package:flutter/services.dart';

class StepStatus {
  const StepStatus({
    this.supported = false,
    this.permission = false,
    this.enabled = false,
    this.running = false,
    this.error,
  });
  final bool supported, permission, enabled, running;
  final String? error;
  String get message => !supported
      ? '이 기기에서는 만보기를 지원하지 않아요.'
      : !permission
      ? '신체 활동 권한을 허용하면 걸음을 기록해요.'
      : !enabled
      ? '운동을 시작하지 않아도 일상 걸음을 기록해요.'
      : !running
      ? '만보기가 멈춰 있어요. 다시 켜 주세요.'
      : '운동 걸음도 포함된 일상 걸음이에요. GPS 거리와 더하지 않아요.';
}

class StepService {
  static const _channel = MethodChannel('diligent_life/steps');
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('settings');
    } on MissingPluginException {
      /* Non-Android */
    } on PlatformException {
      /* Keep the permission guidance visible. */
    }
  }

  Future<void> suspend() async {
    try {
      await _channel.invokeMethod<void>('suspend');
    } on MissingPluginException {
      /* Non-Android */
    }
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod<void>('resume');
    } on MissingPluginException {
      /* Non-Android */
    } on PlatformException {
      /* Restore succeeded; status exposes a sensor restart failure. */
    }
  }

  Future<void> restore() async {
    try {
      await _channel.invokeMethod<void>('restore');
    } on MissingPluginException {
      /* Non-Android */
    } on PlatformException {
      /* Status exposes failure. */
    }
  }

  Future<StepStatus> status() async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
      return StepStatus(
        supported: r['supported'] == true,
        permission: r['permission'] == true,
        enabled: r['enabled'] == true,
        running: r['running'] == true,
        error: r['error'] == null
            ? null
            : '걸음 기록에 문제가 있어요. 권한·저장 공간·절전 설정을 확인해 주세요.',
      );
    } on MissingPluginException {
      return const StepStatus();
    } on PlatformException {
      return const StepStatus(error: '만보기 상태를 확인하지 못했어요.');
    }
  }

  Future<StepStatus> enable(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(enabled ? 'enable' : 'disable');
    } on PlatformException {
      return const StepStatus(
        supported: true,
        error: '만보기를 시작하지 못했어요. 신체 활동 권한과 절전 설정을 확인해 주세요.',
      );
    }
    return status();
  }

  Future<void> flush() async {
    try {
      await _channel.invokeMethod<void>('flush');
    } on MissingPluginException {
      /* Non-Android */
    }
  }
}
