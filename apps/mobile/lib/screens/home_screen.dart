import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This section is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _brandHeader(),
                const SizedBox(height: 10),
                _supportBanner(),
                const SizedBox(height: 20),
                _quickActions(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _bottomNavigation(),
      );

  Widget _brandHeader() => Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: SvgPicture.asset(
                '../public/images/HorizontalLogo.svg',
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticsLabel: 'Sahayogi Nepal',
              ),
            ),
          ),
          IconButton(
            onPressed: _showComingSoon,
            tooltip: 'Notifications',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: appNavy,
                  size: 25,
                ),
                Positioned(
                  right: -1,
                  top: 1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: appGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _supportBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
        decoration: BoxDecoration(
          color: appNavy,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: appGold, size: 20),
                SizedBox(width: 10),
                Text(
                  'HERE WHEN YOU NEED US',
                  style: TextStyle(
                    color: appGold,
                    fontSize: 10,
                    letterSpacing: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'You’re not alone.\nLet’s find you support.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Food, water, medicine and a safer place.',
              style: TextStyle(
                color: Color(0xFFD1DDE5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _showComingSoon,
                style: FilledButton.styleFrom(
                  backgroundColor: appGold,
                  foregroundColor: appNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Request Help',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _quickActions() => Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.inventory_2_outlined,
              label: 'Request\nAssistance',
              onTap: _showComingSoon,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.favorite_border_rounded,
              label: 'Donate\nResources',
              onTap: _showComingSoon,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.people_outline_rounded,
              label: 'Become a\nVolunteer',
              onTap: _showComingSoon,
            ),
          ),
        ],
      );

  Widget _bottomNavigation() => Container(
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
                _NavigationItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                _NavigationItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
                _NavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: _selectedTab == 2,
                  onTap: () => setState(() => _selectedTab = 2),
                ),
                _NavigationItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: _selectedTab == 3,
                  onTap: () => setState(() => _selectedTab = 3),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
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
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 101,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E6EC)),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: appTeal, size: 24),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 27,
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFE7F0F4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: selected ? appNavy : appNavy,
                ),
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
