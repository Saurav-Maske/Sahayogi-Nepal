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

  /// Authenticated volunteer endpoints. Supabase Functions attaches the active
  /// session's access token to these requests.
  static Future<ApiResult<dynamic>> volunteerAction(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'volunteer-api/$action',
        body: body,
      );
      final envelope = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        return ApiResult(
          errorCode: error['code']?.toString() ?? 'volunteer_api_failed',
          errorMessage:
              error['message']?.toString() ?? 'The request could not be completed.',
        );
      }
      if (!envelope.containsKey('data')) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected response.',
        );
      }
      return ApiResult<dynamic>(data: envelope['data']);
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = details is Map
          ? Map<String, dynamic>.from(details)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      final body = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : <String, dynamic>{};
      return ApiResult(
        errorCode: body['code']?.toString() ?? 'volunteer_api_failed',
        errorMessage: body['message']?.toString() ?? error.toString(),
      );
    } catch (error) {
      return ApiResult(errorCode: 'network', errorMessage: error.toString());
    }
  }

  static Future<ApiResult<List<Map<String, dynamic>>>> getVolunteerOffers() async {
    final result = await volunteerAction('offers');
    if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (result.data is! List) {
      return const ApiResult(
        errorCode: 'invalid_response',
        errorMessage: 'The server returned an unexpected offers response.',
      );
    }
    return ApiResult(
      data: (result.data as List)
          .whereType<Map>()
          .map((offer) => Map<String, dynamic>.from(offer))
          .toList(),
    );
  }

  static Future<ApiResult<Map<String, dynamic>>> getVolunteerStats() async {
    final result = await volunteerAction('stats');
    return _mapResult(result, 'stats');
  }

  static Future<ApiResult<Map<String, dynamic>>> getVolunteerAssignment(
    String id,
  ) async {
    final result = await volunteerAction('assignments/detail', body: {'id': id});
    return _mapResult(result, 'assignment');
  }

  static Future<ApiResult<Map<String, dynamic>>> claimVolunteerAssignment(
    String id,
  ) async {
    final result = await volunteerAction('assignments/claim', body: {'id': id});
    return _mapResult(result, 'assignment');
  }

  static Future<ApiResult<Map<String, dynamic>>> updateVolunteerAssignmentState(
    String id,
    String state,
  ) async {
    final result = await volunteerAction(
      'assignments/state',
      body: {'id': id, 'state': state},
    );
    return _mapResult(result, 'assignment state');
  }

  static Future<ApiResult<Map<String, dynamic>>> verifyVolunteerOtp({
    required String id,
    required String purpose,
    required String code,
    bool confirmed = false,
  }) async {
    final result = await volunteerAction(
      'assignments/verify-otp',
      body: {
        'id': id,
        'purpose': purpose,
        'code': code,
        if (confirmed) 'confirmed': true,
      },
    );
    return _mapResult(result, 'OTP verification');
  }

  static Future<ApiResult<Map<String, dynamic>>> updateVolunteerLocation({
    required String id,
    required double latitude,
    required double longitude,
  }) async {
    final result = await volunteerAction(
      'assignments/location',
      body: {'id': id, 'lat': latitude, 'lng': longitude},
    );
    return _mapResult(result, 'location update');
  }

  static ApiResult<Map<String, dynamic>> _mapResult(
    ApiResult<dynamic> result,
    String label,
  ) {
    if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (result.data is! Map) {
      return ApiResult(
        errorCode: 'invalid_response',
        errorMessage: 'The server returned an unexpected $label response.',
      );
    }
    return ApiResult(data: Map<String, dynamic>.from(result.data as Map));
  }

  /// Public, privacy-preserving map markers from the `map_markers` RPC.
  static Future<ApiResult<List<Map<String, dynamic>>>> getMapMarkers() async {
    try {
      final raw = await _sb.rpc('map_markers');
      if (raw is! List) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected map response.',
        );
      }
      return ApiResult(
        data: raw
            .whereType<Map>()
            .map((marker) => Map<String, dynamic>.from(marker))
            .toList(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'map_failed', errorMessage: e.toString());
    }
  }

  /// Public tracking lookup. The ref and secret token together prove ownership.
  static Future<ApiResult<Map<String, dynamic>>> getRequestTracking({
    required String reference,
    required String token,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'public-api/tracking',
        body: {'ref': reference, 'token': token},
      );
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final rawError = body['error'];
      final err = rawError is Map ? Map<String, dynamic>.from(rawError) : null;
      if (err != null) {
        return ApiResult(
          errorCode: err['code']?.toString() ?? 'tracking_failed',
          errorMessage:
              err['message']?.toString() ?? 'Could not load tracking.',
        );
      }
      final rawData = body['data'];
      if (rawData is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected tracking response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(rawData));
    } on FunctionException catch (e) {
      final details = e.details;
      final rawError = details is Map ? details['error'] : null;
      final err = rawError is Map ? rawError : null;
      return ApiResult(
        errorCode: err?['code']?.toString() ?? 'tracking_failed',
        errorMessage: err?['message']?.toString() ?? e.toString(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'network', errorMessage: e.toString());
    }
  }

  /// Anonymous public intake via Edge Function (no direct table insert).
  static Future<ApiResult<Map<String, dynamic>>> submitRequest(
      Map<String, dynamic> payload) async {
    try {
      final res = await _sb.functions.invoke('submit-request', body: payload);
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final rawError = body['error'];
      final err = rawError is Map ? Map<String, dynamic>.from(rawError) : null;
      if (err != null) {
        return ApiResult(
          errorCode: err['code']?.toString() ?? 'request_failed',
          errorMessage:
              err['message']?.toString() ?? 'Could not submit request.',
        );
      }
      final rawData = body['data'];
      if (rawData is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(rawData));
    } on FunctionException catch (e) {
      final d = e.details;
      final rawError = d is Map ? d['error'] : null;
      final err = rawError is Map ? rawError : null;
      return ApiResult(
        errorCode: err?['code']?.toString() ?? 'request_failed',
        errorMessage: err?['message']?.toString() ?? e.toString(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'network', errorMessage: e.toString());
    }
  }
}
