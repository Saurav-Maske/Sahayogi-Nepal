import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'volunteer_auth_service.dart';

class SavedVolunteerApplication {
  const SavedVolunteerApplication({
    required this.applicationId,
    required this.status,
    required this.name,
    required this.email,
    required this.phone,
    required this.roles,
  });

  static const _storageKey = 'sahayogi_volunteer_application_v1';

  final String applicationId;
  final String status;
  final String name;
  final String email;
  final String phone;
  final List<String> roles;

  VolunteerApplicationSubmission get submission =>
      VolunteerApplicationSubmission(
        applicationId: applicationId,
        status: status,
      );

  static Future<void> save(SavedVolunteerApplication application) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey,
        jsonEncode({
          'application_id': application.applicationId,
          'status': application.status,
          'name': application.name,
          'email': application.email,
          'phone': application.phone,
          'roles': application.roles,
        }),
      );
    } catch (_) {
      // Status remains available in the current registration flow.
    }
  }

  static Future<SavedVolunteerApplication?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_storageKey);
      if (encoded == null) return null;
      final value = jsonDecode(encoded);
      if (value is! Map) return null;
      final record = Map<String, dynamic>.from(value);
      final applicationId = record['application_id'];
      final email = record['email'];
      if (applicationId is! String || email is! String) return null;
      return SavedVolunteerApplication(
        applicationId: applicationId,
        status: '${record['status'] ?? 'submitted'}',
        name: '${record['name'] ?? ''}',
        email: email,
        phone: '${record['phone'] ?? ''}',
        roles: (record['roles'] as List? ?? const [])
            .map((role) => '$role')
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateStatus(String status) async {
    try {
      final application = await load();
      if (application == null) return;
      await save(
        SavedVolunteerApplication(
          applicationId: application.applicationId,
          status: status,
          name: application.name,
          email: application.email,
          phone: application.phone,
          roles: application.roles,
        ),
      );
    } catch (_) {}
  }

  static Future<void> clearForEmail(String email) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final application = await load();
      if (application?.email.toLowerCase() == email.trim().toLowerCase()) {
        await preferences.remove(_storageKey);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_storageKey);
    } catch (_) {}
  }
}
