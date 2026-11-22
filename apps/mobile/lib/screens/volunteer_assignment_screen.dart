import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'dart:convert';

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
  late Map<String, dynamic> _assignment;
  final _otpController = TextEditingController();
  StreamSubscription<Position>? _locationSubscription;
  bool _loading = true;
  bool _claiming = false;
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
    await preferences.setString(
      'volunteer_active_assignment',
      jsonEncode(result.data!),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task accepted.')),
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  bool get _isPickup => _assignment['assignment_type'] == 'pickup';
  bool get _isDelivery => _assignment['assignment_type'] == 'delivery';

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
        SnackBar(content: Text(result.errorMessage ?? 'Could not update task.')),
      );
      return;
    }
    await _refresh();
  }

  Future<void> _verifyCode(String purpose) async {
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
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!result.ok || result.data == null || result.data!['ok'] == false) {
      final reason = result.data?['reason']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason ?? result.errorMessage ?? 'The code could not be verified.',
          ),
        ),
      );
      return;
    }
    _otpController.clear();
    await _refresh();
  }

  Widget _progressActions(String state) {
    if (state == 'accepted') {
      return _actionButton(
        'Start task',
        () => _moveTo(
          _isDelivery || _isPickup
              ? 'en_route_to_pickup'
              : 'en_route_to_destination',
        ),
      );
    }
    if (state == 'en_route_to_pickup' && _isPickup) {
      return _otpAction('pickup', 'Confirm pickup with code');
    }
    if (state == 'en_route_to_pickup' && _isDelivery) {
      return _actionButton('Confirm pickup', () => _moveTo('picked_up'));
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
              labelText: 'Requester verification code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          _actionButton(label, () => _verifyCode(purpose)),
        ],
      );

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

  List<LatLng> get _route => (_assignment['route'] as List? ?? const [])
      .whereType<Map>()
      .map((point) => LatLng(
            (point['lat'] as num).toDouble(),
            (point['lng'] as num).toDouble(),
          ))
      .toList();

  bool get _isMine => _assignment['is_mine'] == true;

  @override
  Widget build(BuildContext context) {
    final district = '${_assignment['district'] ?? 'Nearby community'}';
    final state = '${_assignment['state'] ?? 'offered'}';
    final type = '${_assignment['assignment_type'] ?? 'volunteer'}';
    final requester = _assignment['requester'] is Map
        ? Map<String, dynamic>.from(_assignment['requester'] as Map)
        : <String, dynamic>{};
    final title = _title(type);
    final quantities = _items.map((item) {
      final qty = item['qty'] ?? item['approved_qty'] ?? '';
      final unit = '${item['unit'] ?? ''}'.trim();
      return '$qty${unit.isEmpty ? '' : ' $unit'} ${_typeLabel('${item['item_type'] ?? ''}')}'
          .trim();
    }).where((value) => value.isNotEmpty).toList();

    return VolunteerSessionGuard(
      onUnauthorized: () => openVolunteerLogin(context),
      child: Scaffold(
      backgroundColor: appPaper,
      appBar: AppBar(
        backgroundColor: appPaper,
        foregroundColor: appNavy,
        elevation: 0,
        title: Text(_isMine ? 'Assigned task' : 'Volunteer opportunity'),
        actions: [
          IconButton(
            tooltip: 'Refresh task',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _assignment.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  if (_error != null)
                    _InfoBox(
                      text: _error!,
                      color: const Color(0xFFFFF7DF),
                    ),
                  _InfoBox(
                    text: '${_isMine ? _stateLabel(state) : 'Open'} · $district',
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
                  _InfoBox(
                    text: '$title · ${'${_assignment['public_ref'] ?? ''}'}',
                    color: Colors.white,
                    border: true,
                  ),
                  if (quantities.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoBox(
                      text: quantities.join(' · '),
                      color: Colors.white,
                      border: true,
                    ),
                  ],
                  if (_isMine && requester.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _InfoBox(
                      text:
                          'Requester: ${requester['name'] ?? 'Community member'}\n${requester['phone'] ?? 'Phone not provided'}',
                      color: Colors.white,
                      border: true,
                    ),
                  ],
                  if (_route.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Task route',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: _route.first,
                            initialZoom: 11,
                            initialCameraFit: CameraFit.coordinates(
                              coordinates: _route,
                              padding: const EdgeInsets.all(45),
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'np.sahayogi.sahayogi_mobile',
                            ),
                            if (_route.length > 1)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _route,
                                    color: appTeal,
                                    strokeWidth: 4,
                                  ),
                                ],
                              ),
                            const CurrentLocationLayer(),
                            MarkerLayer(
                              markers: [
                                for (var index = 0; index < _route.length; index++)
                                  Marker(
                                    point: _route[index],
                                    width: 34,
                                    height: 34,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: appNavy,
                                      size: 30,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (!_isMine) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Approximate location: ${_assignment['approx_lat'] ?? ''}, ${_assignment['approx_lng'] ?? ''}',
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_claiming ? 'Accepting…' : 'Accept task'),
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
  const _InfoBox({required this.text, required this.color, this.border = false});

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