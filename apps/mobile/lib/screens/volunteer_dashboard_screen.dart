import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import 'assigned_task_screen.dart';
import 'explore_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_profile_screen.dart';

class VolunteerDashboardScreen extends StatelessWidget {
  const VolunteerDashboardScreen({
    super.key,
    required this.account,
  });

  final VolunteerAccount account;

  void _openAssignedTask(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AssignedTaskScreen(),
        ),
      );

  void _openExplore(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
      );

  void _openRequests(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MyRequestsScreen()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
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
                '${account.name} · Kathmandu volunteer',
                style: const TextStyle(color: appMuted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              _NextMissionCard(onTap: () => _openAssignedTask(context)),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(child: _StatTile(value: '1', label: 'Assigned')),
                  SizedBox(width: 10),
                  Expanded(child: _StatTile(value: '2', label: 'Accepted')),
                  SizedBox(width: 10),
                  Expanded(child: _StatTile(value: '18', label: 'Completed')),
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
              _OpportunityCard(onTap: () => _openAssignedTask(context)),
              const SizedBox(height: 14),
              if (account.roles.isNotEmpty)
                Text(
                  'Your roles: ${account.roles.join(' · ')}',
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
              builder: (_) => VolunteerProfileScreen(account: account),
            ),
          ),
        ),
      );
}

class _NextMissionCard extends StatelessWidget {
  const _NextMissionCard({required this.onTap});

  final VoidCallback onTap;

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
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: appGold, size: 19),
                SizedBox(width: 9),
                Text(
                  'YOUR NEXT MISSION',
                  style: TextStyle(
                    color: appGold,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Deliver warmth.\nBring peace of mind.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '30 blankets · 6 families in Chabahil\nPickup: Baluwatar relief hub · 10:00',
              style: TextStyle(
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
                label: const Text('View assigned task'),
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
  const _OpportunityCard({required this.onTap});

  final VoidCallback onTap;

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
                const Text(
                  'Pack essential food kits',
                  style: TextStyle(
                    color: appNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '2 volunteers · Baluwatar, Kathmandu',
                  style: TextStyle(color: appMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: appMuted, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '0.8 km away · Today, 11:00–14:00',
                        style: TextStyle(color: appMuted, fontSize: 11),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: appNavy),
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
