import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/saved_volunteer_application.dart';
import '../core/volunteer_auth_service.dart';
import 'volunteer_login_screen.dart';
import 'volunteer_registration_screen.dart';

class VolunteerApplicationStatusScreen extends StatefulWidget {
  const VolunteerApplicationStatusScreen({
    super.key,
    required this.application,
    required this.name,
    required this.email,
    required this.phone,
    required this.roles,
  });

  final VolunteerApplicationSubmission application;
  final String name;
  final String email;
  final String phone;
  final List<String> roles;

  @override
  State<VolunteerApplicationStatusScreen> createState() =>
      _VolunteerApplicationStatusScreenState();
}

class _VolunteerApplicationStatusScreenState
    extends State<VolunteerApplicationStatusScreen> {
  Timer? _pollTimer;
  late String _status;
  bool _isRefreshing = false;
  String? _error;

  bool get _isApproved =>
      const {'approved', 'accepted'}.contains(_status.toLowerCase());
  bool get _isRejected =>
      const {'declined', 'rejected'}.contains(_status.toLowerCase());

  @override
  void initState() {
    super.initState();
    _status = widget.application.status;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
    _pollTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) {
        if (!_isApproved && !_isRejected) _refreshStatus();
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (_isRefreshing || !mounted) return;
    setState(() {
      _isRefreshing = true;
      _error = null;
    });
    try {
      final status = await VolunteerAuthService.viewVolunteerApplication(
        applicationId: widget.application.applicationId,
      );
      if (!mounted) return;
      setState(() => _status = status);
      await SavedVolunteerApplication.updateStatus(status);
      if (_isApproved || _isRejected) _pollTimer?.cancel();
    } on VolunteerAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not refresh your application status.');
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _signUpAgain() async {
    await SavedVolunteerApplication.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const VolunteerRegistrationScreen(),
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const VolunteerLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isRejected
        ? 'Application not approved'
        : _isApproved
            ? 'Application approved'
            : 'Application pending';
    final description = _isRejected
        ? 'Your application was not approved. You can update your details and submit a new application.'
        : _isApproved
            ? 'We sent a secure password setup link to ${widget.email}. Create and confirm your password from that link, then log in to open your volunteer dashboard.'
            : 'Your application has been sent to the admin team. We will keep checking for a decision.';

    return Scaffold(
      backgroundColor: appPaper,
      appBar: AppBar(
        backgroundColor: appPaper,
        foregroundColor: appNavy,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Application status',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: (_isRejected
                          ? const Color(0xFFC74747)
                          : _isApproved
                              ? const Color(0xFF159B55)
                              : appGold)
                      .withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRejected
                      ? Icons.cancel_outlined
                      : _isApproved
                          ? Icons.verified_rounded
                          : Icons.hourglass_top_rounded,
                  color: _isRejected
                      ? const Color(0xFFC74747)
                      : _isApproved
                          ? const Color(0xFF159B55)
                          : appNavy,
                  size: 38,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: appNavy,
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0E6EC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REQUEST STATUS',
                      style: TextStyle(
                        color: appMuted,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          _isRejected
                              ? Icons.cancel_rounded
                              : _isApproved
                                  ? Icons.check_circle_rounded
                                  : Icons.pending_rounded,
                          color: _isRejected
                              ? const Color(0xFFC74747)
                              : _isApproved
                                  ? const Color(0xFF159B55)
                                  : appGold,
                          size: 21,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _status.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                              color: appNavy,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isRefreshing)
                          const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (!_isRejected && !_isApproved)
                          IconButton(
                            tooltip: 'Refresh status',
                            onPressed: _refreshStatus,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: appTeal,
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      'Application reference: ${widget.application.applicationId}',
                      style: const TextStyle(color: appMuted, fontSize: 11),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFC74747),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (_isRejected)
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _signUpAgain,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    label: const Text('Sign up again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              if (!_isRejected && !_isApproved)
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isRefreshing ? null : _refreshStatus,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: appNavy,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE0E6EC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text('Check status'),
                  ),
                ),
              if (_isApproved)
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _goToLogin,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    label: const Text('Go to log in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
