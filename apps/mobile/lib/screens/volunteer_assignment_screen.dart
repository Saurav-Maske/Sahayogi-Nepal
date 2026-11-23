import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/app_colors.dart';
import '../core/volunteer_session_guard.dart';
import 'volunteer_login_screen.dart';

class VolunteerAssignmentScreen extends StatefulWidget {
  const VolunteerAssignmentScreen({
    super.key,
    required this.assignmentId,
    required this.initialOffer,
  });

  final String assignmentId;
  final Map<String, dynamic> initialOffer;

  @override
  State<VolunteerAssignmentScreen> createState() =>
      _VolunteerAssignmentScreenState();
}

class _VolunteerAssignmentScreenState extends State<VolunteerAssignmentScreen> {
  final MapController _mapController = MapController();
  late Map<String, dynamic> _assignment;
  final _otpController = TextEditingController();
  StreamSubscription<Position>? _locationSubscription;
  bool _loading = true;
  bool _claiming = false;
  bool _loadingPreviewRoute = false;
  DateTime? _lastPreviewRouteAt;
  List<LatLng> _previewRoute = const [];
  String? _routeError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _assignment = widget.initialOffer;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await Api.getVolunteerAssignment(widget.assignmentId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok && result.data != null) {
        _assignment = result.data!;
      } else {
        _error = result.errorMessage ?? 'Could not load this opportunity.';
      }
    });
    await _syncLocationUpdates();
    if (!_isMine || _activeRouteLegIndex != null) {
      await _loadPreviewRoute();
    } else {
      setState(() => _previewRoute = const []);
    }
  }

  Future<void> _loadPreviewRoute() async {
    final activeLegIndex = _isMine ? _activeRouteLegIndex : null;
    final destination = activeLegIndex == null
        ? _previewDestination
        : _activeRouteDestination;
    if (destination == null) {
      if (mounted) {
        setState(() => _routeError = 'The route location is unavailable.');
      }
      return;
    }
    _lastPreviewRouteAt = DateTime.now();
    if (mounted) {
      setState(() {
        _previewRoute = const [];
        _routeError = null;
        _loadingPreviewRoute = true;
      });
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _routeError = 'Turn on location services to load the route.');
        }
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _routeError = 'Allow location access to load the route.');
        }
        return;
      }
      final origin = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final result = await Api.getVolunteerRoutePreview(
        originLatitude: origin.latitude,
        originLongitude: origin.longitude,
        destinationLatitude: destination.latitude,
        destinationLongitude: destination.longitude,
      );
      if (!mounted) return;
      if (!result.ok || result.data == null) {
        setState(() => _routeError =
            result.errorMessage ?? 'Could not load the route from the server.');
        return;
      }
      final precision = (result.data!['shape_precision'] as num?)?.toInt() ?? 6;
      final points = <LatLng>[];
      final legs = result.data!['legs'];
      if (legs is List && legs.isNotEmpty) {
        for (final leg in legs.whereType<Map>()) {
          final shape = leg['shape']?.toString() ?? '';
          final legPoints = _decodePolyline(shape, precision: precision);
          if (points.isNotEmpty &&
              legPoints.isNotEmpty &&
              points.last.latitude == legPoints.first.latitude &&
              points.last.longitude == legPoints.first.longitude) {
            legPoints.removeAt(0);
          }
          points.addAll(legPoints);
        }
      } else {
        points.addAll(
          _decodePolyline(
            result.data!['shape']?.toString() ?? '',
            precision: precision,
          ),
        );
      }
      if (points.isNotEmpty) {
        setState(() => _previewRoute = points);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _route.length < 2) return;
          _mapController.fitCamera(
            CameraFit.coordinates(
              coordinates: _route,
              padding: const EdgeInsets.all(45),
            ),
          );
        });
      } else {
        setState(() => _routeError = 'The server returned no route points.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _routeError = 'Could not load route: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingPreviewRoute = false);
    }
  }

  List<LatLng> _decodePolyline(String encoded, {int precision = 6}) {
    final points = <LatLng>[];
    if (precision != 5 && precision != 6) return points;
    final scale = precision == 5 ? 100000.0 : 1000000.0;
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int value;
      do {
        if (index >= encoded.length) return points;
        value = encoded.codeUnitAt(index++) - 63;
        result |= (value & 0x1f) << shift;
        shift += 5;
      } while (value >= 0x20);
      latitude += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;
      do {
        if (index >= encoded.length) return points;
        value = encoded.codeUnitAt(index++) - 63;
        result |= (value & 0x1f) << shift;
        shift += 5;
      } while (value >= 0x20);
      longitude += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      final decodedLatitude = latitude / scale;
      final decodedLongitude = longitude / scale;
      if (decodedLatitude < -90 ||
          decodedLatitude > 90 ||
          decodedLongitude < -180 ||
          decodedLongitude > 180) {
        return const [];
      }
      points.add(LatLng(decodedLatitude, decodedLongitude));
    }
    return points;
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final result = await Api.claimVolunteerAssignment(widget.assignmentId);
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!result.ok || result.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Could not accept this task.'),
        ),
      );
      return;
    }
    setState(() => _assignment = result.data!);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'volunteer_active_assignment_id',
      widget.assignmentId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task accepted.')),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _otpController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  bool get _isPickup => _assignment['assignment_type'] == 'pickup';
  bool get _isDelivery => _assignment['assignment_type'] == 'delivery';

  int? get _activeRouteLegIndex {
    final state = '${_assignment['state'] ?? ''}';
    if (!_isMine || (!_isDelivery && !_isPickup)) return null;
    if (state == 'en_route_to_pickup') return 0;
    if (state == 'picked_up' || state == 'en_route_to_destination') return 1;
    return null;
  }

  LatLng? get _activeRouteDestination {
    final legIndex = _activeRouteLegIndex;
    if (legIndex == null) return null;
    final route = _assignment['route'];
    if (route is! List || legIndex >= route.length || route[legIndex] is! Map) {
      return null;
    }
    final point = Map<String, dynamic>.from(route[legIndex] as Map);
    final latitude = point['lat'];
    final longitude = point['lng'];
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  Future<void> _syncLocationUpdates() async {
    final state = '${_assignment['state'] ?? ''}';
    final isTravelling = _isMine &&
        (state == 'en_route_to_pickup' ||
            state == 'picked_up' ||
            state == 'en_route_to_destination');
    if (!isTravelling) {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      return;
    }
    if (_locationSubscription != null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen((position) {
        unawaited(
          Api.updateVolunteerLocation(
            id: widget.assignmentId,
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        );
        final now = DateTime.now();
        final lastRouteAt = _lastPreviewRouteAt;
        if (_activeRouteLegIndex != null &&
            !_loadingPreviewRoute &&
            (lastRouteAt == null ||
                now.difference(lastRouteAt) >= const Duration(seconds: 60))) {
          unawaited(_loadPreviewRoute());
        }
      });
    } catch (_) {
      // The assignment details and progress controls still work without GPS.
    }
  }

  Future<void> _moveTo(String nextState) async {
    setState(() => _claiming = true);
    final result = await Api.updateVolunteerAssignmentState(
      widget.assignmentId,
      nextState,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.errorMessage ?? 'Could not update task.')),
      );
      return;
    }
    await _refresh();
  }

  Future<void> _verifyCode(String purpose, {bool confirmed = false}) async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the code from the requester.')),
      );
      return;
    }
    setState(() => _claiming = true);
    final result = await Api.verifyVolunteerOtp(
      id: widget.assignmentId,
      purpose: purpose,
      code: code,
      confirmed: confirmed,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!result.ok || result.data == null || result.data!['ok'] == false) {
      final reason = result.data?['reason']?.toString();
      if (reason == 'quantity_changed') {
        final changedItems = (result.data?['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pickup quantities changed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'The donor updated the quantities. Confirm these items before pickup.'),
                const SizedBox(height: 10),
                ...changedItems.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                          '${item['qty']} ${item['unit'] ?? 'kits'} · ${item['item_type'] ?? 'item'}'),
                    )),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Review later')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm quantities')),
            ],
          ),
        );
        if (accepted == true && mounted) {
          await _verifyCode(purpose, confirmed: true);
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_otpErrorMessage(
            reason,
            result.data?['attempts_left'],
            fallback: result.errorMessage,
          )),
        ),
      );
      return;
    }
    _otpController.clear();
    await _refresh();
  }

  String _otpErrorMessage(String? reason, Object? attemptsLeft,
          {String? fallback}) =>
      switch (reason) {
        'invalid_otp' => attemptsLeft is num
            ? 'That code is incorrect. $attemptsLeft attempts remain.'
            : 'That code is incorrect. Try again.',
        'otp_locked' => 'This code is locked. Ask for a new code.',
        'otp_expired' => 'This code expired. Ask for a new code.',
        'otp_used' => 'This code has already been used.',
        'otp_not_issued' => 'The code has not been issued yet.',
        _ => fallback ?? 'The code could not be verified.',
      };

  Widget _progressActions(String state) {
    if (state == 'accepted') {
      return Column(
        children: [
          _actionButton(
            'Start task',
            () => _moveTo(
              _isDelivery || _isPickup
                  ? 'en_route_to_pickup'
                  : 'en_route_to_destination',
            ),
          ),
          if (_isDelivery) ...[
            const SizedBox(height: 12),
            _issueReportButton(),
          ],
        ],
      );
    }
    if (state == 'en_route_to_pickup' && _isPickup) {
      return Column(
        children: [
          _otpAction('pickup', 'Confirm pickup with code'),
          const SizedBox(height: 12),
          _issueReportButton(),
        ],
      );
    }
    if (state == 'en_route_to_pickup' && _isDelivery) {
      return Column(
        children: [
          _otpAction('hub_pickup', 'Confirm hub pickup with code'),
          const SizedBox(height: 12),
          _issueReportButton(),
        ],
      );
    }
    if (state == 'picked_up' && (_isDelivery || _isPickup)) {
      return _actionButton(
        'Start delivery route',
        () => _moveTo('en_route_to_destination'),
      );
    }
    if (state == 'en_route_to_destination' && _isDelivery) {
      return _otpAction('delivery', 'Confirm delivery with code');
    }
    if (state == 'en_route_to_destination' && _isPickup) {
      return _otpAction('hub_dropoff', 'Confirm hub drop-off with code');
    }
    if (state == 'en_route_to_destination') {
      return _actionButton('Complete task', () => _moveTo('delivered'));
    }
    return const SizedBox.shrink();
  }

  Widget _otpAction(String purpose, String label) => Column(
        children: [
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          _actionButton(label, () => _verifyCode(purpose)),
        ],
      );

  Widget _issueReportButton() => SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: _claiming ? null : _reportIssue,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Report a problem with these items'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
        ),
      );

  Future<void> _reportIssue() async {
    final controller = TextEditingController();
    var selectedType = 'items_mismatch';
    final issue = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Report an issue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Issue type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'items_mismatch',
                    child: Text('Items do not match'),
                  ),
                  DropdownMenuItem(
                    value: 'pickup_refused',
                    child: Text('Pickup cannot be completed'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedType = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                      'type': selectedType,
                      'note': controller.text.trim(),
                    }),
                child: const Text('Send report')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (issue == null || !mounted) return;
    final note = issue['note'] ?? '';
    if (note.length < 2 || note.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Describe the issue in 2 to 500 characters.')),
      );
      return;
    }
    setState(() => _claiming = true);
    final result = await Api.reportVolunteerIssue(
      id: widget.assignmentId,
      type: issue['type'] ?? 'items_mismatch',
      note: note,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(result.errorMessage ?? 'Could not report the issue.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Issue reported. This task is back in the offer queue.')),
    );
    Navigator.of(context).pop(true);
  }

  Widget _actionButton(String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _claiming ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: appGold,
            foregroundColor: appNavy,
          ),
          child: _claiming
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      );

  List<Map<String, dynamic>> get _items =>
      (_assignment['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  List<LatLng> get _route {
    if (_isMine && (_isDelivery || _isPickup)) {
      return _activeRouteLegIndex != null ? _previewRoute : const [];
    }
    final savedRoute = (_assignment['route'] as List? ?? const [])
        .whereType<Map>()
        .map((point) {
          final latitude = point['lat'];
          final longitude = point['lng'];
          if (latitude is! num || longitude is! num) return null;
          final lat = latitude.toDouble();
          final lng = longitude.toDouble();
          if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
    return savedRoute.isNotEmpty ? savedRoute : _previewRoute;
  }

  LatLng? get _previewDestination {
    final latitude = _assignment['approx_lat'];
    final longitude = _assignment['approx_lng'];
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  bool get _isMine => _assignment['is_mine'] == true;

  @override
  Widget build(BuildContext context) {
    final district = '${_assignment['district'] ?? 'Nearby community'}';
    final state = '${_assignment['state'] ?? 'offered'}';
    final type = '${_assignment['assignment_type'] ?? 'volunteer'}';
    final requester = _assignment['requester'] is Map
        ? Map<String, dynamic>.from(_assignment['requester'] as Map)
        : <String, dynamic>{};
    final previewDestination = _previewDestination;
    final routePoints = _route.isNotEmpty
        ? _route
        : !_isMine && previewDestination != null
            ? [previewDestination]
            : const <LatLng>[];
    final title = _title(type);
    final quantities = _items
        .map((item) {
          final qty = item['qty'] ?? item['approved_qty'] ?? '';
          final unit = '${item['unit'] ?? ''}'.trim();
          return '$qty${unit.isEmpty ? '' : ' $unit'} ${_typeLabel('${item['item_type'] ?? ''}')}'
              .trim();
        })
        .where((value) => value.isNotEmpty)
        .toList();
    final requestKind = '${_assignment['kind'] ?? ''}'.trim();
    final assignmentType = '${_assignment['assignment_type'] ?? ''}'.trim();
    final urgency = '${_assignment['urgency'] ?? ''}'.replaceAll('_', ' ');
    final requestDetails = <String>[
      if (requestKind.isNotEmpty)
        'Request type: ${requestKind.replaceAll('_', ' ')}',
      if (assignmentType.isNotEmpty)
        'Volunteer task: ${assignmentType.replaceAll('_', ' ')}',
      if (urgency.isNotEmpty) 'Urgency: $urgency',
      if (quantities.isNotEmpty) 'Approved items: ${quantities.join(' · ')}',
    ].join('\n');

    return VolunteerSessionGuard(
      onUnauthorized: () => openVolunteerLogin(context),
      child: Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: Text(_isMine ? 'Assigned task' : 'Volunteer opportunity'),
        ),
        body: SafeArea(
          child: _loading && _assignment.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    if (_error != null)
                      _InfoBox(
                        text: _error!,
                        color: const Color(0xFFFFF7DF),
                      ),
                    _InfoBox(
                      text:
                          '${_isMine ? _stateLabel(state) : 'Open'} · $district',
                      color: const Color(0xFFE8F0F4),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _headline(type),
                      style: const TextStyle(
                        color: appNavy,
                        fontSize: 27,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Request details',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _InfoBox(
                      text: requestDetails,
                      color: Colors.white,
                      border: true,
                    ),
                    const SizedBox(height: 10),
                    _InfoBox(
                      text: 'Reference: ${_assignment['public_ref'] ?? ''}',
                      color: Colors.white,
                      border: true,
                    ),
                    if (_isMine && requester.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _InfoBox(
                        text:
                            'Requester: ${requester['name'] ?? 'Community member'}\n${requester['phone'] ?? 'Phone not provided'}',
                        color: Colors.white,
                        border: true,
                      ),
                    ],
                    if (routePoints.isNotEmpty ||
                        (_isMine && _activeRouteLegIndex != null)) ...[
                      const SizedBox(height: 18),
                      Text(
                        _isMine
                            ? state == 'en_route_to_pickup'
                                ? _isDelivery
                                    ? 'Route to hub'
                                    : 'Route to donor'
                                : _isDelivery
                                    ? 'Route to requested destination'
                                    : 'Route to hub'
                            : 'Destination route preview',
                        style: TextStyle(
                          color: appNavy,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingPreviewRoute)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: LinearProgressIndicator(),
                        ),
                      if (routePoints.isNotEmpty)
                        SizedBox(
                          height: 220,
                          child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: routePoints.first,
                              initialZoom: 11,
                              initialCameraFit: routePoints.length > 1
                                  ? CameraFit.coordinates(
                                      coordinates: routePoints,
                                      padding: const EdgeInsets.all(45),
                                    )
                                  : null,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'np.sahayogi.sahayogi_mobile',
                              ),
                              if (routePoints.length > 1)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: routePoints,
                                      color: appTeal,
                                      strokeWidth: 4,
                                    ),
                                  ],
                                ),
                              const CurrentLocationLayer(),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: routePoints.last,
                                    width: 38,
                                    height: 38,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: appNavy,
                                      size: 34,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ),
                        )
                      else
                        _InfoBox(
                          text: _loadingPreviewRoute
                              ? 'Loading the next route from the server…'
                              : _routeError ??
                                  'Route preview is unavailable. Pull down to try again.',
                          color: const Color(0xFFE8F0F4),
                        ),
                    ] else if (!_isMine) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Destination location is unavailable for this request.',
                        style: const TextStyle(color: appMuted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (!_isMine && state == 'offered')
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _claiming ? null : _claim,
                          icon: _claiming
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(_claiming ? 'Joining…' : 'Join now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appGold,
                            foregroundColor: appNavy,
                          ),
                        ),
                      ),
                    if (_isMine && state != 'delivered')
                      _progressActions(state),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'food' => 'food supplies',
        'drinking_water' => 'drinking water',
        'medical_supplies' => 'medical supplies',
        'temp_shelter' => 'temporary shelter',
        'cloth' => 'clothing',
        _ => type.replaceAll('_', ' '),
      };

  String _title(String type) => switch (type) {
        'delivery' => 'Resource delivery',
        'pickup' => 'Donation pickup',
        'healthcare' => 'Health worker support',
        'transport' => 'Transport support',
        'manpower' => 'Community manpower',
        _ => 'Volunteer assignment',
      };

  String _headline(String type) => switch (type) {
        'delivery' || 'pickup' => 'A little help.\nA big difference.',
        'healthcare' => 'Care that reaches\nthose who need it.',
        'transport' => 'Help move support\nwhere it matters.',
        _ => 'A little warmth.\nA big difference.',
      };

  String _stateLabel(String state) => switch (state) {
        'accepted' => 'Accepted',
        'en_route_to_pickup' => 'On the way to pickup',
        'picked_up' => 'Picked up',
        'en_route_to_destination' => 'On the way to delivery',
        'delivered' => 'Delivered',
        _ => state.replaceAll('_', ' '),
      };
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(
      {required this.text, required this.color, this.border = false});

  final String text;
  final Color color;
  final bool border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(17),
          border: border ? Border.all(color: const Color(0xFFE0E6EC)) : null,
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: appNavy,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
