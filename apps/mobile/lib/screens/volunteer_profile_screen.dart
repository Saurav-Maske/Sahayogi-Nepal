import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';

class VolunteerProfileScreen extends StatelessWidget {
  const VolunteerProfileScreen({
    super.key,
    required this.account,
  });

  final VolunteerAccount account;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: const Text(
            'Volunteer profile',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Center(
              child: CircleAvatar(
                radius: 38,
                backgroundColor: appNavy,
                child: Text(
                  account.name.isEmpty
                      ? 'V'
                      : account.name.substring(0, 1).toUpperCase(),
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
              account.name,
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
                    value: account.name,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.email_outlined,
                    label: 'Email address',
                    value: account.email,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.phone_outlined,
                    label: 'Phone number',
                    value: account.phone.isEmpty ? 'Not provided' : account.phone,
                  ),
                  const Divider(height: 25),
                  _ProfileDetail(
                    icon: Icons.volunteer_activism_outlined,
                    label: 'Volunteer roles',
                    value: account.roles.join(', '),
                  ),
                ],
              ),
            ),
          ],
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
