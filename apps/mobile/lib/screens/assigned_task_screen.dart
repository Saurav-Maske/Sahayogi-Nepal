import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import 'explore_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_login_screen.dart';

class AssignedTaskScreen extends StatelessWidget {
  const AssignedTaskScreen({super.key});

  static const _pickup = LatLng(27.7206, 85.3302);
  static const _delivery = LatLng(27.7175, 85.3488);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: const Text(
            'Assigned task',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 24),
              child: Icon(Icons.verified_user_outlined, color: appTeal),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0F4),
                    border: Border.all(color: appNavy),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Text(
                    'Accepted · Pickup at 10:00',
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'A little warmth.\nA big difference.',
                style: TextStyle(
                  color: appNavy,
                  fontSize: 27,
                  height: 1.18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              _TaskCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VT-0142 · Blanket delivery',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '30 blankets for 6 families',
                      style: TextStyle(color: appTeal, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Coordinator: Aasha Tamang\n+977 9800 112 233',
                      style: TextStyle(
                        color: appMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _TaskCard(
                child: Column(
                  children: const [
                    _StopRow(
                      icon: Icons.inventory_2_outlined,
                      number: '01',
                      title: 'Pick up supplies',
                      details: 'Baluwatar community relief hub\nToday, 10:00 NPT',
                    ),
                    SizedBox(height: 21),
                    _StopRow(
                      icon: Icons.location_on_outlined,
                      number: '02',
                      title: 'Deliver to families',
                      details:
                          'Chabahil, Ward 7, Kathmandu\n2.4 km · Approx. 15 min',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 64),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _AssignedTaskMapScreen(
                        pickup: _pickup,
                        delivery: _delivery,
                      ),
                    ),
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: const Text('View area on map'),
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
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _showCoordinator(context),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: const Text('Contact coordinator'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: appNavy,
                    side: const BorderSide(color: Color(0xFFE0E6EC)),
                    backgroundColor: Colors.white,
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
        bottomNavigationBar: _TaskNavigationBar(
          onHome: () => Navigator.of(context).pop(),
          onExplore: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
          ),
          onRequests: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyRequestsScreen()),
          ),
          onProfile: () => openVolunteerLogin(context),
        ),
      );

  void _showCoordinator(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact coordinator'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aasha Tamang'),
            SizedBox(height: 7),
            SelectableText('+977 9800 112 233'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: child,
      );
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.icon,
    required this.number,
    required this.title,
    required this.details,
  });

  final IconData icon;
  final String number;
  final String title;
  final String details;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: appTeal, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$number  ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: const TextStyle(color: appNavy, fontSize: 13),
                ),
                const SizedBox(height: 5),
                Text(
                  details,
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _AssignedTaskMapScreen extends StatelessWidget {
  const _AssignedTaskMapScreen({required this.pickup, required this.delivery});

  final LatLng pickup;
  final LatLng delivery;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (pickup.latitude + delivery.latitude) / 2,
      (pickup.longitude + delivery.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task route'),
        backgroundColor: appPaper,
        foregroundColor: appNavy,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.2,
              minZoom: 5,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'np.sahayogi.sahayogi_mobile',
                maxZoom: 19,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [pickup, delivery],
                    color: appTeal,
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pickup,
                    width: 52,
                    height: 58,
                    child: const _RouteMarker(
                      number: '1',
                      icon: Icons.inventory_2_rounded,
                      color: appNavy,
                    ),
                  ),
                  Marker(
                    point: delivery,
                    width: 52,
                    height: 58,
                    child: const _RouteMarker(
                      number: '2',
                      icon: Icons.home_rounded,
                      color: appTeal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(color: appMuted, fontSize: 10),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _TaskCard(
              child: const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: appNavy),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Baluwatar pickup  →  Chabahil delivery\n2.4 km · Approx. 15 min',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
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
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({
    required this.number,
    required this.icon,
    required this.color,
  });

  final String number;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x33183D58), blurRadius: 6),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
}

class _TaskNavigationBar extends StatelessWidget {
  const _TaskNavigationBar({
    required this.onHome,
    required this.onExplore,
    required this.onRequests,
    required this.onProfile,
  });

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
                _TaskNavItem(
                    icon: Icons.home_outlined, label: 'Home', onTap: onHome),
                _TaskNavItem(
                    icon: Icons.map_outlined, label: 'Explore', onTap: onExplore),
                _TaskNavItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Requests',
                    onTap: onRequests,
                    selected: true),
                _TaskNavItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onTap: onProfile),
              ],
            ),
          ),
        ),
      );
}

class _TaskNavItem extends StatelessWidget {
  const _TaskNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

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
                  borderRadius: BorderRadius.circular(18),
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
