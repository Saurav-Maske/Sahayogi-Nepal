import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../widgets/community_map_preview.dart';
import 'volunteer_login_screen.dart';

class DonateResourcesScreen extends StatefulWidget {
  const DonateResourcesScreen({super.key});

  @override
  State<DonateResourcesScreen> createState() => _DonateResourcesScreenState();
}

class _DonateResourcesScreenState extends State<DonateResourcesScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _nameControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _descriptionControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _quantityControllers = [
    TextEditingController(),
  ];
  final _contactController = TextEditingController();

  final List<String?> _categories = [null];
  final List<bool> _categoryErrors = [false];
  String? _location;
  bool _locationError = false;

  static const _categoryOptions = [
    'Food supplies',
    'Drinking water',
    'Medicine',
    'Clothing',
    'Temporary shelter',
  ];

  static const _locations = [
    'Melamchi, Ward 11',
    'Kathmandu, Ward 5',
    'Balaju, Ward 16',
    'Boudha, Ward 6',
  ];

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _descriptionControllers) {
      controller.dispose();
    }
    for (final controller in _quantityControllers) {
      controller.dispose();
    }
    _contactController.dispose();
    super.dispose();
  }

  void _addDonationItem() => setState(() {
        _categories.add(null);
        _categoryErrors.add(false);
        _nameControllers.add(TextEditingController());
        _descriptionControllers.add(TextEditingController());
        _quantityControllers.add(TextEditingController());
      });

  void _removeDonationItem(int index) {
    if (_categories.length <= 1) return;
    setState(() {
      _categories.removeAt(index);
      _categoryErrors.removeAt(index);
      _nameControllers.removeAt(index).dispose();
      _descriptionControllers.removeAt(index).dispose();
      _quantityControllers.removeAt(index).dispose();
    });
  }

  Future<void> _chooseValue({
    required String title,
    required List<String> values,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: appPaper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: appNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...values.map(
              (value) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(value),
                trailing: value == selectedValue
                    ? const Icon(Icons.check_rounded, color: appTeal)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) onSelected(selected);
  }

  void _submitDonation() {
    final fieldsValid = _formKey.currentState!.validate();
    final categoriesValid = _categories.every((category) => category != null);
    final locationValid = _location != null;
    setState(() {
      for (var i = 0; i < _categories.length; i++) {
        _categoryErrors[i] = _categories[i] == null;
      }
      _locationError = !locationValid;
    });
    if (!fieldsValid || !categoriesValid || !locationValid) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Donation submission is not connected yet.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
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
                      const Expanded(
                        child: Text(
                          'Donate resources',
                          style: TextStyle(
                            color: appNavy,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.verified_user_outlined,
                        color: appTeal,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'What can you share?',
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your extra supplies can be someone’s lifeline.',
                    style: TextStyle(color: appMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  ...List.generate(
                    _categories.length,
                    (index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _categories.length - 1 ? 0 : 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _fieldLabel('Resource category')),
                              if (_categories.length > 1)
                                IconButton(
                                  onPressed: () => _removeDonationItem(index),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Remove resource',
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: appMuted,
                                    size: 19,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _choiceField(
                            value: _categories[index] ?? 'Select a category',
                            error: _categoryErrors[index],
                            onTap: () => _chooseValue(
                              title: 'Resource category',
                              values: _categoryOptions,
                              selectedValue: _categories[index] ?? '',
                              onSelected: (value) => setState(() {
                                _categories[index] = value;
                                _categoryErrors[index] = false;
                              }),
                            ),
                          ),
                          if (_categoryErrors[index]) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Choose a resource category.',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _fieldLabel('Resource name'),
                          const SizedBox(height: 8),
                          _textField(
                            controller: _nameControllers[index],
                            hint: 'Family food kits',
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter a resource name'
                                    : null,
                          ),
                          const SizedBox(height: 18),
                          _fieldLabel('Description'),
                          const SizedBox(height: 8),
                          _textField(
                            controller: _descriptionControllers[index],
                            hint: 'Rice, lentils, cooking oil and salt.',
                            validator: null,
                          ),
                          const SizedBox(height: 18),
                          _fieldLabel('Available quantity'),
                          const SizedBox(height: 8),
                          _textField(
                            controller: _quantityControllers[index],
                            hint: '40 family kits',
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter the available quantity'
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addDonationItem,
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text(
                        'Add another resource',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel('Pickup location'),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _chooseValue(
                        title: 'Choose pickup location',
                        values: _locations,
                        selectedValue: _location ?? '',
                        onSelected: (value) => setState(() {
                          _location = value;
                          _locationError = false;
                        }),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: _locationError
                              ? Border.all(color: Colors.redAccent)
                              : null,
                        ),
                        child: Stack(
                          children: [
                            const CommunityMapPreview(height: 66),
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: Center(
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: appNavy,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            if (_location != null)
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .94),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      _location!,
                                      style: const TextStyle(
                                        color: appNavy,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_locationError) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Choose a pickup location.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _fieldLabel('Contact information'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _contactController,
                    hint: '+977 9841 234 567',
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      final contact = value?.trim() ?? '';
                      if (contact.isEmpty) return 'Enter a contact number';
                      if (contact.replaceAll(RegExp(r'\D'), '').length < 7) {
                        return 'Enter a valid contact number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _submitDonation,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: const Text('Share resources'),
                      style: FilledButton.styleFrom(
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
        bottomNavigationBar: _donationNavigationBar(context),
      );

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF263746),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );

  Widget _choiceField({
    required String value,
    required VoidCallback onTap,
    bool error = false,
  }) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: error ? Colors.redAccent : const Color(0xFFE0E6EC),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(color: appMuted, fontSize: 14),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: appMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
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
          suffixIcon: const Icon(
            Icons.chevron_right_rounded,
            color: appMuted,
            size: 22,
          ),
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
      );
}

Widget _donationNavigationBar(BuildContext context) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6EC))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _DonationNavigationItem(
                icon: Icons.home_outlined,
                label: 'Home',
                selected: true,
                onTap: () => Navigator.of(context).popUntil(
                  (route) => route.isFirst,
                ),
              ),
              const _DonationNavigationItem(
                icon: Icons.map_outlined,
                label: 'Explore',
                selected: false,
              ),
              const _DonationNavigationItem(
                icon: Icons.inventory_2_outlined,
                label: 'Requests',
                selected: false,
              ),
              _DonationNavigationItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                selected: false,
                onTap: () => openVolunteerLogin(context),
              ),
            ],
          ),
        ),
      ),
    );

class _DonationNavigationItem extends StatelessWidget {
  const _DonationNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 27,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE7F0F4)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 21, color: appNavy),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: appNavy,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
}
