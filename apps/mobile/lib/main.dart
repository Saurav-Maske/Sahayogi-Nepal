import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_colors.dart';
import 'core/config.dart';
import 'screens/startup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: SahayogiApp()));
}

class SahayogiApp extends StatelessWidget {
  const SahayogiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sahayogi Nepal',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: appPaper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: appNavy,
            primary: appNavy,
            surface: appPaper,
          ),
          fontFamily: 'Roboto',
        ),
        home: const StartupScreen(),
      );
}
