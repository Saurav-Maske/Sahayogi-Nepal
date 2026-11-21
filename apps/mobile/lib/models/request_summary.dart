import 'package:material_ui/material_ui.dart';

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

  String get reference => '$id · $referenceLine';

  Color get statusColor => switch (status) {
        'In progress' => appNavy,
        'Pending' => const Color(0xFF9A7400),
        _ => const Color(0xFF159B68),
      };
}
