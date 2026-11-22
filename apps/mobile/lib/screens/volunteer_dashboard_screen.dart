import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_colors.dart';
import '../core/volunteer_session_guard.dart';
import '../core/volunteer_auth_service.dart';
import 'explore_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_profile_screen.dart';
import 'volunteer_assignment_screen.dart';
import 'volunteer_login_screen.dart';
import 'request_help_screen.dart';
import 'request_assistance_screen.dart';
import 'donate_resources_screen.dart';
import 'assigned_task_screen.dart';

class VolunteerDashboardScreen extends StatefulWidget {
  const VolunteerDashboardScreen({
    super.key,
    required this.account,
  });

  final VolunteerAccount account;

  @override
  State<VolunteerDashboardScreen> createState() =>
      _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState extends State<VolunteerDashboardScreen> {
  List<Map<String, dynamic>> _nearbyRequests = const [];
  Map<String, dynamic>? _activeAssignment;
  bool _loading = true;
  String? _loadError;
  Timer? _offerRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _offerRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_loading) unawaited(_loadDashboard());
    });
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final position = await _getCurrentPosition();
    final nearbyOffersResult = position == null
        ? const ApiResult<List<Map<String, dynamic>>>(
            errorCode: 'location_unavailable',
            errorMessage: 'Enable location access to find nearby offers.',
          )
        : await Api.getNearbyVolunteerOffers(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 100,
          );
    final preferences = await SharedPreferences.getInstance();
    final activeId = preferences.getString('volunteer_active_assignment_id');
    final activeResult =
        activeId == null ? null : await Api.getVolunteerAssignment(activeId);
    if (!mounted) return;
    final requestsById = <String, Map<String, dynamic>>{};
    for (final offer in nearbyOffersResult.data ?? const []) {
      final requestId = offer['request_id'];
      if (requestId is! String || requestId.isEmpty) continue;
      final existing = requestsById[requestId];
      if (existing != null) {
        (existing['join_offers'] as List<Map<String, dynamic>>).add(offer);
        continue;
      }
      final items = (offer['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      requestsById[requestId] = {
        ...offer,
        'id': offer['assignment_id'],
        'layer': 'need',
        'lat': offer['approx_lat'],
        'lng': offer['approx_lng'],
        'item_types':
            items.map((item) => item['item_type']).whereType<String>().toList(),
        'join_offers': <Map<String, dynamic>>[offer],
      };
    }
    final nearbyRequests = requestsById.values.toList()
      ..sort((a, b) =>
          ((a['distance_km'] as num?)?.toDouble() ?? double.infinity).compareTo(
            (b['distance_km'] as num?)?.toDouble() ?? double.infinity,
          ));
    setState(() {
      _loading = false;
      if (nearbyOffersResult.ok && nearbyOffersResult.data != null) {
        _nearbyRequests = nearbyRequests;
      }
      _activeAssignment = activeResult != null &&
              activeResult.ok &&
              activeResult.data?['is_mine'] == true
          ? activeResult.data
          : null;
      if (position == null) {
        _loadError = 'Enable location access to find requests within 100 km.';
      } else if (!nearbyOffersResult.ok) {
        _loadError = nearbyOffersResult.errorMessage;
      } else if (activeResult != null &&
          !activeResult.ok &&
          activeResult.errorCode != 'not_found') {
        _loadError = activeResult.errorMessage;
      } else {
        _loadError = null;
      }
    });
    if (activeId != null &&
        (activeResult?.errorCode == 'not_found' ||
            (activeResult?.ok == true &&
                activeResult!.data?['is_mine'] != true))) {
      await preferences.remove('volunteer_active_assignment_id');
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _offerRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openOffer(Map<String, dynamic> offer) async {
    final id = offer['id'];
    if (id is! String || id.isEmpty) return;
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VolunteerAssignmentScreen(
          assignmentId: id,
          initialOffer: offer,
        ),
      ),
    );
    if (!mounted) return;
    await _loadDashboard();
    if (joined == true && mounted) {
      await _openAssignedTask(assignmentId: id);
    }
  }

  VoidCallback _joinRequest(Map<String, dynamic> request) {
    final offers = request['join_offers'];
    if (offers is! List || offers.isEmpty || offers.first is! Map) {
      return () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No claimable task is available for this request right now.',
              ),
            ),
          );
    }
    return () => _openOffer(Map<String, dynamic>.from(offers.first as Map));
  }

  void _openExplore(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExploreScreen(requireVolunteerSession: true),
        ),
      );

  Future<void> _openAssignedTask({String? assignmentId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssignedTaskScreen(assignmentId: assignmentId),
      ),
    );
    if (mounted) _loadDashboard();
  }

  void _openRequests(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(requireVolunteerSession: true),
        ),
      );

  void _openRequestHelp() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RequestHelpScreen()),
      );

  void _openRequestAssistance() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const RequestAssistanceScreen(),
        ),
      );

  void _openDonateResources() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DonateResourcesScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) => VolunteerSessionGuard(
        onUnauthorized: () => openVolunteerLogin(context),
        child: Scaffold(
          backgroundColor: appPaper,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Volunteer hub',
                        style: TextStyle(
                          color: appNavy,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SvgPicture.asset(
                      'assets/images/SahayogiNepalLogo.svg',
                      width: 36,
                      height: 36,
                      semanticsLabel: 'Sahayogi Nepal logo',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ready to make\na difference?',
                  style: TextStyle(
                    color: appNavy,
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.account.name,
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                _NextMissionCard(
                  offer: _activeAssignment,
                  loading: _loading,
                  onTap: _activeAssignment != null
                      ? () {
                          final id = _activeAssignment!['id'];
                          _openAssignedTask(
                            assignmentId: id is String ? id : null,
                          );
                        }
                      : () => _openAssignedTask(),
                  buttonLabel: _activeAssignment != null
                      ? 'View assigned task'
                      : 'Current task',
                ),
                const SizedBox(height: 24),
                const Text(
                  'Community actions',
                  style: TextStyle(
                    color: appNavy,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _VolunteerActionCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'Request help',
                        onTap: _openRequestHelp,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _VolunteerActionCard(
                        icon: Icons.people_outline_rounded,
                        label: 'Request assistance',
                        onTap: _openRequestAssistance,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _VolunteerActionCard(
                        icon: Icons.favorite_border_rounded,
                        label: 'Donate resources',
                        onTap: _openDonateResources,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Opportunities near you',
                        style: TextStyle(
                          color: appNavy,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openExplore(context),
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 36),
                      ),
                      child: const Text('View map'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadError != null) ...[
                  _DashboardMessage(
                    message: _loadError!,
                    onRetry: _loadDashboard,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_loading && _nearbyRequests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_nearbyRequests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No nearby requests right now.',
                      style: TextStyle(color: appMuted, fontSize: 13),
                    ),
                  )
                else
                  Container(
                    height: 360,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE0E6EC)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _nearbyRequests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final request = _nearbyRequests[index];
                        return _OpportunityCard(
                          request: request,
                          onJoin: _joinRequest(request),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                if (widget.account.roles.isNotEmpty)
                  Text(
                    'Your roles: ${widget.account.roles.join(' · ')}',
                    style: const TextStyle(color: appMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: _VolunteerNavigationBar(
            selectedIndex: 0,
            onHome: () {},
            onExplore: () => _openExplore(context),
            onRequests: () => _openRequests(context),
            onProfile: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VolunteerProfileScreen(account: widget.account),
              ),
            ),
          ),
        ),
      );
}

class _NextMissionCard extends StatelessWidget {
  const _NextMissionCard({
    required this.offer,
    required this.loading,
    required this.onTap,
    required this.buttonLabel,
  });

  final Map<String, dynamic>? offer;
  final bool loading;
  final VoidCallback onTap;
  final String buttonLabel;

  String _assignmentTitle() => switch ('${offer?['assignment_type'] ?? ''}') {
        'delivery' => 'Deliver essential supplies.',
        'pickup' => 'Collect a community donation.',
        'healthcare' => 'Provide health support.',
        'transport' => 'Help transport supplies.',
        'manpower' => 'Support your community.',
        _ => 'Your help can make a difference.',
      };

  String _assignmentDetails() {
    if (offer == null) {
      return loading
          ? 'Loading opportunities…'
          : 'New opportunities will appear here when a request matches your roles.';
    }
    final district = '${offer!['district'] ?? 'Nearby community'}';
    final items = (offer!['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => '${item['qty'] ?? ''} ${item['unit'] ?? ''}'.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return [if (items.isNotEmpty) items, district].join(' · ');
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appNavy,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: appGold, size: 19),
                const SizedBox(width: 9),
                Text(
                  offer == null ? 'YOUR VOLUNTEER HUB' : 'MATCHED OPPORTUNITY',
                  style: const TextStyle(
                    color: appGold,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              offer == null
                  ? 'Ready to help?\nWe’ll find a match.'
                  : _assignmentTitle(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _assignmentDetails(),
              style: const TextStyle(
                color: Color(0xFFD1DDE5),
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onTap,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                label:
                    Text(loading && offer == null ? 'Loading…' : buttonLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: appGold,
                  foregroundColor: appNavy,
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
      );
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7DF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: appNavy, fontSize: 12),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _VolunteerActionCard extends StatelessWidget {
  const _VolunteerActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 88,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: appTeal, size: 24),
                const SizedBox(height: 9),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 10,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.request, required this.onJoin});

  final Map<String, dynamic> request;
  final VoidCallback onJoin;

  List<String> get _itemTypes => (request['item_types'] as List? ?? const [])
      .map((item) => '$item')
      .toList();

  String get _title {
    final kind = '${request['kind'] ?? ''}';
    if (kind == 'donation_offer') return 'Community resources offered';
    final items = _itemTypes;
    if (kind.endsWith('_request') && items.isEmpty) {
      final label = switch (kind) {
        'healthcare_request' => 'Health worker support',
        'transport_request' => 'Transport manpower',
        'manpower_request' => 'Human manpower',
        _ => 'Community support',
      };
      return '$label needed';
    }
    if (items.length > 1) return 'Multiple resource needs';
    return items.isEmpty
        ? 'Community support needed'
        : '${_itemTypeLabel(items.first)} needed';
  }

  String get _details {
    final kind = '${request['kind'] ?? ''}';
    final items = _itemTypes;
    final category = switch (kind) {
      'healthcare_request' => 'Health worker support',
      'transport_request' => 'Transport manpower',
      'manpower_request' => 'Human manpower',
      'donation_offer' => 'Community donation',
      _ => items.length > 1
          ? 'Multiple resource types'
          : items.isEmpty
              ? 'Community request'
              : '${_itemTypeLabel(items.first)} only',
    };
    final distance = request['distance_km'];
    final distanceLabel = distance is num
        ? '${distance.toDouble().toStringAsFixed(1)} km away'
        : 'Nearby';
    return '$category · $distanceLabel';
  }

  String _itemTypeLabel(String type) => switch (type) {
        'food' => 'Food',
        'drinking_water' => 'Drinking water',
        'medical_supplies' => 'Medicine',
        'cloth' => 'Clothing',
        'temp_shelter' => 'Temporary shelter',
        _ => type.replaceAll('_', ' '),
      };

  String get _status {
    return switch ('${request['layer'] ?? ''}') {
      'fulfilled' => 'Request closed',
      'pickup' || 'donation' => 'Help on the way',
      _ => 'Currently needed',
    };
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onJoin,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE0E6EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A183D58),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: appTeal, size: 17),
                    const SizedBox(width: 8),
                    const Text(
                      'NEARBY REQUEST',
                      style: TextStyle(
                        color: appTeal,
                        fontSize: 9,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _status,
                      style: const TextStyle(color: appNavy, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  _title,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _details,
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: appMuted, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Approximate request location',
                        style: const TextStyle(color: appMuted, fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onJoin,
                      icon: const Icon(Icons.volunteer_activism_outlined,
                          size: 16),
                      label: const Text('Join now'),
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _VolunteerNavigationBar extends StatelessWidget {
  const _VolunteerNavigationBar({
    required this.selectedIndex,
    required this.onHome,
    required this.onExplore,
    required this.onRequests,
    required this.onProfile,
  });

  final int selectedIndex;
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
                _NavItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  selected: selectedIndex == 0,
                  onTap: onHome,
                ),
                _NavItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  selected: selectedIndex == 1,
                  onTap: onExplore,
                ),
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: selectedIndex == 2,
                  onTap: onRequests,
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: selectedIndex == 3,
                  onTap: onProfile,
                ),
              ],
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 30,
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFE8F0F4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: appNavy, size: 21),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: appNavy,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
}
