import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';

class VolunteerDashboardScreen extends StatelessWidget {
  const VolunteerDashboardScreen({
    super.key,
    required this.volunteerName,
    required this.roles,
  });

  final String volunteerName;
  final List<String> roles;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            children: [
              SizedBox(
                height: 42,
                child: SvgPicture.asset(
                  'assets/images/HorizontalLogo.svg',
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                  semanticsLabel: 'Sahayogi Nepal',
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: appNavy,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.volunteer_activism_outlined,
                          color: appGold,
                          size: 19,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'VOLUNTEER DASHBOARD',
                          style: TextStyle(
                            color: appGold,
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome, $volunteerName.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your helping hand makes the community stronger.',
                      style: TextStyle(
                        color: Color(0xFFD1DDE5),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your volunteer roles',
                style: TextStyle(
                  color: appNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: roles
                    .map(
                      (role) => Chip(
                        avatar: const Icon(
                          Icons.check_circle_rounded,
                          color: appTeal,
                          size: 17,
                        ),
                        label: Text(role),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE0E6EC)),
                        labelStyle: const TextStyle(
                          color: appNavy,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0E6EC)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You’re ready to help',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Nearby volunteer opportunities and assignment updates will appear here.',
                      style: TextStyle(
                        color: appMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
