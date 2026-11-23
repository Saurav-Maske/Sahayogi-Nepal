import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_home_navigation.dart';
import '../core/app_colors.dart';
import '../core/request_submission.dart';
import '../core/volunteer_auth_service.dart';
import '../models/request_summary.dart';
import 'explore_screen.dart';
import 'volunteer_login_screen.dart';

class RequestTrackingScreen extends StatefulWidget {
  const RequestTrackingScreen({super.key, required this.request});

  final RequestSummaryData request;

  @override
  State<RequestTrackingScreen> createState() => _RequestTrackingScreenState();
}

class _RequestTrackingScreenState extends State<RequestTrackingScreen> {
  late RequestSummaryData _currentRequest;
  Map<String, dynamic>? _tracking;
  List<_VolunteerPosition> _volunteerPositions = const [];
  Timer? _trackingTimer;
  bool _refreshing = false;
  bool _actionLoading = false;
  bool _deliveryConfirmed = false;

  RequestSummaryData get request => _currentRequest;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
    _loadDeliveryConfirmation();
    _refreshTracking();
    _trackingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!{'Fulfilled', 'Declined', 'Cancelled'}.contains(request.status)) {
          _refreshTracking(showErrors: false);
        }
      },
    );
  }

  Future<void> _loadDeliveryConfirmation() async {
    final preferences = await SharedPreferences.getInstance();
    final confirmed = preferences.getBool(_deliveryConfirmationKey) ?? false;
    if (mounted && confirmed) setState(() => _deliveryConfirmed = true);
  }

  String get _deliveryConfirmationKey =>
      'delivery_confirmed_${widget.request.id}';

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTracking({bool showErrors = true}) async {
    final token = request.trackingToken;
    if (token == null || token.isEmpty || _refreshing) return;
    setState(() => _refreshing = true);
    final result = await Api.getRequestTracking(
      reference: request.id,
      token: token,
    );
    if (!mounted) return;
    if (!result.ok || result.data == null) {
      setState(() => _refreshing = false);
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Could not refresh tracking.'),
          ),
        );
      }
      return;
    }
    final data = result.data!;
    final rawStatus = '${data['status'] ?? request.serverStatus ?? ''}';
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final quantities = items
        .map((item) {
          final quantity = item['donor_qty'] ??
              item['approved_qty'] ??
              item['requested_qty'] ??
              '';
          final unit = '${item['unit'] ?? ''}'.trim();
          return '$quantity${unit.isEmpty ? '' : ' $unit'}';
        })
        .where((value) => value.isNotEmpty)
        .join(', ');
    final assignments = (data['assignments'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final positions = assignments
        .map(_positionFromAssignment)
        .whereType<_VolunteerPosition>()
        .toList()
      ..sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.updatedAt?.millisecondsSinceEpoch ?? 0,
          ));
    setState(() {
      _refreshing = false;
      _tracking = data;
      _volunteerPositions = positions;
      _currentRequest = request.copyWith(
        status: _displayTrackingStatus(rawStatus),
        serverStatus: rawStatus,
        requestSummary: quantities.isEmpty ? null : quantities,
      );
    });
    await updateSavedRequestStatus(request.id, rawStatus);
  }

  Future<void> _issueRequesterCode() async {
    final token = request.trackingToken;
    if (token == null || token.isEmpty) return;
    final purpose = '${_tracking?['otp_purpose'] ?? ''}';
    if (purpose != 'pickup' && purpose != 'delivery') return;
    setState(() => _actionLoading = true);
    final result = await Api.requestTrackingOtp(
      reference: request.id,
      token: token,
      purpose: purpose,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (!result.ok || result.data == null) {
      _showActionError(result.errorMessage);
      return;
    }
    final expires =
        DateTime.tryParse('${result.data!['expires_at'] ?? ''}')?.toLocal();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(purpose == 'pickup' ? 'Pickup code' : 'Delivery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Read this one-time code to the volunteer.'),
            const SizedBox(height: 14),
            Center(
              child: SelectableText(
                '${result.data!['code'] ?? ''}',
                style: const TextStyle(
                  color: appNavy,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 5,
                ),
              ),
            ),
            if (expires != null) ...[
              const SizedBox(height: 8),
              Text('Expires ${DateFormat('HH:mm').format(expires)}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    await _refreshTracking(showErrors: false);
  }

  Future<void> _editDonationQuantities() async {
    final token = request.trackingToken;
    if (token == null || token.isEmpty) return;
    final items = (_tracking?['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final controllers = items.map((item) {
      final qty = item['donor_qty'] ??
          item['approved_qty'] ??
          item['requested_qty'] ??
          0;
      return TextEditingController(text: '$qty');
    }).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update pickup quantities'),
        content: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                  'Enter the number of kits you can provide. At least one item must remain.'),
              const SizedBox(height: 12),
              ...List.generate(items.length, (index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          '${_itemLabel(item['item_type']?.toString() ?? 'Item')} kits',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      for (final controller in controllers) {
        controller.dispose();
      }
      return;
    }
    final updates = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final id = items[i]['id'];
      final qty = int.tryParse(controllers[i].text.trim());
      final original = items[i]['donor_qty'] ??
          items[i]['approved_qty'] ??
          items[i]['requested_qty'];
      if (id is! String ||
          qty == null ||
          qty < 0 ||
          (original is num && qty > original)) {
        for (final controller in controllers) {
          controller.dispose();
        }
        _showActionError(
            'Enter whole kit quantities within the approved amount.');
        return;
      }
      if (qty != original) updates.add({'item_id': id, 'qty': qty});
    }
    for (final controller in controllers) {
      controller.dispose();
    }
    if (updates.isEmpty) return;
    setState(() => _actionLoading = true);
    final result = await Api.updateDonationPickupQuantities(
      reference: request.id,
      token: token,
      items: updates,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (!result.ok) {
      _showActionError(result.errorMessage);
      return;
    }
    await _refreshTracking(showErrors: false);
  }

  Future<void> _confirmDelivery(bool full) async {
    final token = request.trackingToken;
    if (token == null || token.isEmpty) return;
    String? note;
    if (!full) {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Report a short delivery'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What was missing?',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Submit')),
          ],
        ),
      );
      controller.dispose();
      if (note == null || !mounted) return;
      if (note.trim().length < 2) {
        _showActionError('Add a short note about the missing items.');
        return;
      }
    }
    setState(() => _actionLoading = true);
    final result = await Api.confirmRequestDelivery(
      reference: request.id,
      token: token,
      full: full,
      note: note,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (!result.ok) {
      _showActionError(result.errorMessage);
      return;
    }
    if (full) {
      setState(() => _deliveryConfirmed = true);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_deliveryConfirmationKey, true);
    }
    await _refreshTracking(showErrors: false);
    if (!full && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Short delivery reported to the response team.')),
      );
    }
  }

  void _showActionError(String? message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? 'Could not complete this action.')),
    );
  }

  String _itemLabel(String type) => type.replaceAll('_', ' ');

  Widget _requesterActions() {
    if (_tracking == null || request.trackingToken?.isNotEmpty != true) {
      return const SizedBox.shrink();
    }
    final purpose = '${_tracking!['otp_purpose'] ?? ''}';
    final canEditPickup = _tracking!['can_update_pickup_qty'] == true;
    final canConfirmDelivery = request.requestKind == 'resource_request' &&
        !_deliveryConfirmed &&
        _tracking!['status'] == 'fulfilled' &&
        '${_tracking!['incident_status'] ?? ''}' != 'open';
    if (!canEditPickup && purpose.isEmpty && !canConfirmDelivery) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E6EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Actions',
              style: TextStyle(
                  color: appNavy, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (purpose == 'pickup' || purpose == 'delivery')
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _actionLoading ? null : _issueRequesterCode,
                  icon: const Icon(Icons.password_rounded),
                  label: Text(_actionLoading
                      ? 'Please wait…'
                      : 'Get ${purpose == 'pickup' ? 'pickup' : 'delivery'} code'),
                )),
          if (canEditPickup)
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _actionLoading ? null : _editDonationQuantities,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Update donation quantities'),
                )),
          if (canConfirmDelivery) ...[
            const Text('Did the delivered items arrive as expected?',
                style: TextStyle(color: appMuted, fontSize: 13)),
            const SizedBox(height: 6),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _actionLoading ? null : () => _confirmDelivery(true),
                  child: const Text('Confirm full delivery'),
                )),
            SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed:
                      _actionLoading ? null : () => _confirmDelivery(false),
                  child: const Text('Report missing items'),
                )),
          ],
        ],
      ),
    );
  }

  _VolunteerPosition? _positionFromAssignment(Map<String, dynamic> assignment) {
    final rawLocation = assignment['location'];
    if (rawLocation is! Map) return null;
    final lat = rawLocation['lat'];
    final lng = rawLocation['lng'];
    if (lat is! num || lng is! num) return null;
    final latitude = lat.toDouble();
    final longitude = lng.toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return _VolunteerPosition(
      name: '${assignment['volunteer_first_name'] ?? 'Volunteer'}',
      point: LatLng(latitude, longitude),
      updatedAt:
          DateTime.tryParse('${rawLocation['updated_at'] ?? ''}')?.toLocal(),
    );
  }

  int get _currentStep => switch (request.serverStatus) {
        'approved' || 'awaiting_assignment' || 'assigned' => 1,
        'in_progress' || 'partially_fulfilled' => 2,
        'fulfilled' => 3,
        _ => switch (request.status) {
            'Pending' => 0,
            'In progress' => 2,
            'Fulfilled' => 3,
            _ => 0,
          },
      };

  bool get _hasAssignedVolunteer {
    final assignments =
        (_tracking?['assignments'] as List? ?? const []).whereType<Map>();
    return assignments.any((assignment) {
      final firstName = assignment['volunteer_first_name'];
      final state = '${assignment['state'] ?? ''}';
      return (firstName is String && firstName.isNotEmpty) ||
          state != 'offered';
    });
  }

  List<_JourneyStep> get _steps {
    return _tracking == null ? const [] : _liveSteps;
  }

  List<_JourneyStep> get _liveSteps {
    final data = _tracking!;
    String time(Object? value, String fallback) {
      if (value is! String) return fallback;
      final parsed = DateTime.tryParse(value)?.toLocal();
      return parsed == null
          ? fallback
          : DateFormat('d MMM · HH:mm').format(parsed);
    }

    final assignments = (data['assignments'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final acceptedAt = assignments
        .map((item) => item['accepted_at'])
        .whereType<String>()
        .firstOrNull;
    final completedAt = assignments
        .map((item) => item['completed_at'])
        .whereType<String>()
        .firstOrNull;
    final created = time(data['created_at'], 'Submitted');
    final matched = time(data['approved_at'], 'Finding a match');
    final progress = time(
      acceptedAt ?? data['picked_up_at'],
      'Awaiting a match',
    );
    final fulfilled =
        time(data['fulfilled_at'] ?? completedAt, 'Awaiting delivery');
    return request.isDonation
        ? [
            _JourneyStep('Donation shared', created),
            _JourneyStep('Recipient matched', matched),
            _JourneyStep(
              data['picked_up_at'] == null ? 'Pickup coordinated' : 'Picked up',
              time(data['picked_up_at'], 'Waiting for pickup'),
            ),
            _JourneyStep('Received', fulfilled),
          ]
        : [
            _JourneyStep('Pending', created),
            _JourneyStep('Matched', matched),
            _JourneyStep('In Progress', progress),
            _JourneyStep('Fulfilled', fulfilled),
          ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: appNavy,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        request.isDonation ? 'Track donation' : 'Track request',
                        style: const TextStyle(
                          color: appNavy,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshTracking(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.id,
                                style: const TextStyle(
                                  color: appNavy,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                request.location,
                                style: const TextStyle(
                                  color: appMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: request.status),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _RequestInfoCard(request: request),
                    if (_tracking != null) ...[
                      const SizedBox(height: 16),
                      _requesterActions(),
                    ],
                    const SizedBox(height: 22),
                    const Text(
                      'Assigned volunteer location',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VolunteerLocationMap(
                      positions: _volunteerPositions,
                      hasAssignedVolunteer: _hasAssignedVolunteer,
                      loading: _refreshing && _tracking == null,
                      trackingLoaded: _tracking != null,
                      trackingTokenAvailable:
                          request.trackingToken?.isNotEmpty == true,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Your relief journey',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_tracking == null)
                      _TrackingMessage(
                        message: _refreshing
                            ? 'Loading tracking details from the server…'
                            : 'Tracking details are unavailable. Pull down to try again.',
                      )
                    else
                      _JourneyCard(
                        steps: _steps,
                        currentStep: _currentStep,
                        fulfilled: request.status == 'Fulfilled',
                      ),
                    const SizedBox(height: 22),
                    const Text(
                      'Latest update',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LatestUpdate(
                      status: request.status,
                      isDonation: request.isDonation,
                    ),
                  ],
                ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _TrackingNavigationBar(
          onHome: () => openRoleAwareHome(context),
          onExplore: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ExploreScreen()),
          ),
          onRequests: () => Navigator.of(context).pop(),
          onProfile: () => openVolunteerLogin(context),
        ),
      );
}

String _displayTrackingStatus(String status) => switch (status) {
      'pending_admin_review' => 'Pending',
      'approved' || 'awaiting_assignment' || 'assigned' => 'Matched',
      'in_progress' || 'partially_fulfilled' => 'In progress',
      'fulfilled' => 'Fulfilled',
      'declined' => 'Declined',
      'cancelled' => 'Cancelled',
      _ => 'Pending',
    };

class _JourneyStep {
  const _JourneyStep(this.title, this.time);

  final String title;
  final String time;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final background = switch (status) {
      'Pending' => const Color(0xFFFFF7DE),
      'Matched' => const Color(0xFFEAF0F5),
      'Fulfilled' => const Color(0xFFE8F5EC),
      _ => const Color(0xFFE9F0F5),
    };
    final border = switch (status) {
      'Pending' => const Color(0xFFF0C650),
      'Fulfilled' => const Color(0xFF159B68),
      _ => appNavy,
    };

    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: status == 'Pending'
              ? const Color(0xFF866500)
              : status == 'Fulfilled'
                  ? const Color(0xFF159B68)
                  : appNavy,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestInfoCard extends StatelessWidget {
  const _RequestInfoCard({required this.request});

  final RequestSummaryData request;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.trackingTitle,
              style: const TextStyle(
                color: appNavy,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              request.requestSummary,
              style: const TextStyle(
                color: appTeal,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Submitted ${request.submittedAt}',
              style: const TextStyle(color: appMuted, fontSize: 10),
            ),
          ],
        ),
      );
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.steps,
    required this.currentStep,
    required this.fulfilled,
  });

  final List<_JourneyStep> steps;
  final int currentStep;
  final bool fulfilled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++)
              _JourneyRow(
                step: steps[index],
                isCurrent: index == currentStep,
                isComplete: fulfilled || index < currentStep,
                isLast: index == steps.length - 1,
                fulfilled: fulfilled,
              ),
          ],
        ),
      );
}

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({
    required this.step,
    required this.isCurrent,
    required this.isComplete,
    required this.isLast,
    required this.fulfilled,
  });

  final _JourneyStep step;
  final bool isCurrent;
  final bool isComplete;
  final bool isLast;
  final bool fulfilled;

  @override
  Widget build(BuildContext context) {
    final dotColor = fulfilled
        ? const Color(0xFF159B68)
        : isComplete || isCurrent
            ? appNavy
            : const Color(0xFFE1E7ED);
    final lineColor = fulfilled || isComplete
        ? (fulfilled ? const Color(0xFF159B68) : appNavy)
        : const Color(0xFFE1E7ED);

    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 52,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isLast)
                  Positioned(
                    top: 17,
                    bottom: 0,
                    child: Container(width: 2, color: lineColor),
                  ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: isComplete || isCurrent ? appNavy : appMuted,
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.time,
                  style: const TextStyle(color: appMuted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolunteerPosition {
  const _VolunteerPosition({
    required this.name,
    required this.point,
    required this.updatedAt,
  });

  final String name;
  final LatLng point;
  final DateTime? updatedAt;
}

class _VolunteerLocationMap extends StatelessWidget {
  const _VolunteerLocationMap({
    required this.positions,
    required this.hasAssignedVolunteer,
    required this.loading,
    required this.trackingLoaded,
    required this.trackingTokenAvailable,
  });

  final List<_VolunteerPosition> positions;
  final bool hasAssignedVolunteer;
  final bool loading;
  final bool trackingLoaded;
  final bool trackingTokenAvailable;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      final String message;
      if (loading) {
        message = 'Loading volunteer location…';
      } else if (!trackingTokenAvailable) {
        message = 'A tracking token is unavailable for this request.';
      } else if (!trackingLoaded) {
        message =
            'Could not load live location. Pull down to try again.';
      } else if (hasAssignedVolunteer) {
        message =
            'Waiting for the assigned volunteer to share a live location.';
      } else {
        message = 'A volunteer has not been assigned yet.';
      }
      return _TrackingMessage(message: message, height: 170);
    }

    final points = positions.map((position) => position.point).toList();
    final mapKey = points
        .map((point) =>
            '${point.latitude.toStringAsFixed(3)},${point.longitude.toStringAsFixed(3)}')
        .join('|');

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(mapKey),
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 14,
                initialCameraFit: CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(42),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'np.sahayogi.sahayogi_mobile',
                ),
                MarkerLayer(
                  markers: [
                    for (final position in positions)
                      Marker(
                        point: position.point,
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: appTeal,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33183D58),
                                blurRadius: 7,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_walk_rounded,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    positions.length == 1
                        ? '${positions.first.name} · ${_updatedLabel(positions.first.updatedAt)}'
                        : '${positions.length} assigned volunteers · updates every 15 seconds',
                    style: const TextStyle(
                      color: appNavy,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _updatedLabel(DateTime? updatedAt) => updatedAt == null
      ? 'update time unavailable'
      : 'updated ${DateFormat('d MMM, HH:mm').format(updatedAt)}';
}

class _TrackingMessage extends StatelessWidget {
  const _TrackingMessage({required this.message, this.height});

  final String message;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: appMuted, fontSize: 12, height: 1.45),
        ),
      );
}

class _LatestUpdate extends StatelessWidget {
  const _LatestUpdate({
    required this.status,
    required this.isDonation,
  });

  final String status;
  final bool isDonation;

  @override
  Widget build(BuildContext context) {
    final isFulfilled = status == 'Fulfilled';
    final isPending = status == 'Pending';
    final isClosed = {'Declined', 'Cancelled'}.contains(status);
    final background = isFulfilled
        ? const Color(0xFFECF7EF)
        : isPending
            ? const Color(0xFFFFF7DE)
            : isClosed
                ? const Color(0xFFFFF0EF)
                : const Color(0xFFEAF0F5);
    final subject = isDonation ? 'Donation' : 'Request';
    final title = switch (status) {
      'Fulfilled' => '$subject fulfilled',
      'Pending' => '$subject pending',
      'Matched' => '$subject matched',
      'Declined' => '$subject declined',
      'Cancelled' => '$subject cancelled',
      _ => '$subject in progress',
    };
    final subjectLower = subject.toLowerCase();
    final message = switch (status) {
      'Pending' =>
        'The backend reports this $subjectLower is waiting for a volunteer match.',
      'Matched' =>
        'A volunteer has been assigned. Their live location appears above when sharing is active.',
      'In progress' => 'The backend reports this $subjectLower is in progress.',
      'Fulfilled' => 'The backend reports this $subjectLower is fulfilled.',
      'Declined' => 'The backend reports this $subjectLower was declined.',
      'Cancelled' => 'The backend reports this $subjectLower was cancelled.',
      _ => 'Current status: $status.',
    };

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE0E6EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: appNavy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: appMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingNavigationBar extends StatelessWidget {
  const _TrackingNavigationBar({
    required this.onHome,
    required this.onExplore,
    required this.onRequests,
    required this.onProfile,
  });

  final VoidCallback onHome;
  final VoidCallback onExplore;
  final VoidCallback onRequests;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E6EC))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                _TrackingNavigationItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: onHome,
                ),
                _TrackingNavigationItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  onTap: onExplore,
                ),
                _TrackingNavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: true,
                  onTap: onRequests,
                ),
                _TrackingNavigationItem(
                  icon: Icons.person_outline_rounded,
                  label: VolunteerAuthService.hasSession ? 'Profile' : 'Join',
                  onTap: onProfile,
                ),
              ],
            ),
          ),
        ),
      );
}

class _TrackingNavigationItem extends StatelessWidget {
  const _TrackingNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 27,
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFE7F0F4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 21, color: appNavy),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: appNavy,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
}
