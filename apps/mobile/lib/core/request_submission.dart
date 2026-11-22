import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const _savedRequestsKey = 'sahayogi_submitted_requests_v1';

Future<List<Map<String, dynamic>>> loadSavedRequests() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getStringList(_savedRequestsKey) ?? const [];
    final records = <Map<String, dynamic>>[];
    for (final entry in encoded) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map) records.add(Map<String, dynamic>.from(decoded));
      } on FormatException {
        // Ignore a damaged local record and keep the remaining submissions.
      }
    }
    return records;
  } catch (_) {
    return const [];
  }
}

/// Request tokens belong to anonymous device tracking. Clear them when a
/// volunteer signs in so one account never sees a previous user's local list.
Future<void> clearSavedRequests() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_savedRequestsKey);
  } catch (_) {
    // A local cleanup failure must not prevent sign-in.
  }
}

Future<void> saveSubmittedRequest({
  required Map<String, dynamic> response,
  required Map<String, dynamic> payload,
}) async {
  final reference = response['public_ref'];
  final token = response['tracking_token'];
  if (reference is! String || token is! String) return;

  try {
    final preferences = await SharedPreferences.getInstance();
    final records = await loadSavedRequests();
    records.removeWhere((record) => record['public_ref'] == reference);
    records.insert(0, {
      'public_ref': reference,
      'tracking_token': token,
      'kind': payload['kind'],
      'items': payload['items'] ?? const [],
      'volunteers_needed': payload['volunteers_needed'],
      'district': response['district'],
      'notes': payload['notes'],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': response['status'] ?? 'pending_admin_review',
    });
    await preferences.setStringList(
      _savedRequestsKey,
      records.take(100).map(jsonEncode).toList(),
    );
  } catch (_) {
    // API success remains valid even if local request history cannot be saved.
  }
}

Future<void> updateSavedRequestStatus(String reference, String status) async {
  await updateSavedRequestStatuses({reference: status});
}

Future<void> updateSavedRequestStatuses(
    Map<String, String> statusByReference) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final records = await loadSavedRequests();
    var changed = false;
    for (final record in records) {
      final status = statusByReference[record['public_ref']];
      if (status != null) {
        record['status'] = status;
        changed = true;
      }
    }
    if (changed) {
      await preferences.setStringList(
        _savedRequestsKey,
        records.map(jsonEncode).toList(),
      );
    }
  } catch (_) {
    // The tracking screen still displays the fetched server status.
  }
}

/// Converts the phone formats accepted by the forms to the local 10 digit
/// format accepted by the request API.
String? normalizeNepalPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('977') && digits.length == 13) {
    digits = digits.substring(3);
  }
  if (digits.length != 10) return null;
  return digits;
}

String? validateNepalPhone(String? value) =>
    normalizeNepalPhone(value ?? '') == null
        ? 'Enter a 10-digit phone number'
        : null;

String? validateRequesterName(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Enter your name';
  if (name.length > 120) return 'Name must be 120 characters or fewer';
  return null;
}

/// The API stores a numeric quantity and a separate unit. Forms currently
/// accept values such as "8 kits", so split those values before submission.
Map<String, dynamic>? parseQuantityAndUnit(String value) {
  final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(.*?)\s*$').firstMatch(value);
  if (match == null) return null;
  final quantity = num.tryParse(match.group(1)!);
  if (quantity == null || quantity <= 0) return null;
  final unit = (match.group(2) ?? '').trim();
  if (unit.length > 20) return null;
  return {'qty': quantity, 'unit': unit.isEmpty ? 'unit' : unit};
}

String? resourceItemType(String category) => switch (category.toLowerCase()) {
      'food' || 'food supplies' => 'food',
      'drinking water' => 'drinking_water',
      'medicine' => 'medical_supplies',
      'clothing' => 'cloth',
      'temporary shelter' => 'temp_shelter',
      _ => null,
    };

String? assistanceRequestKind(String type) => switch (type) {
      'Health Worker' => 'healthcare_request',
      'Transport Manpower' => 'transport_request',
      'Human Manpower' => 'manpower_request',
      _ => null,
    };

Future<void> showSubmissionSuccessDialog(
  BuildContext context,
  Map<String, dynamic> data,
) async {
  final reference = data['public_ref']?.toString() ?? 'Submitted';
  final token = data['tracking_token']?.toString() ?? '';
  final status = data['status']?.toString() ?? 'submitted';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Request submitted'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reference: $reference'),
          Text('Status: ${status.replaceAll('_', ' ')}'),
          const SizedBox(height: 10),
          const Text('Save this tracking token. It is shown only once.'),
          if (token.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(token),
          ],
        ],
      ),
      actions: [
        if (token.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tracking token copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy token'),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

void showSubmissionError<T>(BuildContext context, ApiResult<T> result) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.errorMessage ?? 'Could not submit request.'),
    ),
  );
}
