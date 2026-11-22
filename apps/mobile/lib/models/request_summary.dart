import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../core/app_colors.dart';

class RequestSummaryData {
  const RequestSummaryData({
    required this.id,
    required this.title,
    required this.trackingTitle,
    required this.amountAndLocation,
    required this.requestSummary,
    required this.location,
    required this.submittedAt,
    required this.referenceLine,
    required this.status,
    this.isDonation = false,
    this.trackingToken,
    this.requestKind,
    this.serverStatus,
  });

  final String id;
  final String title;
  final String trackingTitle;
  final String amountAndLocation;
  final String requestSummary;
  final String location;
  final String submittedAt;
  final String referenceLine;
  final String status;
  final bool isDonation;
  final String? trackingToken;
  final String? requestKind;
  final String? serverStatus;

  factory RequestSummaryData.fromSavedSubmission(
    Map<String, dynamic> record,
  ) {
    final kind = '${record['kind'] ?? ''}';
    final items = (record['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final types = items
        .map((item) => _itemTypeLabel('${item['item_type'] ?? ''}'))
        .toSet()
        .toList();
    final quantities = items
        .map((item) {
          final qty = item['qty'] ?? item['requested_qty'] ?? '';
          final unit = '${item['unit'] ?? ''}'.trim();
          return '$qty${unit.isEmpty ? '' : ' $unit'}';
        })
        .where((value) => value.isNotEmpty)
        .join(', ');
    final isDonation = kind == 'donation_offer';
    final note = '${record['notes'] ?? ''}';
    final donationName =
        RegExp(r'Resource: ([^\n—]+)').firstMatch(note)?.group(1)?.trim();
    final title = switch (kind) {
      'donation_offer' => donationName?.isNotEmpty == true
          ? 'Donation: $donationName'
          : 'Community resource donation',
      'healthcare_request' => 'Health worker support',
      'transport_request' => 'Transport manpower support',
      'manpower_request' => 'Human manpower support',
      _ => types.isEmpty
          ? 'Resource assistance request'
          : '${types.join(', ')} needed',
    };
    final volunteers = record['volunteers_needed'];
    final amount = volunteers != null
        ? '$volunteers volunteers'
        : quantities.isEmpty
            ? 'Resource details submitted'
            : quantities;
    final district = '${record['district'] ?? ''}'.trim();
    final place = district.isEmpty ? 'Location provided' : district;
    final createdAt =
        DateTime.tryParse('${record['created_at'] ?? ''}')?.toLocal();
    final dateLabel = createdAt == null
        ? 'Recently'
        : DateFormat('d MMM yyyy, HH:mm').format(createdAt);
    final status =
        _displayStatus('${record['status'] ?? 'pending_admin_review'}');
    final reference = '${record['public_ref'] ?? 'Request'}';
    final requestSummary = volunteers != null
        ? '$volunteers volunteers requested'
        : quantities.isEmpty
            ? title
            : quantities;
    return RequestSummaryData(
      id: reference,
      title: title,
      trackingTitle: title,
      amountAndLocation: '$amount · $place',
      requestSummary: requestSummary,
      location: place,
      submittedAt: dateLabel,
      referenceLine: 'Submitted $dateLabel',
      status: status,
      isDonation: isDonation,
      trackingToken: record['tracking_token']?.toString(),
      requestKind: kind,
      serverStatus: '${record['status'] ?? 'pending_admin_review'}',
    );
  }

  RequestSummaryData copyWith({
    String? status,
    String? serverStatus,
    String? requestSummary,
    String? trackingTitle,
  }) =>
      RequestSummaryData(
        id: id,
        title: title,
        trackingTitle: trackingTitle ?? this.trackingTitle,
        amountAndLocation: amountAndLocation,
        requestSummary: requestSummary ?? this.requestSummary,
        location: location,
        submittedAt: submittedAt,
        referenceLine: referenceLine,
        status: status ?? this.status,
        isDonation: isDonation,
        trackingToken: trackingToken,
        requestKind: requestKind,
        serverStatus: serverStatus ?? this.serverStatus,
      );

  String get reference => '$id · $referenceLine';

  Color get statusColor => switch (status) {
        'Matched' => appNavy,
        'In progress' => appNavy,
        'Pending' => const Color(0xFF9A7400),
        'Fulfilled' => const Color(0xFF159B68),
        _ => const Color(0xFFB42318),
      };
}

String _itemTypeLabel(String type) => switch (type) {
      'food' => 'Food',
      'drinking_water' => 'Drinking water',
      'medical_supplies' => 'Medicine',
      'cloth' => 'Clothing',
      'temp_shelter' => 'Temporary shelter',
      _ => type.replaceAll('_', ' '),
    };

String _displayStatus(String raw) => switch (raw) {
      'pending_admin_review' => 'Pending',
      'approved' || 'awaiting_assignment' || 'assigned' => 'Matched',
      'in_progress' || 'partially_fulfilled' => 'In progress',
      'fulfilled' => 'Fulfilled',
      'declined' => 'Declined',
      'cancelled' => 'Cancelled',
      _ => 'Pending',
    };
