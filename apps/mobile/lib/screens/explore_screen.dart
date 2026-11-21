import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import 'my_requests_screen.dart';
import 'volunteer_login_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

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
  Position? _currentPosition;
  LatLng? _sampleAnchor;
  StreamSubscription<Position>? _positionSubscription;

  List<_ReliefRequest> get _dummyRequests {
    final anchor = _sampleAnchor ?? _defaultSampleAnchor;
    return [
      _ReliefRequest(
        position: LatLng(anchor.latitude + 0.008, anchor.longitude + 0.010),
        title: 'Food and clean water needed',
        location: 'Nearby area',
        quantity: '8 households',
        kind: 'Help request',
        color: const Color(0xFFE53935),
        icon: Icons.priority_high_rounded,
      ),
      _ReliefRequest(
        position: LatLng(anchor.latitude + 0.015, anchor.longitude - 0.006),
        title: 'Temporary shelter support',
        location: 'Nearby area',
        quantity: '4 families',
        kind: 'Help request',
        color: const Color(0xFFF4BD32),
        icon: Icons.priority_high_rounded,
      ),
      _ReliefRequest(
        position: LatLng(anchor.latitude - 0.012, anchor.longitude + 0.004),
        title: 'Medical supplies delivered',
        location: 'Nearby area',
        quantity: '12 kits',
        kind: 'Resource request',
        color: const Color(0xFF159B68),
        icon: Icons.check_rounded,
      ),
      _ReliefRequest(
        position: LatLng(anchor.latitude - 0.018, anchor.longitude - 0.010),
        title: 'Transport volunteers needed',
        location: 'Nearby area',
        quantity: '3 volunteers',
        kind: 'Assistance request',
        color: const Color(0xFF247A91),
        icon: Icons.add_rounded,
      ),
      _ReliefRequest(
        position: LatLng(anchor.latitude + 0.004, anchor.longitude - 0.018),
        title: 'Medicine request',
        location: 'Nearby area',
        quantity: '8 kits',
        kind: 'Help request',
        color: const Color(0xFF247A91),
        count: '8',
      ),
    ];
  }

  List<_ReliefRequest> get _nearbyRequests {
    final position = _currentPosition;
    if (position == null) return const [];

    return _dummyRequests.where((request) {
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        request.position.latitude,
        request.position.longitude,
      );
      return distanceInMeters <= 100000;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestLocationAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
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
    } catch (_) {
      // The location marker layer continues requesting fixes from its own stream.
    }
  }

  void _updateCurrentPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
      _sampleAnchor ??= LatLng(position.latitude, position.longitude);
    });
  }

  Future<void> _openLocationSettings() async {
    if (_permissionPermanentlyDenied) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
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

  void _showNearbyRequests() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: appPaper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const Text(
                'Nearby requests',
                style: TextStyle(
                  color: appNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sample requests shown until live request data is connected.',
                style: TextStyle(color: appMuted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ..._nearbyRequests.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        _showRequestDetails(request);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _requestSummary(request),
                      ),
                    ),
                  ),
                ),
              ),
              if (_nearbyRequests.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    _currentPosition == null
                        ? 'Allow location access to find sample requests within 100 km.'
                        : 'There are no sample requests within 100 km of your location.',
                    style: const TextStyle(color: appMuted, fontSize: 13),
                  ),
                ),
            ],
          ),
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
          const Text(
            'Sample map request',
            style: TextStyle(color: appMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'This marker uses demo coordinates. Live request locations can replace these when backend coordinates are available.',
            style: TextStyle(color: appNavy, fontSize: 14, height: 1.4),
          ),
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
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon:
                          const Icon(Icons.arrow_back_rounded, color: appNavy),
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
                      onPressed: _requestLocationAccess,
                      tooltip: 'Refresh location',
                      icon:
                          const Icon(Icons.my_location_rounded, color: appTeal),
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
                                options: const MapOptions(
                                  initialCenter: LatLng(27.7172, 85.3240),
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
                                    color: Colors.white.withValues(alpha: 0.8),
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
                                    color: Colors.white.withValues(alpha: 0.8),
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
                                    color: Colors.white.withValues(alpha: 0.9),
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
                                    color: Colors.white.withValues(alpha: 0.96),
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
                                              child: CircularProgressIndicator(
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
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                                  fontWeight: FontWeight.w700,
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
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE0E6EC)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: SizedBox(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.radar_rounded,
                                      size: 16,
                                      color: appTeal,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _currentPosition == null
                                            ? 'Requests within 100 km'
                                            : '${_nearbyRequests.length} sample requests within 100 km',
                                        style: const TextStyle(
                                          color: appMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 52,
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _showNearbyRequests,
                                  iconAlignment: IconAlignment.end,
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                  ),
                                  label: const Text('View nearby requests'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: appNavy,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
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
        ),
        bottomNavigationBar: _ExploreNavigationBar(
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onRequests: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyRequestsScreen()),
          ),
          onProfile: () => openVolunteerLogin(context),
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
    required this.color,
    this.icon,
    this.count,
  });

  final LatLng position;
  final String title;
  final String location;
  final String quantity;
  final String kind;
  final Color color;
  final IconData? icon;
  final String? count;
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
          color: request.color,
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
        child: request.count != null
            ? Text(
                request.count!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Icon(
                request.icon,
                color: Colors.white,
                size: size * 0.53,
              ),
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
                  label: 'Profile',
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
