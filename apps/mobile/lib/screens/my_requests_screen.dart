import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../models/request_summary.dart';
import 'explore_screen.dart';
import 'request_tracking_screen.dart';
import 'volunteer_login_screen.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  static const _records = <RequestSummaryData>[
    RequestSummaryData(
      id: 'SN-2048',
      title: 'Drinking water for 24 people',
      trackingTitle: 'Drinking water',
      amountAndLocation: '60 litres · Melamchi, Sindhupalchok',
      requestSummary: '60 litres · 24 people',
      location: 'Melamchi, Sindhupalchok',
      submittedAt: '20 Nov 2026, 08:40 NPT',
      referenceLine: 'Submitted 20 Nov, 08:40',
      status: 'In progress',
    ),
    RequestSummaryData(
      id: 'SN-2054',
      title: 'First-aid supplies for 8 people',
      trackingTitle: 'First-aid supplies',
      amountAndLocation: '8 first-aid kits · Melamchi, Sindhupalchok',
      requestSummary: '8 kits · 8 people',
      location: 'Melamchi, Sindhupalchok',
      submittedAt: '20 Nov 2026, 09:41 NPT',
      referenceLine: 'Submitted 20 Nov, 09:41',
      status: 'Pending',
    ),
    RequestSummaryData(
      id: 'SN-2031',
      title: 'Family food kits for 6 families',
      trackingTitle: 'Family food kits',
      amountAndLocation: '6 kits · Melamchi, Sindhupalchok',
      requestSummary: '6 kits · 6 families',
      location: 'Melamchi, Sindhupalchok',
      submittedAt: '19 Nov 2026, 10:15 NPT',
      referenceLine: 'Delivered 19 Nov, 16:30',
      status: 'Fulfilled',
    ),
    RequestSummaryData(
      id: 'SD-3012',
      title: 'Winter blankets for 12 families',
      trackingTitle: 'Winter blankets',
      amountAndLocation: '12 blankets · Pickup, Balaju',
      requestSummary: '12 blankets · 12 families',
      location: 'Balaju, Kathmandu',
      submittedAt: '21 Nov 2026, 08:20 NPT',
      referenceLine: 'Pickup scheduled 22 Nov, 11:00',
      status: 'In progress',
      isDonation: true,
    ),
    RequestSummaryData(
      id: 'SD-3008',
      title: 'Family food kits for 10 families',
      trackingTitle: 'Family food kits',
      amountAndLocation: '10 food kits · Pickup, Boudha',
      requestSummary: '10 kits · 10 families',
      location: 'Boudha, Kathmandu',
      submittedAt: '19 Nov 2026, 09:10 NPT',
      referenceLine: 'Received 20 Nov, 15:35',
      status: 'Fulfilled',
      isDonation: true,
    ),
  ];

  String _selectedFilter = 'All';

  List<RequestSummaryData> get _visibleRequests => switch (_selectedFilter) {
        'Active' =>
          _records.where((request) => request.status == 'In progress').toList(),
        'Fulfilled' =>
          _records.where((request) => request.status == 'Fulfilled').toList(),
        _ => _records,
      };

  void _openExplore() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
      );

  void _showRequest(RequestSummaryData request) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestTrackingScreen(request: request),
      ),
    );
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
                          _filterChip(
                            'Active',
                            _records
                                .where((request) =>
                                    request.status == 'In progress')
                                .length,
                          ),
                          const SizedBox(width: 8),
                          _filterChip(
                            'Fulfilled',
                            _records
                                .where(
                                    (request) => request.status == 'Fulfilled')
                                .length,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_visibleRequests.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No requests in this category.',
                            style: TextStyle(color: appMuted, fontSize: 14),
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
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onExplore: _openExplore,
          onProfile: () => openVolunteerLogin(context),
        ),
      );

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
                  label: 'Profile',
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
