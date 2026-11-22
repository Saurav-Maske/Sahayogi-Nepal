import 'dart:convert';

import 'package:material_ui/material_ui.dart';
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
  List<Map<String, dynamic>> _offers = const [];
  Map<String, dynamic> _stats = const {};
  Map<String, dynamic>? _activeAssignment;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final results = await Future.wait([
      Api.getVolunteerOffers(),
      Api.getVolunteerStats(),
    ]);
    final preferences = await SharedPreferences.getInstance();
    final activeId = preferences.getString('volunteer_active_assignment_id');
    Map<String, dynamic>? cachedAssignment;
    final cachedJson = preferences.getString('volunteer_active_assignment');
    if (cachedJson != null) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map) {
          cachedAssignment = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        await preferences.remove('volunteer_active_assignment');
      }
    }
    final activeResult = activeId == null
        ? null
        : await Api.getVolunteerAssignment(activeId);
    if (!mounted) return;
    final offers = results[0] as ApiResult<List<Map<String, dynamic>>>;
    final stats = results[1] as ApiResult<Map<String, dynamic>>;
    setState(() {
      _loading = false;
      if (offers.ok && offers.data != null) _offers = offers.data!;
      if (stats.ok && stats.data != null) _stats = stats.data!;
      _activeAssignment = activeResult?.ok == true
          ? activeResult!.data
          : cachedAssignment;
      _loadError = !offers.ok
          ? offers.errorMessage
          : !stats.ok
              ? stats.errorMessage
              : null;
    });
  }

  Future<void> _openOffer(Map<String, dynamic> offer) async {
    final id = offer['id'];
    if (id is! String || id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VolunteerAssignmentScreen(
          assignmentId: id,
          initialOffer: offer,
        ),
      ),
    );
    if (mounted) _loadDashboard();
  }

  void _openExplore(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExploreScreen(requireVolunteerSession: true),
        ),
      );

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
              const Text(
                'Volunteer hub',
                style: TextStyle(
                  color: appNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
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
                '${widget.account.name} · Kathmandu volunteer',
                style: const TextStyle(color: appMuted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              _NextMissionCard(
                offer: _activeAssignment ?? (_offers.isEmpty ? null : _offers.first),
                loading: _loading,
                onTap: _activeAssignment != null
                    ? () => _openOffer(_activeAssignment!)
                    : _offers.isNotEmpty
                        ? () => _openOffer(_offers.first)
                        : _loadDashboard,
                buttonLabel: _activeAssignment != null
                    ? 'View assigned task'
                    : _offers.isEmpty
                        ? 'Refresh opportunities'
                        : 'View opportunity',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      value: _stat('claimed_total'),
                      label: 'Claimed',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(value: _stat('active'), label: 'Active'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      value: _stat('completed'),
                      label: 'Completed',
                    ),
                  ),
                ],
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
              if (_loading && _offers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_offers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No open volunteer opportunities right now.',
                    style: TextStyle(color: appMuted, fontSize: 13),
                  ),
                )
              else
                ..._offers.take(5).map(
                      (offer) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OpportunityCard(
                          offer: offer,
                          onTap: () => _openOffer(offer),
                        ),
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

  String _stat(String key) => '${_stats[key] ?? (_loading ? '—' : 0)}';
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
                const Icon(Icons.inventory_2_outlined, color: appGold, size: 19),
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
                label: Text(loading && offer == null ? 'Loading…' : buttonLabel),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 98,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E6EC)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: appTeal, size: 22),
                const SizedBox(height: 8),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        height: 89,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: appNavy,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(color: appMuted, fontSize: 11)),
          ],
        ),
      );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.offer, required this.onTap});

  final Map<String, dynamic> offer;
  final VoidCallback onTap;

  String get _title => switch ('${offer['assignment_type'] ?? ''}') {
        'delivery' => 'Deliver requested supplies',
        'pickup' => 'Pick up donated resources',
        'healthcare' => 'Provide health worker support',
        'transport' => 'Transport assistance needed',
        'manpower' => 'Human manpower needed',
        _ => 'Volunteer opportunity',
      };

  String get _details {
    final district = '${offer['district'] ?? 'Nearby area'}';
    final urgency = '${offer['urgency'] ?? 'normal'}';
    return '$district · ${urgency[0].toUpperCase()}${urgency.substring(1)} priority';
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
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
                const Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: appTeal, size: 17),
                    SizedBox(width: 8),
                    Text(
                      'VOLUNTEER OPPORTUNITY',
                      style: TextStyle(
                        color: appTeal,
                        fontSize: 9,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Open',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
                    const Icon(Icons.location_on_outlined, color: appMuted, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Offer ${offer['public_ref'] ?? ''} · Tap to review',
                        style: const TextStyle(color: appMuted, fontSize: 11),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: appNavy),
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
                  color: selected ? const Color(0xFFE8F0F4) : Colors.transparent,
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