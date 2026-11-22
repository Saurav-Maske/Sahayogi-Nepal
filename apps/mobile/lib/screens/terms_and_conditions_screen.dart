import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        appBar: AppBar(
          backgroundColor: appPaper,
          foregroundColor: appNavy,
          elevation: 0,
          title: const Text('Terms and Conditions'),
        ),
        body: SafeArea(
          child: FutureBuilder<String>(
            future: DefaultAssetBundle.of(context)
                .loadString('assets/terms_and_conditions.txt'),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load the terms and conditions.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: SelectableText(
                  snapshot.data!,
                  style: const TextStyle(
                    color: appNavy,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              );
            },
          ),
        ),
      );
}
