import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the `{ data, error }` contract from docs/API-CONTRACT.md.
class ApiResult<T> {
  final T? data;
  final String? errorCode;
  final String? errorMessage;
  const ApiResult({this.data, this.errorCode, this.errorMessage});
  bool get ok => errorCode == null;
}

class Api {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Anonymous public intake via Edge Function (no direct table insert).
  static Future<ApiResult<Map<String, dynamic>>> submitRequest(Map<String, dynamic> payload) async {
    try {
      final res = await _sb.functions.invoke('submit-request', body: payload);
      final body = res.data as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      if (err != null) return ApiResult(errorCode: err['code'], errorMessage: err['message']);
      return ApiResult(data: body['data'] as Map<String, dynamic>);
    } on FunctionException catch (e) {
      final d = e.details;
      final err = d is Map ? d['error'] as Map? : null;
      return ApiResult(errorCode: err?['code'] ?? 'request_failed', errorMessage: err?['message'] ?? e.toString());
    } catch (e) {
      return ApiResult(errorCode: 'network', errorMessage: e.toString());
    }
  }
}
