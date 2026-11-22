import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import '../core/volunteer_session_guard.dart';
import 'explore_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_login_screen.dart';

class VolunteerProfileScreen extends StatefulWidget {
  const VolunteerProfileScreen({
    super.key,
    required this.account,
  });

  final VolunteerAccount account;

  @override
  State<VolunteerProfileScreen> createState() => _VolunteerProfileScreenState();
}

class _VolunteerProfileScreenState extends State<VolunteerProfileScreen> {
  bool _isLoggingOut = false;
  late VolunteerAccount _account;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    try {
      final account = await VolunteerAuthService.currentVolunteer();
      if (mounted) setState(() => _account = account);
    } catch (_) {
      // Keep the profile returned at login if the refresh is unavailable.
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await VolunteerAuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const VolunteerLoginScreen(),
        ),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => VolunteerSessionGuard(
        onUnauthorized: () => openVolunteerLogin(context),
        child: Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: const Text(
            'Volunteer profile',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh profile',
              onPressed: _refreshProfile,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Center(
              child: CircleAvatar(
                radius: 38,
                backgroundColor: appNavy,
                child: Text(
                  _account.name.isEmpty
                      ? 'V'
                      : _account.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _account.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: appNavy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Verified volunteer',
              textAlign: TextAlign.center,
              style: TextStyle(color: appMuted, fontSize: 13),
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE0E6EC)),
              ),
              child: Column(
                children: [
                  _ProfileDetail(
                    icon: Icons.person_outline_rounded,
                    label: 'Full name',
                    value: _account.name,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.email_outlined,
                    label: 'Email address',
                    value: _account.email,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.phone_outlined,
                    label: 'Phone number',
                    value: _account.phone.isEmpty
                        ? 'Not provided'
                        : _account.phone,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.volunteer_activism_outlined,
                    label: 'Volunteer roles',
                    value: _account.roles.join(', '),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isLoggingOut ? null : _logout,
                icon: _isLoggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(_isLoggingOut ? 'Logging out…' : 'Log out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                  side: const BorderSide(color: Color(0xFFE5A6A2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _VolunteerNavBar(
          onHome: () => Navigator.of(context).pop(),
          onExplore: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExploreScreen(requireVolunteerSession: true),
              ),
            );
          },
          onRequests: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MyRequestsScreen(requireVolunteerSession: true),
              ),
            );
          },
        ),
        ),
      );
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: appTeal, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: appMuted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? 'Not provided' : value,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _VolunteerNavBar extends StatelessWidget {
  const _VolunteerNavBar({
    required this.onHome,
    required this.onExplore,
    required this.onRequests,
  });

  final VoidCallback onHome;
  final VoidCallback onExplore;
  final VoidCallback onRequests;

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
                  selected: false,
                  onTap: onHome,
                ),
                _NavItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  selected: false,
                  onTap: onExplore,
                ),
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: false,
                  onTap: onRequests,
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: true,
                  onTap: () {},
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
              Icon(
                icon,
                color: selected ? appNavy : appMuted,
                size: 23,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? appNavy : appMuted,
                  fontSize: 10,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
}