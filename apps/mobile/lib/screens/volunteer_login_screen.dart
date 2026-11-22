import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/saved_volunteer_application.dart';
import '../core/volunteer_auth_service.dart';
import 'volunteer_dashboard_screen.dart';
import 'volunteer_application_status_screen.dart';
import 'volunteer_registration_screen.dart';

Future<void> openVolunteerLogin(BuildContext context) async {
  if (VolunteerAuthService.hasSession) {
    try {
      final account = await VolunteerAuthService.currentVolunteer();
      await SavedVolunteerApplication.clearForEmail(account.email);
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => VolunteerDashboardScreen(account: account),
        ),
        (_) => false,
      );
      return;
    } catch (_) {
      await VolunteerAuthService.signOut();
    }
  }
  final application = await SavedVolunteerApplication.load();
  if (!context.mounted) return;
  if (application != null) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => VolunteerApplicationStatusScreen(
          application: application.submission,
          name: application.name,
          email: application.email,
          phone: application.phone,
          roles: application.roles,
        ),
      ),
      (_) => false,
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const VolunteerLoginScreen(),
    ),
  );
}

class VolunteerLoginScreen extends StatefulWidget {
  const VolunteerLoginScreen({super.key});

  @override
  State<VolunteerLoginScreen> createState() => _VolunteerLoginScreenState();
}

class _VolunteerLoginScreenState extends State<VolunteerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isSigningIn = false;
  bool _isResettingPassword = false;
  String? _signInError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSigningIn = true;
      _signInError = null;
    });
    try {
      final account = await VolunteerAuthService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await SavedVolunteerApplication.clearForEmail(account.email);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => VolunteerDashboardScreen(account: account),
        ),
        (_) => false,
      );
    } on VolunteerAuthException catch (error) {
      if (mounted) setState(() => _signInError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _signInError = 'Unable to log in. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    setState(() => _isResettingPassword = true);
    try {
      await VolunteerAuthService.requestPasswordReset(email);
      if (!mounted) return;
      final resetToken = await _requestResetCode(email);
      if (resetToken == null || !mounted) return;
      final newPassword = await _requestNewPassword();
      if (newPassword == null || !mounted) return;
      await VolunteerAuthService.resetPassword(
        email: email,
        resetToken: resetToken,
        newPassword: newPassword,
      );
      if (mounted) {
        _passwordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated. You can now log in.'),
          ),
        );
      }
    } on VolunteerAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset the password.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResettingPassword = false);
    }
  }

  Future<String?> _requestResetCode(String email) async {
    final controller = TextEditingController();
    var verifying = false;
    var resendSeconds = 60;
    var resending = false;
    String? errorMessage;
    Timer? resendTimer;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            resendTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (resendSeconds == 0) {
                resendTimer?.cancel();
                resendTimer = null;
                return;
              }
              setDialogState(() => resendSeconds--);
            });
            return AlertDialog(
              title: const Text('Verify your email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the 6-digit code sent to $email.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setDialogState(() => errorMessage = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Verification code',
                      errorText: errorMessage,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: resendSeconds > 0 || resending
                          ? null
                          : () async {
                              setDialogState(() {
                                resending = true;
                                errorMessage = null;
                              });
                              try {
                                await VolunteerAuthService.requestPasswordReset(
                                    email);
                                setDialogState(() {
                                  resending = false;
                                  resendSeconds = 60;
                                  resendTimer = Timer.periodic(
                                      const Duration(seconds: 1), (_) {
                                    if (resendSeconds == 0) {
                                      resendTimer?.cancel();
                                      resendTimer = null;
                                      return;
                                    }
                                    setDialogState(() => resendSeconds--);
                                  });
                                });
                              } on VolunteerAuthException catch (error) {
                                setDialogState(() {
                                  resending = false;
                                  errorMessage = error.message;
                                });
                              } catch (_) {
                                setDialogState(() {
                                  resending = false;
                                  errorMessage = 'Could not resend the code.';
                                });
                              }
                            },
                      child: Text(
                        resending
                            ? 'Sending...'
                            : resendSeconds > 0
                                ? 'Resend code in ${resendSeconds}s'
                                : 'Resend code',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          if (controller.text.trim().length != 6) {
                            setDialogState(
                              () => errorMessage = 'Enter the 6-digit code.',
                            );
                            return;
                          }
                          setDialogState(() {
                            verifying = true;
                            errorMessage = null;
                          });
                          try {
                            final token = await VolunteerAuthService
                                .verifyPasswordResetOtp(
                              email: email,
                              code: controller.text,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(token);
                            }
                          } on VolunteerAuthException catch (error) {
                            setDialogState(() {
                              verifying = false;
                              errorMessage = error.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              verifying = false;
                              errorMessage = 'Could not verify the code.';
                            });
                          }
                        },
                  child: verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify code'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      resendTimer?.cancel();
      controller.dispose();
    }
  }

  Future<String?> _requestNewPassword() async {
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create a new password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText:
                        '10+ characters with upper, lower, number and symbol',
                    helperMaxLines: 2,
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.length < 10 || password.length > 128) {
                      return 'Use 10 to 128 characters';
                    }
                    if (!RegExp(r'[A-Z]').hasMatch(password) ||
                        !RegExp(r'[a-z]').hasMatch(password) ||
                        !RegExp(r'\d').hasMatch(password) ||
                        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
                      return 'Add uppercase, lowercase, number and symbol';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) => value != passwordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(passwordController.text);
                }
              },
              child: const Text('Update password'),
            ),
          ],
        ),
      );
    } finally {
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  void _openRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const VolunteerRegistrationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 40,
                        ),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: appNavy,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Volunteer login',
                        style: TextStyle(
                          color: appNavy,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: SvgPicture.asset(
                        'assets/images/SahayogiNepalLogo.svg',
                        semanticsLabel: 'Sahayogi Nepal logo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Welcome back,\nvolunteer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 30,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue helping your community.',
                    style: TextStyle(
                      color: appMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _loginField(
                    label: 'Email address',
                    hint: 'johndoe@email.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _loginField(
                    label: 'Password',
                    hint: 'Enter your password',
                    controller: _passwordController,
                    isPassword: true,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your password'
                        : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isResettingPassword ? null : _resetPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: _isResettingPassword
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Forgot password?',
                              style: TextStyle(fontSize: 12),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_signInError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _signInError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSigningIn ? null : _signIn,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: _isSigningIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Log in'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _openRegistration,
                          style: TextButton.styleFrom(
                            foregroundColor: appTeal,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Become a Volunteer',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _loginField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF263746),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 9),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: isPassword && !_passwordVisible,
            validator: validator,
            style: const TextStyle(color: appNavy, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: appMuted, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              suffixIcon: isPassword
                  ? IconButton(
                      onPressed: () => setState(
                        () => _passwordVisible = !_passwordVisible,
                      ),
                      tooltip:
                          _passwordVisible ? 'Hide password' : 'Show password',
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: appMuted,
                        size: 21,
                      ),
                    )
                  : null,
              errorStyle: const TextStyle(fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0E6EC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0E6EC)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: appTeal, width: 1.4),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      );
}
