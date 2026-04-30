import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/hive_setup.dart';

/// Public endpoint via Nginx proxy on trusmiledentist.in (mobile carriers
/// in India block non-standard ports like 8009 directly).
/// Override for local dev:
///   --dart-define=API_BASE_URL=http://10.0.2.2:8009/api/v1
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://trusmiledentist.in/medunity-api',
);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = HiveSetup.sessionBox.get('access_token') as String?;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (DioException e, handler) {
      if (e.response?.statusCode == 401) {
        // Phase 1: token refresh / logout logic added here
        HiveSetup.sessionBox.delete('access_token');
      }
      handler.next(e);
    },
  ));
  return dio;
});
