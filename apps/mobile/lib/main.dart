import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  // TODO(Person 4): Firebase.initializeApp() + FCM token registration after adding google-services.json (never commit it).
  runApp(const ProviderScope(child: SahayogiApp()));
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
  // Person 1: add routes under features/ — public_intake, volunteer, map, tracking.
]);

class SahayogiApp extends StatelessWidget {
  const SahayogiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Sahayogi Nepal',
        theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
        routerConfig: _router,
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sahayogi Nepal')),
        body: ListView(padding: const EdgeInsets.all(16), children: const [
          ListTile(title: Text('Request help'), subtitle: Text('TODO: public_intake')),
          ListTile(title: Text('Offer a donation'), subtitle: Text('TODO: public_intake')),
          ListTile(title: Text('Volunteer login / apply'), subtitle: Text('TODO: volunteer')),
          ListTile(title: Text('Map'), subtitle: Text('TODO: map')),
          ListTile(title: Text('Track my request'), subtitle: Text('TODO: tracking')),
        ]),
      );
}
