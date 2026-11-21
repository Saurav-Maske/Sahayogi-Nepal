import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';
import '../widgets/onboarding_illustration.dart';
import 'home_screen.dart';

class _OnboardingPage {
  const _OnboardingPage(this.title, this.description, this.scene);

  final String title;
  final String description;
  final int scene;
}

const _pages = [
  _OnboardingPage(
    'Help is closer\nthan you think.',
    'Request essentials for yourself or your\ncommunity. The right support starts here.',
    0,
  ),
  _OnboardingPage(
    'Small acts.\nExtraordinary impact.',
    'Connect with local donors, volunteers and\norganizations ready to lend a hand.',
    1,
  ),
  _OnboardingPage(
    'Every resource.\nEvery step. Visible.',
    'Follow your request from first match to safe\ndelivery. Trust built into every update.',
    2,
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxHeight < 760;

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sahayogi',
                        style: TextStyle(
                          color: appNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(foregroundColor: appTeal),
                        child: const Text(
                          'Skip',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 18 : 34),
                  Expanded(
                    flex: 12,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 360,
                          maxHeight: 310,
                        ),
                        child: OnboardingIllustration(scene: page.scene),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 28),
                  Text(
                    '${(_index + 1).toString().padLeft(2, '0')} / 03',
                    style: const TextStyle(
                      color: appTeal,
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    page.title,
                    style: const TextStyle(
                      color: appNavy,
                      fontSize: 30,
                      height: 1.17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 19),
                  Text(
                    page.description,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 15,
                      height: 1.48,
                    ),
                  ),
                  const SizedBox(height: 27),
                  Row(
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _index ? 26 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color:
                              i == _index ? appNavy : const Color(0xFFCCD6DF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: _index == 2 ? appGold : appNavy,
                        foregroundColor: _index == 2 ? appNavy : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: _index == 2 ? 2 : 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _index == 2 ? 'Get started' : 'Continue',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 18),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
