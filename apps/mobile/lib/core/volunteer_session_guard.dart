import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'volunteer_auth_service.dart';

class VolunteerSessionGuard extends StatefulWidget {
  const VolunteerSessionGuard({
    super.key,
    required this.child,
    required this.onUnauthorized,
  });

  final Widget child;
  final Future<void> Function() onUnauthorized;

  @override
  State<VolunteerSessionGuard> createState() => _VolunteerSessionGuardState();
}

class _VolunteerSessionGuardState extends State<VolunteerSessionGuard> {
  bool _checking = true;
  bool _redirecting = false;
  StreamSubscription<AuthState>? _authChanges;

  @override
  void initState() {
    super.initState();
    _authChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) _redirect();
      },
    );
    _validateSession();
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    super.dispose();
  }

  Future<void> _validateSession() async {
    if (!VolunteerAuthService.hasSession) {
      _redirect();
      return;
    }
    try {
      await VolunteerAuthService.currentVolunteer();
      if (mounted) setState(() => _checking = false);
    } catch (_) {
      _redirect();
    }
  }

  void _redirect() {
    if (_redirecting || !mounted) return;
    _redirecting = true;
    setState(() => _checking = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.onUnauthorized());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _redirecting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
