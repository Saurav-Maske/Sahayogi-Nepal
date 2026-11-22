import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/app_home_navigation.dart';
import '../core/app_colors.dart';
import '../core/request_submission.dart';
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

  RequestSummaryData get request => _currentRequest;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
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
      ..sort((a, b) =>
          (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(
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
      updatedAt: DateTime.tryParse('${rawLocation['updated_at'] ?? ''}')
          ?.toLocal(),
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
    final assignments = (_tracking?['assignments'] as List? ?? const [])
        .whereType<Map>();
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
                    IconButton(
                      onPressed: _refreshing ? null : _refreshTracking,
                      tooltip: 'Refresh tracking status',
                      icon: _refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              color: appTeal,
                              size: 20,
                            ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
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
                            : 'Tracking details are unavailable. Use refresh to try again.',
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
        message = 'Could not load live location. Refresh tracking to try again.';
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
                  label: 'Profile',
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
