import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import '../core/request_submission.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'volunteer_dashboard_screen.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _continueAfterSplash();
  }

  Future<void> _continueAfterSplash() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    Widget destination = prefs.getBool('onboarding_complete') == true
        ? const HomeScreen()
        : const OnboardingScreen();
    if (prefs.getBool('onboarding_complete') == true &&
        VolunteerAuthService.hasSession) {
      try {
        final account = await VolunteerAuthService.currentVolunteer();
        await clearSavedRequests();
        destination = VolunteerDashboardScreen(account: account);
      } catch (_) {
        await VolunteerAuthService.signOut();
        await clearSavedRequests();
        destination = const HomeScreen();
      }
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appNavy,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 82,
                  height: 82,
                  child: Image.asset(
                    'assets/images/SahayogiNepalLogo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 53),
                const Text(
                  'Sahayogi\nNepal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 26),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: appGold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
