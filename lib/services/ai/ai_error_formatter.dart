import 'dart:io';

import 'package:dio/dio.dart';

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatAiError(Object error) {
  if (error is AiServiceException) {
    return error.message;
  }

  if (error is DioException) {
    final inner = error.error;
    if (inner is SocketException) {
      if (inner.message.toLowerCase().contains('failed host lookup')) {
        return '网络连接失败：无法解析 AI 服务地址，请检查手机网络、DNS、代理/VPN，或在设置页确认 API 地址是否正确。';
      }
      return '网络连接失败：请检查手机是否可以访问互联网。';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'AI 服务连接超时：请检查网络后重试。';
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          return 'AI 鉴权失败：请检查 DeepSeek API Key 是否正确。';
        }
        if (statusCode == 429) {
          return 'AI 请求过于频繁或额度不足，请稍后重试。';
        }
        if (statusCode != null && statusCode >= 500) {
          return 'AI 服务暂时不可用，请稍后重试。';
        }
        return 'AI 请求失败：服务器返回异常状态 ${statusCode ?? ''}。'.trim();
      case DioExceptionType.connectionError:
        return '网络连接失败：请检查手机网络、DNS、代理/VPN，或在设置页确认 API 地址是否正确。';
      case DioExceptionType.cancel:
        return 'AI 请求已取消。';
      case DioExceptionType.badCertificate:
        return 'AI 服务证书校验失败，请检查系统时间和网络环境。';
      case DioExceptionType.unknown:
        return 'AI 请求失败：请检查网络后重试。';
    }
  }

  final message = error.toString();
  if (message.startsWith('Exception: ')) {
    return message.substring('Exception: '.length);
  }
  return message;
}
