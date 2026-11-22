import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/volunteer_auth_service.dart';
import 'volunteer_application_status_screen.dart';
import 'terms_and_conditions_screen.dart';

class VolunteerRegistrationScreen extends StatefulWidget {
  const VolunteerRegistrationScreen({super.key});

  @override
  State<VolunteerRegistrationScreen> createState() =>
      _VolunteerRegistrationScreenState();
}

class _VolunteerRegistrationScreenState
    extends State<VolunteerRegistrationScreen> {
  static const _maxNidImageBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _signupOtpController = TextEditingController();
  final _citizenshipNumberController = TextEditingController();
  final _drivingLicenseNumberController = TextEditingController();
  final _medicalLicenseNumberController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _isSubmitting = false;
  bool _signupOtpSent = false;
  String? _emailVerificationToken;
  String? _otpErrorMessage;
  bool _agreedToVolunteer = false;
  bool _transportManpowerSelected = false;
  bool _healthWorkerSelected = false;
  XFile? _nidImage;
  Uint8List? _nidImageBytes;
  XFile? _drivingLicenseImage;
  Uint8List? _drivingLicenseImageBytes;
  XFile? _medicalLicenseImage;
  Uint8List? _medicalLicenseImageBytes;
  bool _documentError = false;
  bool _drivingLicenseError = false;
  bool _medicalLicenseError = false;
  bool _agreementError = false;

  List<String> get _volunteerTypes => [
        if (_transportManpowerSelected) 'driver',
        if (_healthWorkerSelected) 'doctor',
        if (!_transportManpowerSelected && !_healthWorkerSelected) 'manpower',
      ];

  Future<void> _pickDocumentImage({
    required String documentName,
    required void Function(XFile image, Uint8List bytes) onPicked,
  }) async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image == null) return;

      final imageSize = await image.length();
      if (imageSize > _maxNidImageBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a JPG or PNG image no larger than 5 MB.'),
          ),
        );
        return;
      }

      final imageBytes = await image.readAsBytes();
      if (imageBytes.lengthInBytes > _maxNidImageBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose an image no larger than 5 MB.')),
        );
        return;
      }

      if (!mounted) return;
      onPicked(image, imageBytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload the $documentName image.')),
      );
    }
  }

  Future<void> _pickNidImage() => _pickDocumentImage(
        documentName: 'NID/Citizenship',
        onPicked: (image, bytes) => setState(() {
          _nidImage = image;
          _nidImageBytes = bytes;
          _documentError = false;
        }),
      );

  Future<void> _pickDrivingLicenseImage() => _pickDocumentImage(
        documentName: 'driving license',
        onPicked: (image, bytes) => setState(() {
          _drivingLicenseImage = image;
          _drivingLicenseImageBytes = bytes;
          _drivingLicenseError = false;
        }),
      );

  Future<void> _pickMedicalLicenseImage() => _pickDocumentImage(
        documentName: 'medical license',
        onPicked: (image, bytes) => setState(() {
          _medicalLicenseImage = image;
          _medicalLicenseImageBytes = bytes;
          _medicalLicenseError = false;
        }),
      );

  void _removeNidImage() => setState(() {
        _nidImage = null;
        _nidImageBytes = null;
      });

  void _toggleTransportManpower() => setState(() {
        _transportManpowerSelected = !_transportManpowerSelected;
        if (!_transportManpowerSelected) {
          _drivingLicenseImage = null;
          _drivingLicenseImageBytes = null;
          _drivingLicenseError = false;
        }
      });

  void _toggleHealthWorker() => setState(() {
        _healthWorkerSelected = !_healthWorkerSelected;
        if (!_healthWorkerSelected) {
          _medicalLicenseImage = null;
          _medicalLicenseImageBytes = null;
          _medicalLicenseError = false;
        }
      });

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _signupOtpController.dispose();
    _citizenshipNumberController.dispose();
    _drivingLicenseNumberController.dispose();
    _medicalLicenseNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final missingNid = _nidImage == null;
    final missingAgreement = !_agreedToVolunteer;
    final missingDrivingLicense =
        _transportManpowerSelected && _drivingLicenseImage == null;
    final missingMedicalLicense =
        _healthWorkerSelected && _medicalLicenseImage == null;
    if (missingNid ||
        missingAgreement ||
        missingDrivingLicense ||
        missingMedicalLicense) {
      setState(() {
        _documentError = missingNid;
        _agreementError = missingAgreement;
        _drivingLicenseError = missingDrivingLicense;
        _medicalLicenseError = missingMedicalLicense;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete all required fields.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      if (_emailVerificationToken == null) {
        if (!_signupOtpSent) {
          await VolunteerAuthService.sendSignupOtp(email);
          if (!mounted) return;
          setState(() {
            _signupOtpSent = true;
            _otpErrorMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification code sent to $email.')),
          );
          return;
        }

        final verificationToken =
            await VolunteerAuthService.verifySignupOtp(
          email: email,
          code: _signupOtpController.text,
        );
        if (!mounted) return;
        setState(() {
          _emailVerificationToken = verificationToken;
          _otpErrorMessage = null;
        });
        return;
      }

      final documents = <VolunteerDocument>[
        VolunteerDocument(
          kind: 'citizenship',
          bytes: _nidImageBytes!,
          contentType: _contentType(_nidImage!),
        ),
        if (_transportManpowerSelected)
          VolunteerDocument(
            kind: 'license',
            bytes: _drivingLicenseImageBytes!,
            contentType: _contentType(_drivingLicenseImage!),
          ),
        if (_healthWorkerSelected)
          VolunteerDocument(
            kind: 'service_card',
            bytes: _medicalLicenseImageBytes!,
            contentType: _contentType(_medicalLicenseImage!),
          ),
      ];
      final application = await VolunteerAuthService.submitApplication(
        fullName: _nameController.text,
        email: email,
        phone: _phoneController.text,
        volunteerTypes: _volunteerTypes,
        citizenshipNumber: _citizenshipNumberController.text,
        drivingLicenseNumber: _transportManpowerSelected
            ? _drivingLicenseNumberController.text
            : null,
        medicalLicenseNumber:
            _healthWorkerSelected ? _medicalLicenseNumberController.text : null,
        emailVerificationToken: _emailVerificationToken!,
        documents: documents,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VolunteerApplicationStatusScreen(
            application: application,
            name: _nameController.text.trim(),
            email: email,
            phone: _phoneController.text.trim(),
            roles: [
              'Human Manpower',
              if (_transportManpowerSelected) 'Transport Manpower',
              if (_healthWorkerSelected) 'Health Worker',
            ],
          ),
        ),
      );
    } on VolunteerAuthException catch (error) {
      if (mounted) {
        if (_signupOtpSent && _emailVerificationToken == null) {
          setState(() => _otpErrorMessage = error.message);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Could not submit your application. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _contentType(XFile image) {
    final extension = image.name.toLowerCase();
    if (extension.endsWith('.png')) return 'image/png';
    if (extension.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
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
                        'Create account',
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
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'A helping hand\nstarts with you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 28,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Become a Volunteer and join Nepal’s community\nrelief network.',
                    style: TextStyle(
                      color: appMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Applications are reviewed before volunteer accounts are activated.',
                    style: TextStyle(color: appMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  _formField(
                    label: 'Full name',
                    hint: 'John Dow',
                    controller: _nameController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\p{L}\p{M} ]', unicode: true),
                      ),
                      TextInputFormatter.withFunction((oldValue, newValue) =>
                          newValue.text.startsWith(' ') ? oldValue : newValue),
                    ],
                    validator: (value) {
                      final name = value ?? '';
                      if (name.trim().isEmpty) return 'Enter your full name';
                      if (name.startsWith(' ')) {
                        return 'Name cannot start with a space';
                      }
                      if (!RegExp(r'^[\p{L}\p{M} ]+$', unicode: true)
                          .hasMatch(name)) {
                        return 'Use letters and spaces only';
                      }
                      if (!RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
                        return 'Enter at least one letter';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _formField(
                    label: 'Phone number',
                    hint: '10-digit phone number',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      final phone = value?.trim() ?? '';
                      if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                        return 'Enter a 10-digit phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _formField(
                    label: 'Email address',
                    hint: 'johndoe@email.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (_emailVerificationToken != null || _signupOtpSent) {
                        setState(() {
                          _emailVerificationToken = null;
                          _signupOtpSent = false;
                          _otpErrorMessage = null;
                          _signupOtpController.clear();
                        });
                      }
                    },
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  if (_signupOtpSent && _emailVerificationToken == null) ...[
                    const SizedBox(height: 18),
                    _formField(
                      label: 'Email verification code',
                      hint: 'Enter the 6-digit code',
                      controller: _signupOtpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (_) {
                        if (_otpErrorMessage != null) {
                          setState(() => _otpErrorMessage = null);
                        }
                      },
                      validator: (value) {
                        if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) {
                          return 'Enter the 6-digit code from your email';
                        }
                        return null;
                      },
                    ),
                    if (_otpErrorMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _otpErrorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  _formField(
                    label: 'Citizenship number',
                    hint: 'Enter your citizenship number',
                    controller: _citizenshipNumberController,
                    validator: (value) {
                      final number = value?.trim() ?? '';
                      if (number.length < 4 || number.length > 30) {
                        return 'Enter a valid citizenship number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _nidDocumentUpload(),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => setState(() {
                        _agreedToVolunteer = !_agreedToVolunteer;
                        _agreementError = false;
                      }),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _agreementError
                                ? Colors.redAccent
                                : const Color(0xFFE0E6EC),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _agreedToVolunteer,
                              onChanged: (value) => setState(() {
                                _agreedToVolunteer = value ?? false;
                                _agreementError = false;
                              }),
                              activeColor: appNavy,
                            ),
                            const Expanded(
                              child: Text(
                                'I agree to be a volunteer',
                                style: TextStyle(
                                  color: appNavy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Text(
                              'Required',
                              style: TextStyle(color: appMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_agreementError) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Agree to be a volunteer to continue.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Additional roles',
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Transport and Health Worker roles include Human Manpower by default. You may select either or both.',
                    style: TextStyle(
                      color: appMuted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final optionWidth = (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ContributionOption(
                            width: optionWidth,
                            title: 'Transport Manpower',
                            selected: _transportManpowerSelected,
                            onTap: _toggleTransportManpower,
                          ),
                          _ContributionOption(
                            width: optionWidth,
                            title: 'Health Worker',
                            selected: _healthWorkerSelected,
                            onTap: _toggleHealthWorker,
                          ),
                        ],
                      );
                    },
                  ),
                  if (_transportManpowerSelected) ...[
                    const SizedBox(height: 16),
                    _formField(
                      label: 'Driving license number',
                      hint: 'Enter your license number',
                      controller: _drivingLicenseNumberController,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter your driving license number'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    _documentUpload(
                      title: 'Driving license (required)',
                      image: _drivingLicenseImage,
                      imageBytes: _drivingLicenseImageBytes,
                      error: _drivingLicenseError,
                      errorMessage: 'Upload your driving license image.',
                      onPick: _pickDrivingLicenseImage,
                      onRemove: () => setState(() {
                        _drivingLicenseImage = null;
                        _drivingLicenseImageBytes = null;
                      }),
                    ),
                  ],
                  if (_healthWorkerSelected) ...[
                    const SizedBox(height: 16),
                    _formField(
                      label: 'Medical license number',
                      hint: 'Enter your medical license number',
                      controller: _medicalLicenseNumberController,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter your medical license number'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    _documentUpload(
                      title: 'Medical license (required)',
                      image: _medicalLicenseImage,
                      imageBytes: _medicalLicenseImageBytes,
                      error: _medicalLicenseError,
                      errorMessage: 'Upload your medical license image.',
                      onPick: _pickMedicalLicenseImage,
                      onRemove: () => setState(() {
                        _medicalLicenseImage = null;
                        _medicalLicenseImageBytes = null;
                      }),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'By joining, you agree to our Terms and ',
                        style: TextStyle(color: appMuted, fontSize: 11),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TermsAndConditionsScreen(),
                          ),
                        ),
                        child: const Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: appNavy,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Text(
                        '.',
                        style: TextStyle(color: appMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_emailVerificationToken != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F3EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF159B55),
                            size: 19,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Email verified. Confirm your request to send the application for admin review.',
                              style: TextStyle(
                                color: appNavy,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _emailVerificationToken == null
                                  ? _signupOtpSent
                                      ? 'Verify code'
                                      : 'Verify email'
                                  : 'Confirm request',
                            ),
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
                ],
              ),
            ),
          ),
        ),
      );

  Widget _nidDocumentUpload() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NID/Citizenship (required)',
            style: TextStyle(
              color: Color(0xFF263746),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _pickNidImage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 82),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _documentError
                        ? Colors.redAccent
                        : const Color(0xFFE0E6EC),
                  ),
                ),
                child: _nidImage == null
                    ? Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8EFF4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.upload_file_rounded,
                              color: appNavy,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Upload document image',
                                  style: TextStyle(
                                    color: appNavy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'JPG or PNG · up to 5 MB',
                                  style: TextStyle(
                                    color: appMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: appTeal,
                            size: 22,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.memory(
                              _nidImageBytes!,
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _nidImage!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: appNavy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Tap to replace image',
                                  style: TextStyle(
                                    color: appMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _removeNidImage,
                            tooltip: 'Remove document image',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: appMuted,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (_documentError) ...[
            const SizedBox(height: 6),
            const Text(
              'Upload an image of your NID or Citizenship document.',
              style: TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      );

  Widget _documentUpload({
    required String title,
    required XFile? image,
    required Uint8List? imageBytes,
    required bool error,
    required String errorMessage,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF263746),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 82),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: error ? Colors.redAccent : const Color(0xFFE0E6EC),
                  ),
                ),
                child: image == null
                    ? Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8EFF4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.upload_file_rounded,
                              color: appNavy,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Upload document image',
                                  style: TextStyle(
                                    color: appNavy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'JPG or PNG · up to 5 MB',
                                  style: TextStyle(
                                    color: appMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: appTeal,
                            size: 22,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.memory(
                              imageBytes!,
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              image.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appNavy,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onRemove,
                            tooltip: 'Remove document image',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: appMuted,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (error) ...[
            const SizedBox(height: 6),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      );

  Widget _formField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? helperText,
    Widget? suffixIcon,
    void Function(String)? onChanged,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
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
            obscureText: obscureText,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            validator: validator,
            style: const TextStyle(color: appNavy, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              helperText: helperText,
              helperMaxLines: 2,
              helperStyle: const TextStyle(color: appMuted, fontSize: 10),
              hintStyle: const TextStyle(color: appMuted, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              suffixIcon: suffixIcon,
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

class _ContributionOption extends StatelessWidget {
  const _ContributionOption({
    required this.width,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0xFFE8EFF4) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? appNavy : const Color(0xFFE0E6EC),
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: selected ? appNavy : appNavy,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: appNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
