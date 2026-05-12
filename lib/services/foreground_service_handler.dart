import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台服务处理器 - 用于后台录音
class ForegroundServiceHandler {
  static const String _channelId = 'shiguang_recording';
  static const String _channelName = '录音服务';
  static const String _notificationTitle = '拾光正在录音';
  static const String _notificationText = '后台录音进行中，点击回到拾光';

  /// 初始化前台任务
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: '用于后台录音的前台服务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showWhen: true,
        showBadge: true,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
      ),
    );
  }

  /// 启动录音前台服务
  static Future<void> startRecordingService() async {
    if (Platform.isAndroid) {
      // 检查是否已有任务运行
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: _notificationTitle,
          notificationText: _notificationText,
        );
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: _notificationTitle,
        notificationText: _notificationText,
      );

      debugPrint('[ForegroundService] 前台服务已启动');
    }
  }

  /// 停止录音前台服务
  static Future<void> stopRecordingService() async {
    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        debugPrint('[ForegroundService] 前台服务已停止');
      }
    }
  }

  /// 更新前台服务通知
  static Future<void> updateNotification(String text) async {
    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: _notificationTitle,
          notificationText: text,
        );
      }
    }
  }
}
