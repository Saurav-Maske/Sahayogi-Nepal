import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

class VolunteerAuthException implements Exception {
  const VolunteerAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VolunteerAccount {
  const VolunteerAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.roles,
  });

  final String name;
  final String email;
  final String phone;
  final List<String> roles;
}

class VolunteerApplicationSubmission {
  const VolunteerApplicationSubmission({
    required this.applicationId,
    required this.status,
  });

  final String applicationId;
  final String status;
}

class VolunteerDocument {
  const VolunteerDocument({
    required this.kind,
    required this.bytes,
    required this.contentType,
  });

  final String kind;
  final Uint8List bytes;
  final String contentType;
}

class VolunteerAuthService {
  VolunteerAuthService._();

  static final _client = Supabase.instance.client;

  static bool get hasSession => _client.auth.currentSession != null;

  static Future<VolunteerAccount> signIn({
    required String email,
    required String password,
  }) async {
    final data = await _invoke('volunteer-login', {
      'email': email.trim(),
      'password': password,
    });
    final session = _asMap(data['session']);
    final profile = _asMap(data['profile']);
    if (profile['role'] != 'volunteer') {
      throw const VolunteerAuthException(
        'This account is not a volunteer account.',
      );
    }
    final refreshToken = session['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const VolunteerAuthException(
        'The server did not return a valid login session.',
      );
    }
    await _client.auth.setSession(refreshToken);
    return VolunteerAccount(
      name: '${profile['full_name'] ?? 'Volunteer'}',
      email: '${profile['email'] ?? email}'.trim(),
      phone: '${profile['phone'] ?? ''}'.trim(),
      roles: _rolesFromProfile(profile),
    );
  }

  static Future<VolunteerAccount> currentVolunteer() async {
    if (_client.auth.currentSession == null) {
      throw const VolunteerAuthException('Please log in to continue.');
    }
    final data = await _invoke('auth-me', const {});
    final profile = _asMap(data['profile']);
    if (profile['role'] != 'volunteer' ||
        profile['account_status'] != 'active') {
      throw const VolunteerAuthException(
        'This volunteer account is not active.',
      );
    }
    return VolunteerAccount(
      name: '${profile['full_name'] ?? 'Volunteer'}',
      email: '${profile['email'] ?? ''}'.trim(),
      phone: '${profile['phone'] ?? ''}'.trim(),
      roles: _rolesFromProfile(profile),
    );
  }

  static Future<void> signOut() => _client.auth.signOut();

  static Future<void> sendSignupOtp(String email) async {
    await _invoke('send-signup-otp', {'email': email.trim().toLowerCase()});
  }

  static Future<void> requestPasswordReset(String email) async {
    await _invoke(
      'request-password-reset',
      {'email': email.trim().toLowerCase()},
    );
  }

  static Future<String> verifyPasswordResetOtp({
    required String email,
    required String code,
  }) async {
    final data = await _invoke('verify-reset-otp', {
      'email': email.trim().toLowerCase(),
      'otp': code.trim(),
    });
    final token = data['reset_token'];
    if (token is! String || token.isEmpty) {
      throw const VolunteerAuthException(
        'Password verification did not return a valid token.',
      );
    }
    return token;
  }

  static Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _invoke('reset-password', {
      'email': email.trim().toLowerCase(),
      'reset_token': resetToken,
      'new_password': newPassword,
    });
  }

  static Future<String> verifySignupOtp({
    required String email,
    required String code,
  }) async {
    final data = await _invoke('verify-signup-otp', {
      'email': email.trim().toLowerCase(),
      'otp': code.trim(),
    });
    final token = data['email_verification_token'];
    if (token is! String || token.isEmpty) {
      throw const VolunteerAuthException(
        'Email verification did not return a valid token.',
      );
    }
    return token;
  }

  static Future<VolunteerApplicationSubmission> submitApplication({
    required String fullName,
    required String email,
    required String phone,
    required List<String> volunteerTypes,
    required String citizenshipNumber,
    required String? drivingLicenseNumber,
    required String? medicalLicenseNumber,
    required String emailVerificationToken,
    required List<VolunteerDocument> documents,
  }) async {
    final uploadData = await _invoke('create-upload-urls', {
      'volunteer_types': volunteerTypes,
      'files': documents
          .map((document) => {
                'kind': document.kind,
                'content_type': document.contentType,
              })
          .toList(),
    });
    final uploads = (uploadData['uploads'] as List?)?.map(_asMap).toList() ??
        const <Map<String, dynamic>>[];
    if (uploads.length != documents.length) {
      throw const VolunteerAuthException(
        'The server did not prepare every document upload.',
      );
    }

    final paths = <String, String>{};
    for (final upload in uploads) {
      final kind = '${upload['kind']}';
      final document = documents.where((item) => item.kind == kind).firstOrNull;
      if (document == null) {
        throw const VolunteerAuthException(
          'The server returned an unexpected document type.',
        );
      }
      final path = upload['path'];
      final token = upload['token'];
      if (path is! String || token is! String) {
        throw const VolunteerAuthException(
          'The server returned an invalid document upload URL.',
        );
      }
      try {
        await _client.storage.from('volunteer-docs').uploadBinaryToSignedUrl(
              path,
              token,
              document.bytes,
              FileOptions(contentType: document.contentType, upsert: false),
            );
      } on StorageException catch (error) {
        throw VolunteerAuthException(
          'Could not upload the $kind document: ${error.message}',
        );
      }
      paths[kind] = path;
    }

    final result = await _invoke('submit-volunteer-application', {
      'full_name': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'email_verification_token': emailVerificationToken,
      'phone': phone.trim(),
      'volunteer_types': volunteerTypes,
      'citizenship_no': citizenshipNumber.trim(),
      'citizenship_photo_path': paths['citizenship'],
      if (drivingLicenseNumber != null)
        'license_no': drivingLicenseNumber.trim(),
      if (paths['license'] != null) 'license_photo_path': paths['license'],
      if (medicalLicenseNumber != null)
        'service_card_no': medicalLicenseNumber.trim(),
      if (paths['service_card'] != null)
        'service_card_photo_path': paths['service_card'],
    });
    final applicationId = result['application_id'];
    if (applicationId is! String || applicationId.isEmpty) {
      throw const VolunteerAuthException(
        'The application was submitted, but the server did not return its reference.',
      );
    }
    return VolunteerApplicationSubmission(
      applicationId: applicationId,
      status: '${result['status'] ?? 'submitted'}',
    );
  }

  static Future<String> viewVolunteerApplication({
    required String applicationId,
  }) async {
    final data = await _invoke('view-volunteer-application', {
      'application_id': applicationId,
    });
    final application = _asMap(data['application']);
    final status = data['status'] ??
        data['review_status'] ??
        application['status'] ??
        application['review_status'];
    if (status is! String || status.isEmpty) {
      throw const VolunteerAuthException(
        'The server did not return an application status.',
      );
    }
    return status;
  }

  static Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    if (Config.supabaseAnonKey.trim().isEmpty) {
      throw const VolunteerAuthException(
        'Supabase is not configured. Run the app with SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    try {
      final response = await _client.functions.invoke(functionName, body: body);
      final envelope = _asMap(response.data);
      final error = envelope['error'];
      if (error is Map) {
        throw VolunteerAuthException(
          '${error['message'] ?? 'Request failed.'}',
        );
      }
      return _asMap(envelope['data']);
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = _errorEnvelope(details);
      final errorBody = envelope['error'];
      if (error.status == 0) {
        final advice = Config.supabaseUrl.contains('10.0.2.2')
            ? 'This phone cannot reach the Android emulator address 10.0.2.2. Use your Supabase project URL or your computer’s LAN IP.'
            : 'Check that this phone can reach the configured Supabase URL.';
        throw VolunteerAuthException('Could not connect to Supabase. $advice');
      }
      final message = errorBody is Map
          ? '${errorBody['message'] ?? error.reasonPhrase ?? 'Request failed.'}'
          : envelope['message'] is String
              ? envelope['message'] as String
              : details is String && details.trim().isNotEmpty
                  ? details.trim()
                  : error.reasonPhrase ?? 'Request failed. Please try again.';
      throw VolunteerAuthException(message);
    }
  }

  static Map<String, dynamic> _errorEnvelope(dynamic details) {
    if (details is Map) return _asMap(details);
    if (details is String) {
      try {
        return _asMap(jsonDecode(details));
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<String> _rolesFromProfile(Map<String, dynamic> profile) {
    final categories = (profile['categories'] as List?) ?? const [];
    final roles = <String>['Human Manpower'];
    if (categories.contains('B')) roles.add('Transport Manpower');
    if (categories.contains('C')) roles.add('Health Worker');
    return roles;
  }
}
