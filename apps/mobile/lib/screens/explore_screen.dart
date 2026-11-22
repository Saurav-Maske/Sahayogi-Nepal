import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/app_home_navigation.dart';
import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import '../core/volunteer_session_guard.dart';
import '../core/request_submission.dart';
import 'assigned_task_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_assignment_screen.dart';
import 'volunteer_login_screen.dart';

class ExploreScreen extends StatefulWidget {
  ExploreScreen({super.key, bool? requireVolunteerSession})
      : requireVolunteerSession =
            requireVolunteerSession ?? VolunteerAuthService.hasSession;

  final bool requireVolunteerSession;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with WidgetsBindingObserver {
  static const _defaultSampleAnchor = LatLng(27.7172, 85.3240);

  bool _checkingPermission = true;
  bool _locationAllowed = false;
  bool _locationServiceEnabled = true;
  bool _permissionPermanentlyDenied = false;
  bool _loadingRequests = true;
  String? _requestLoadError;
  Position? _currentPosition;
  List<_ReliefRequest> _mapRequests = const [];
  StreamSubscription<Position>? _positionSubscription;
  Timer? _offerRefreshTimer;

  List<_ReliefRequest> get _nearbyRequests {
    final position = _currentPosition;
    if (position == null) return _mapRequests;

    final nearby = _mapRequests
        .map((request) {
          final distanceKm = request.distanceKm ??
              Geolocator.distanceBetween(
                    position.latitude,
                    position.longitude,
                    request.position.latitude,
                    request.position.longitude,
                  ) /
                  1000;
          return request.copyWith(
            distanceKm: distanceKm,
            quantity: '${distanceKm.toStringAsFixed(1)} km away',
          );
        })
        .where((request) => request.distanceKm! <= 100)
        .toList();
    nearby.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    return nearby;
  }

  bool get _canViewNearbyRequests => VolunteerAuthService.hasSession;

  Future<void> _validateVolunteerSession() async {
    try {
      await VolunteerAuthService.currentVolunteer();
    } catch (_) {
      await VolunteerAuthService.signOut();
      await clearSavedRequests();
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (VolunteerAuthService.hasSession) {
      unawaited(_validateVolunteerSession());
    }
    _loadMapRequests();
    _requestLocationAccess();
    if (_canViewNearbyRequests) {
      _offerRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (mounted && !_loadingRequests && _currentPosition != null) {
          unawaited(_loadMapRequests());
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _offerRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_locationAllowed &&
        !_checkingPermission) {
      _requestLocationAccess();
    }
  }

  Future<void> _requestLocationAccess() async {
    setState(() {
      _checkingPermission = true;
      _permissionPermanentlyDenied = false;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = false;
        _locationAllowed = false;
        _currentPosition = null;
        _checkingPermission = false;
      });
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    final locationAllowed = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    setState(() {
      _locationServiceEnabled = true;
      _locationAllowed = locationAllowed;
      _permissionPermanentlyDenied =
          permission == LocationPermission.deniedForever;
      _checkingPermission = false;
    });

    if (locationAllowed) {
      await _startLocationTracking();
    } else {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      if (mounted) setState(() => _currentPosition = null);
    }
  }

  Future<void> _startLocationTracking() async {
    await _positionSubscription?.cancel();
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        _updateCurrentPosition(position);
      },
      onError: (_) {},
    );

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      _updateCurrentPosition(position);
      unawaited(_loadMapRequests());
    } catch (_) {
      // The location marker layer continues requesting fixes from its own stream.
    }
  }

  void _updateCurrentPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
    });
  }

  Future<void> _loadMapRequests() async {
    if (mounted) {
      setState(() {
        _loadingRequests = true;
        _requestLoadError = null;
      });
    }
    final position = _currentPosition;
    final nearbyOffersFuture = !_canViewNearbyRequests || position == null
        ? Future.value(
            const ApiResult<List<Map<String, dynamic>>>(
              data: <Map<String, dynamic>>[],
            ),
          )
        : Api.getNearbyVolunteerOffers(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 100,
          );
    final results = await Future.wait([
      Api.getMapMarkers(),
      nearbyOffersFuture,
    ]);
    final result = results[0] as ApiResult<List<Map<String, dynamic>>>;
    final offersResult = results[1] as ApiResult<List<Map<String, dynamic>>>;
    if (!mounted) return;
    if (!result.ok || result.data == null) {
      setState(() {
        _loadingRequests = false;
        _requestLoadError =
            result.errorMessage ?? 'Could not load map requests.';
      });
      return;
    }
    final offersByMarkerKey = <String, List<Map<String, dynamic>>>{};
    if (offersResult.ok) {
      for (final offer in offersResult.data ?? const []) {
        final requestId = offer['request_id'];
        if (requestId is! String || requestId.isEmpty) continue;
        final markerKey =
            sha256.convert(utf8.encode(requestId)).toString().substring(0, 12);
        offersByMarkerKey.putIfAbsent(markerKey, () => []).add(offer);
      }
    }
    final parsed = result.data!
        .map((marker) => _requestFromMarker(
              marker,
              joinOffers: offersByMarkerKey['${marker['key']}'] ?? const [],
            ))
        .whereType<_ReliefRequest>()
        .toList();
    if (_canViewNearbyRequests && offersResult.ok) {
      for (final offer in offersResult.data ?? const []) {
        final items = (offer['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => item['item_type'])
            .whereType<String>()
            .toList();
        final request = _requestFromMarker(
          {
            'layer': 'need',
            'kind': offer['kind'],
            'lat': offer['approx_lat'],
            'lng': offer['approx_lng'],
            'item_types': items,
            'urgency': offer['urgency'],
            'at': offer['offered_at'],
            'distance_km': offer['distance_km'],
          },
          joinOffers: [offer],
        );
        if (request != null) parsed.add(request);
      }
    }
    final groups = <String, _ReliefRequest>{};
    for (final request in parsed) {
      final key =
          '${request.position.latitude.toStringAsFixed(2)},${request.position.longitude.toStringAsFixed(2)}';
      final existing = groups[key];
      if (existing == null) {
        groups[key] = request;
      } else {
        final status = existing.status.index < request.status.index
            ? existing.status
            : request.status;
        groups[key] = existing.copyWith(
          title: 'Multiple community requests',
          kind: 'Multiple help requests',
          status: status,
          icon: null,
          isMultiple: true,
          joinOffers: [...existing.joinOffers, ...request.joinOffers],
        );
      }
    }
    setState(() {
      _mapRequests = groups.values.toList();
      _loadingRequests = false;
    });
  }

  _ReliefRequest? _requestFromMarker(
    Map<String, dynamic> marker, {
    List<Map<String, dynamic>> joinOffers = const [],
  }) {
    final latitude = (marker['lat'] as num?)?.toDouble();
    final longitude = (marker['lng'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final layer = '${marker['layer'] ?? ''}';
    final kindCode = '${marker['kind'] ?? ''}';
    if (layer == 'fulfilled' || layer == 'pickup') {
      final completedAt = DateTime.tryParse('${marker['at'] ?? ''}')?.toUtc();
      if (completedAt == null) return null;
      final validPair =
          (layer == 'fulfilled' && kindCode == 'resource_request') ||
              (layer == 'pickup' && kindCode == 'donation_offer');
      if (!validPair) return null;
      final retention = layer == 'pickup'
          ? const Duration(hours: 6)
          : const Duration(hours: 12);
      final age = DateTime.now().toUtc().difference(completedAt);
      if (age.isNegative || age > retention) return null;
    } else if (layer != 'need') {
      return null;
    }
    final itemTypes = (marker['item_types'] as List? ?? const [])
        .map((item) => '$item')
        .toList();
    final status = switch (layer) {
      'fulfilled' => _RequestStatus.closed,
      'pickup' => _RequestStatus.onTheWay,
      _ => _RequestStatus.needed,
    };
    final kind = switch (kindCode) {
      'healthcare_request' => 'Health worker support',
      'transport_request' => 'Transport manpower',
      'manpower_request' => 'Human manpower',
      'donation_offer' => 'Community donation',
      _ => itemTypes.length > 1
          ? 'Multiple resource types'
          : itemTypes.isEmpty
              ? 'Community request'
              : '${_itemTypeLabel(itemTypes.first)} only',
    };
    final title = kindCode == 'donation_offer'
        ? 'Community resources offered'
        : kindCode.endsWith('_request') && itemTypes.isEmpty
            ? '$kind needed'
            : itemTypes.length > 1
                ? 'Multiple resource needs'
                : itemTypes.isEmpty
                    ? 'Community support needed'
                    : '${_itemTypeLabel(itemTypes.first)} needed';
    return _ReliefRequest(
      position: LatLng(latitude, longitude),
      title: title,
      location: 'Approx. location',
      quantity: 'within 100 km',
      kind: kind,
      status: status,
      icon: _markerIcon(kindCode, itemTypes),
      isMultiple: itemTypes.length > 1,
      key: '${marker['key'] ?? ''}',
      distanceKm: (marker['distance_km'] as num?)?.toDouble(),
      joinOffers: joinOffers,
    );
  }

  String _itemTypeLabel(String type) => switch (type) {
        'food' => 'Food',
        'drinking_water' => 'Drinking water',
        'medical_supplies' => 'Medicine',
        'cloth' => 'Clothing',
        'temp_shelter' => 'Temporary shelter',
        _ => type.replaceAll('_', ' '),
      };

  IconData _markerIcon(String kind, List<String> itemTypes) {
    if (kind == 'healthcare_request' ||
        kind == 'transport_request' ||
        kind == 'manpower_request') {
      return Icons.person_rounded;
    }
    if (itemTypes.length != 1) return Icons.inventory_2_outlined;
    return switch (itemTypes.single) {
      'food' => Icons.restaurant_rounded,
      'temp_shelter' => Icons.home_rounded,
      'drinking_water' => Icons.water_drop_rounded,
      'medical_supplies' => Icons.medical_services_rounded,
      'cloth' => Icons.checkroom_rounded,
      _ => Icons.inventory_2_outlined,
    };
  }

  Future<void> _refreshExplore() async {
    await Future.wait([_requestLocationAccess(), _loadMapRequests()]);
  }

  Future<void> _openLocationSettings() async {
    if (_permissionPermanentlyDenied) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }

  Future<void> _joinOffer(Map<String, dynamic> offer) async {
    final assignmentId = offer['id'];
    if (assignmentId is! String || assignmentId.isEmpty) return;
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VolunteerAssignmentScreen(
          assignmentId: assignmentId,
          initialOffer: offer,
        ),
      ),
    );
    if (!mounted) return;
    _loadMapRequests();
    if (joined == true) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AssignedTaskScreen(assignmentId: assignmentId),
        ),
      );
    }
  }

  void _showRequestDetails(_ReliefRequest request) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: appPaper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _requestDetails(request),
        ),
      ),
    );
  }

  Widget _requestDetails(_ReliefRequest request) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _requestSummary(request),
          const SizedBox(height: 14),
          Text(
            'Status: ${request.statusLabel}',
            style: TextStyle(
              color: request.statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Live public map marker',
            style: TextStyle(color: appMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'The map uses an approximate location. Requester details are kept private.',
            style: TextStyle(color: appNavy, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (request.joinOffers.isNotEmpty) ...[
            ...request.joinOffers.map(
              (offer) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _joinOffer(offer);
                    },
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: const Text('Join now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appGold,
                      foregroundColor: appNavy,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _requestSummary(_ReliefRequest request) => Row(
        children: [
          _RequestMapMarker(request: request, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${request.kind} · ${request.location} · ${request.quantity}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      backgroundColor: appPaper,
      body: _canViewNearbyRequests
          ? SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: appNavy),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: 34,
                              child: SvgPicture.asset(
                                'assets/images/HorizontalLogo.svg',
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                semanticsLabel: 'Sahayogi Nepal',
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _refreshExplore,
                          tooltip: 'Refresh location',
                          icon: const Icon(Icons.my_location_rounded,
                              color: appTeal),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Explore relief map',
                              style: TextStyle(
                                color: appNavy,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              height: 310,
                              child: Stack(
                                children: [
                                  FlutterMap(
                                    options: MapOptions(
                                      initialCenter: _currentPosition == null
                                          ? _defaultSampleAnchor
                                          : LatLng(
                                              _currentPosition!.latitude,
                                              _currentPosition!.longitude,
                                            ),
                                      initialZoom: 13,
                                      minZoom: 5,
                                      maxZoom: 19,
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        userAgentPackageName:
                                            'np.sahayogi.sahayogi_mobile',
                                        maxZoom: 19,
                                      ),
                                      MarkerLayer(
                                        markers: _nearbyRequests
                                            .map(
                                              (request) => Marker(
                                                point: request.position,
                                                width: 46,
                                                height: 46,
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      _showRequestDetails(
                                                          request),
                                                  child: _RequestMapMarker(
                                                    request: request,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                      if (_locationAllowed)
                                        const CurrentLocationLayer(
                                          alignPositionOnUpdate:
                                              AlignOnUpdate.always,
                                          alignDirectionOnUpdate:
                                              AlignOnUpdate.never,
                                        ),
                                    ],
                                  ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'N ↑',
                                          style: TextStyle(
                                            color: appMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 12,
                                    bottom: 8,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Community relief network · Sample map',
                                          style: TextStyle(
                                            color: appMuted,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    bottom: 8,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          '© OpenStreetMap',
                                          style: TextStyle(
                                            color: appNavy,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_checkingPermission || !_locationAllowed)
                                    Positioned(
                                      top: 10,
                                      left: 10,
                                      right: 68,
                                      child: Material(
                                        color: Colors.white
                                            .withValues(alpha: 0.96),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              if (_checkingPermission)
                                                const SizedBox(
                                                  width: 15,
                                                  height: 15,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              else
                                                const Icon(
                                                  Icons.location_off_outlined,
                                                  color: appTeal,
                                                  size: 17,
                                                ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _checkingPermission
                                                      ? 'Getting location…'
                                                      : _locationServiceEnabled
                                                          ? 'Enable location for your live dot'
                                                          : 'Turn on location services for your live dot',
                                                  style: const TextStyle(
                                                    color: appNavy,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                              if (!_checkingPermission)
                                                TextButton(
                                                  onPressed: _locationServiceEnabled
                                                      ? _permissionPermanentlyDenied
                                                          ? _openLocationSettings
                                                          : _requestLocationAccess
                                                      : _openLocationSettings,
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    _locationServiceEnabled &&
                                                            !_permissionPermanentlyDenied
                                                        ? 'Allow'
                                                        : 'Settings',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_canViewNearbyRequests) ...[
                            const SizedBox(height: 12),
                            const Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _MapLegendItem(
                                  color: Color(0xFFE53935),
                                  label: 'Currently needed',
                                ),
                                _MapLegendItem(
                                  color: Color(0xFFF4BD32),
                                  label: 'Recently picked up / help on way',
                                ),
                                _MapLegendItem(
                                  color: Color(0xFF159B68),
                                  label: 'Request closed',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border:
                                    Border.all(color: const Color(0xFFE0E6EC)),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.radar_rounded,
                                        size: 17,
                                        color: appTeal,
                                      ),
                                      const SizedBox(width: 7),
                                      const Expanded(
                                        child: Text(
                                          'Nearby requests',
                                          style: TextStyle(
                                            color: appNavy,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${_nearbyRequests.length} within 100 km',
                                        style: const TextStyle(
                                          color: appMuted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _requestLoadError == null
                                        ? 'Approved requests shared by the community.'
                                        : 'Could not load live requests. Pull to refresh.',
                                    style: const TextStyle(
                                      color: appMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 236,
                                    child: _loadingRequests
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : _nearbyRequests.isEmpty
                                            ? Center(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  child: Text(
                                                    _currentPosition == null
                                                        ? 'Allow location access to find requests within 100 km.'
                                                        : _requestLoadError ??
                                                            'There are no approved requests within 100 km of your location.',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: appMuted,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : ListView.separated(
                                                itemCount:
                                                    _nearbyRequests.length,
                                                separatorBuilder: (_, __) =>
                                                    const Divider(height: 1),
                                                itemBuilder: (context, index) {
                                                  final request =
                                                      _nearbyRequests[index];
                                                  return InkWell(
                                                    onTap: () =>
                                                        _showRequestDetails(
                                                            request),
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        vertical: 9,
                                                      ),
                                                      child: _requestSummary(
                                                          request),
                                                    ),
                                                  );
                                                },
                                              ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _buildGuestMapView(),
      bottomNavigationBar: _ExploreNavigationBar(
        onHome: () => openRoleAwareHome(context),
        onRequests: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MyRequestsScreen(
              requireVolunteerSession: widget.requireVolunteerSession,
            ),
          ),
        ),
        onProfile: () => openVolunteerLogin(context),
      ),
    );
    if (!widget.requireVolunteerSession) return screen;
    return VolunteerSessionGuard(
      onUnauthorized: () => openVolunteerLogin(context),
      child: screen,
    );
  }

  Widget _buildGuestMapView() => SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, color: appNavy),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 34,
                        child: SvgPicture.asset(
                          'assets/images/HorizontalLogo.svg',
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          semanticsLabel: 'Sahayogi Nepal',
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshExplore,
                    tooltip: 'Refresh location',
                    icon: const Icon(Icons.my_location_rounded, color: appTeal),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Explore relief map',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * 0.62)
                          .clamp(360.0, 540.0)
                          .toDouble(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            FlutterMap(
                              options: MapOptions(
                                initialCenter: _currentPosition == null
                                    ? _defaultSampleAnchor
                                    : LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      ),
                                initialZoom: 13,
                                minZoom: 5,
                                maxZoom: 19,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'np.sahayogi.sahayogi_mobile',
                                  maxZoom: 19,
                                ),
                                MarkerLayer(
                                  markers: _nearbyRequests
                                      .map(
                                        (request) => Marker(
                                          point: request.position,
                                          width: 46,
                                          height: 46,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _showRequestDetails(request),
                                            child: _RequestMapMarker(
                                              request: request,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                if (_locationAllowed)
                                  const CurrentLocationLayer(
                                    alignPositionOnUpdate: AlignOnUpdate.always,
                                    alignDirectionOnUpdate: AlignOnUpdate.never,
                                  ),
                              ],
                            ),
                            if (_checkingPermission || !_locationAllowed)
                              Positioned(
                                left: 10,
                                right: 10,
                                top: 10,
                                child: Material(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        if (_checkingPermission)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else
                                          const Icon(
                                            Icons.location_off_outlined,
                                            color: appTeal,
                                            size: 18,
                                          ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _checkingPermission
                                                ? 'Getting your location…'
                                                : 'Enable location to show your live position',
                                            style: const TextStyle(
                                              color: appNavy,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        if (!_checkingPermission)
                                          TextButton(
                                            onPressed: _locationServiceEnabled
                                                ? _permissionPermanentlyDenied
                                                    ? _openLocationSettings
                                                    : _requestLocationAccess
                                                : _openLocationSettings,
                                            child: Text(
                                              _permissionPermanentlyDenied
                                                  ? 'Settings'
                                                  : 'Allow',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const Positioned(
                              right: 8,
                              bottom: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '© OpenStreetMap',
                                    style: TextStyle(
                                      color: appNavy,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReliefRequest {
  const _ReliefRequest({
    required this.position,
    required this.title,
    required this.location,
    required this.quantity,
    required this.kind,
    this.icon,
    required this.status,
    this.isMultiple = false,
    this.key = '',
    this.distanceKm,
    this.joinOffers = const [],
  });

  final LatLng position;
  final String title;
  final String location;
  final String quantity;
  final String kind;
  final IconData? icon;
  final _RequestStatus status;
  final bool isMultiple;
  final String key;
  final double? distanceKm;
  final List<Map<String, dynamic>> joinOffers;

  _ReliefRequest copyWith({
    String? title,
    String? quantity,
    String? kind,
    IconData? icon,
    _RequestStatus? status,
    bool? isMultiple,
    double? distanceKm,
    List<Map<String, dynamic>>? joinOffers,
  }) =>
      _ReliefRequest(
        position: position,
        title: title ?? this.title,
        location: location,
        quantity: quantity ?? this.quantity,
        kind: kind ?? this.kind,
        icon: icon ?? this.icon,
        status: status ?? this.status,
        isMultiple: isMultiple ?? this.isMultiple,
        key: key,
        distanceKm: distanceKm ?? this.distanceKm,
        joinOffers: joinOffers ?? this.joinOffers,
      );

  Color get statusColor =>
      status == _RequestStatus.onTheWay && kind == 'Community donation'
          ? const Color(0xFF2878B5)
          : status.color;

  String get statusLabel => switch (status) {
        _RequestStatus.needed => 'Currently needed',
        _RequestStatus.onTheWay => kind == 'Community donation'
            ? 'Donation picked up'
            : 'Help on the way',
        _RequestStatus.closed => 'Request closed',
      };
}

enum _RequestStatus { needed, onTheWay, closed }

extension on _RequestStatus {
  Color get color => switch (this) {
        _RequestStatus.needed => const Color(0xFFE53935),
        _RequestStatus.onTheWay => const Color(0xFFF4BD32),
        _RequestStatus.closed => const Color(0xFF159B68),
      };
}

class _RequestMapMarker extends StatelessWidget {
  const _RequestMapMarker({required this.request, this.size = 38});

  final _ReliefRequest request;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: request.statusColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          request.isMultiple ? Icons.priority_high_rounded : request.icon,
          color: Colors.white,
          size: size * 0.53,
        ),
      );
}

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: appMuted, fontSize: 9),
          ),
        ],
      );
}

class _ExploreNavigationBar extends StatelessWidget {
  const _ExploreNavigationBar({
    required this.onHome,
    required this.onRequests,
    required this.onProfile,
  });

  final VoidCallback onHome;
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
                _ExploreNavigationItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: onHome,
                ),
                const _ExploreNavigationItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  selected: true,
                ),
                _ExploreNavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  onTap: onRequests,
                ),
                _ExploreNavigationItem(
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

class _ExploreNavigationItem extends StatelessWidget {
  const _ExploreNavigationItem({
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
