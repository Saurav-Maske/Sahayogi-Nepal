import 'package:material_ui/material_ui.dart';

import 'volunteer_auth_service.dart';
import 'request_submission.dart';
import '../screens/home_screen.dart';
import '../screens/volunteer_dashboard_screen.dart';

Future<void> openRoleAwareHome(BuildContext context) async {
  Widget destination = const HomeScreen();
  if (VolunteerAuthService.hasSession) {
    try {
      final account = VolunteerAuthService.lastKnownAccount ??
          await VolunteerAuthService.currentVolunteer();
      destination = VolunteerDashboardScreen(account: account);
    } catch (_) {
      await VolunteerAuthService.signOut();
      await clearSavedRequests();
      destination = const HomeScreen();
    }
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => destination),
    (_) => false,
  );
}
