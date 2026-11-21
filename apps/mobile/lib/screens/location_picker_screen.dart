import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialLocation,
  });

  final LatLng? initialLocation;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _selectedLocation;
  bool _checkingPermission = true;
  bool _locationAllowed = false;
  bool _locationServiceEnabled = true;
  bool _permissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _requestLocationAccess();
  }

  Future<void> _requestLocationAccess() async {
    if (mounted) setState(() => _checkingPermission = true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = false;
        _locationAllowed = false;
        _checkingPermission = false;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    final allowed = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    setState(() {
      _locationServiceEnabled = true;
      _locationAllowed = allowed;
      _permissionPermanentlyDenied =
          permission == LocationPermission.deniedForever;
      _checkingPermission = false;
    });

    if (!allowed) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _selectedLocation ??= LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // The map remains selectable even if a GPS fix is temporarily unavailable.
    }
  }

  Future<void> _openSettings() async {
    if (_permissionPermanentlyDenied) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: const Text(
            'Choose location',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              onPressed: _requestLocationAccess,
              tooltip: 'Use current location',
              icon: const Icon(Icons.my_location_rounded, color: appTeal),
            ),
          ],
        ),
        body: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter:
                    _selectedLocation ?? const LatLng(27.7172, 85.3240),
                initialZoom: 14,
                minZoom: 4,
                maxZoom: 19,
                onTap: (_, point) => setState(() => _selectedLocation = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'np.sahayogi.sahayogi_mobile',
                  maxZoom: 19,
                ),
                if (_locationAllowed)
                  const CurrentLocationLayer(
                    alignPositionOnUpdate: AlignOnUpdate.once,
                    alignDirectionOnUpdate: AlignOnUpdate.never,
                  ),
                if (_selectedLocation case final selected?)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: selected,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_pin,
                          color: Color(0xFFE53935),
                          size: 44,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _mapBadge('© OpenStreetMap contributors'),
            ),
            if (_checkingPermission || !_locationAllowed)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _checkingPermission
                                ? 'Getting your live location…'
                                : _locationServiceEnabled
                                    ? 'Enable location to start from your current position'
                                    : 'Turn on location services or tap the map to choose manually',
                            style: const TextStyle(
                              color: appNavy,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (!_checkingPermission)
                          TextButton(
                            onPressed: _locationServiceEnabled &&
                                    !_permissionPermanentlyDenied
                                ? _requestLocationAccess
                                : _openSettings,
                            child: Text(
                              _locationServiceEnabled &&
                                      !_permissionPermanentlyDenied
                                  ? 'Allow'
                                  : 'Settings',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedLocation == null
                            ? 'Tap the map to choose a location'
                            : 'Selected location',
                        style: const TextStyle(
                          color: appNavy,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_selectedLocation case final selected?) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${selected.latitude.toStringAsFixed(5)}, ${selected.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            color: appMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _selectedLocation == null
                              ? null
                              : () =>
                                  Navigator.of(context).pop(_selectedLocation),
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Use this location'),
                          style: FilledButton.styleFrom(
                            backgroundColor: appNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
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
      );
}

class LiveLocationMapPreview extends StatelessWidget {
  const LiveLocationMapPreview({
    super.key,
    required this.locationAllowed,
    required this.locationServiceEnabled,
    required this.onTap,
    this.currentLocation,
    this.selectedLocation,
    this.height = 112,
  });

  final bool locationAllowed;
  final bool locationServiceEnabled;
  final VoidCallback onTap;
  final LatLng? currentLocation;
  final LatLng? selectedLocation;
  final double height;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: selectedLocation ??
                          currentLocation ??
                          const LatLng(27.7172, 85.3240),
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'np.sahayogi.sahayogi_mobile',
                        maxZoom: 19,
                      ),
                      if (locationAllowed)
                        const CurrentLocationLayer(
                          alignPositionOnUpdate: AlignOnUpdate.once,
                          alignDirectionOnUpdate: AlignOnUpdate.never,
                        ),
                      if (selectedLocation case final selected?)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: selected,
                              width: 32,
                              height: 32,
                              child: const Icon(
                                Icons.location_pin,
                                color: Color(0xFFE53935),
                                size: 30,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: _mapBadge(
                    selectedLocation != null
                        ? 'Location selected · Tap to change'
                        : locationAllowed
                            ? 'Live location · Tap to choose on map'
                            : locationServiceEnabled
                                ? 'Allow location · Tap to choose on map'
                                : 'Turn on location · Tap to choose on map',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

Widget _mapBadge(String text) => DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(color: appNavy, fontSize: 10),
        ),
      ),
    );
