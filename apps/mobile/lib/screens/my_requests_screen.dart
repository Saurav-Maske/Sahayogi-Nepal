import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/app_home_navigation.dart';
import '../core/request_submission.dart';
import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import '../core/volunteer_session_guard.dart';
import '../models/request_summary.dart';
import 'explore_screen.dart';
import 'request_tracking_screen.dart';
import 'volunteer_login_screen.dart';

class MyRequestsScreen extends StatefulWidget {
  MyRequestsScreen({super.key, bool? requireVolunteerSession})
      : requireVolunteerSession =
            requireVolunteerSession ?? VolunteerAuthService.hasSession;

  final bool requireVolunteerSession;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<RequestSummaryData> _records = [];
  bool _loading = true;

  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    var saved = await loadSavedRequests();
    if (VolunteerAuthService.hasSession) {
      final localByReference = {
        for (final record in saved)
          if (record['public_ref'] is String) record['public_ref']: record,
      };
      final history = await Api.getVolunteerRequestHistory();
      if (history.ok && history.data != null) {
        saved = history.data!.map((record) {
          final local = localByReference[record['public_ref']];
          return {
            ...record,
            if (local?['tracking_token'] is String)
              'tracking_token': local!['tracking_token'],
          };
        }).toList();
      }
    }
    if (!mounted) return;
    setState(() {
      _records = saved.map(RequestSummaryData.fromSavedSubmission).toList();
      _loading = false;
    });

    final trackable = saved
        .where((record) =>
            record['public_ref'] is String &&
            record['tracking_token'] is String &&
            (record['tracking_token'] as String).isNotEmpty)
        .take(20)
        .toList();
    final results = await Future.wait(
      trackable.map((record) => Api.getRequestTracking(
            reference: record['public_ref'] as String,
            token: record['tracking_token'] as String,
          )),
    );
    final updatedStatuses = <String, String>{};
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final status = result.data?['status'];
      if (result.ok && status is String && status.isNotEmpty) {
        updatedStatuses[trackable[index]['public_ref'] as String] = status;
      }
    }
    if (updatedStatuses.isEmpty) return;
    await updateSavedRequestStatuses(updatedStatuses);
    if (!mounted) return;
    setState(() {
      _records = saved.map((record) {
        final status = updatedStatuses[record['public_ref']];
        return RequestSummaryData.fromSavedSubmission({
          ...record,
          if (status != null) 'status': status,
        });
      }).toList();
    });
  }

  bool _isActive(RequestSummaryData request) =>
      !{'Fulfilled', 'Declined', 'Cancelled'}.contains(request.status);

  List<RequestSummaryData> get _visibleRequests => switch (_selectedFilter) {
        'Active' => _records.where(_isActive).toList(),
        'Fulfilled' =>
          _records.where((request) => request.status == 'Fulfilled').toList(),
        _ => _records,
      };

  void _openExplore() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExploreScreen(
            requireVolunteerSession: widget.requireVolunteerSession,
          ),
        ),
      );

  Future<void> _showRequest(RequestSummaryData request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestTrackingScreen(request: request),
      ),
    );
    await _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
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
                  const Expanded(
                    child: Text(
                      'My Requests',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _loadRequests,
                    tooltip: 'Refresh requests',
                    icon: const Icon(Icons.refresh_rounded, color: appTeal),
                  ),
                  const Icon(
                    Icons.verified_user_outlined,
                    color: appTeal,
                    size: 20,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                children: [
                  const Text(
                    'Support, every step.',
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', _records.length),
                        const SizedBox(width: 8),
                        _filterChip('Active', _records.where(_isActive).length),
                        const SizedBox(width: 8),
                        _filterChip(
                          'Fulfilled',
                          _records
                              .where((request) => request.status == 'Fulfilled')
                              .length,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_visibleRequests.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          _records.isEmpty
                              ? 'Requests you submit from this device will appear here.'
                              : 'No requests in this category.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: appMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._visibleRequests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _RequestCard(
                          request: request,
                          onTap: () => _showRequest(request),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _RequestsNavigationBar(
        onHome: () => openRoleAwareHome(context),
        onExplore: _openExplore,
        onProfile: () => openVolunteerLogin(context),
      ),
    );
    if (!widget.requireVolunteerSession) return screen;
    return VolunteerSessionGuard(
      onUnauthorized: () => openVolunteerLogin(context),
      child: screen,
    );
  }

  Widget _filterChip(String label, int count) {
    final selected = _selectedFilter == label;
    return ChoiceChip(
      label: Text('$label $count'),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = label),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: appNavy,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE7F0F4),
      side: BorderSide(
        color: selected ? appNavy : const Color(0xFFE0E6EC),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 1),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});

  final RequestSummaryData request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 15, 13, 13),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E6EC)),
              borderRadius: BorderRadius.circular(17),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x080F3045),
                  blurRadius: 9,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      request.isDonation
                          ? Icons.volunteer_activism_outlined
                          : Icons.inventory_2_outlined,
                      size: 18,
                      color: appTeal,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      request.isDonation ? 'YOUR DONATION' : 'YOUR REQUEST',
                      style: const TextStyle(
                        color: appTeal,
                        fontSize: 9,
                        letterSpacing: .25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      request.status,
                      style: TextStyle(
                        color: request.statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  request.title,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  request.amountAndLocation,
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: appMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        request.reference,
                        style: const TextStyle(color: appMuted, fontSize: 10),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: appNavy,
                      size: 21,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _RequestsNavigationBar extends StatelessWidget {
  const _RequestsNavigationBar({
    required this.onHome,
    required this.onExplore,
    required this.onProfile,
  });

  final VoidCallback onHome;
  final VoidCallback onExplore;
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
                _RequestsNavigationItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: onHome,
                ),
                _RequestsNavigationItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  onTap: onExplore,
                ),
                const _RequestsNavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: true,
                ),
                _RequestsNavigationItem(
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

class _RequestsNavigationItem extends StatelessWidget {
  const _RequestsNavigationItem({
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
