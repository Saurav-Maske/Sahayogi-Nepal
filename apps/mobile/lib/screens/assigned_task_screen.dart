import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_colors.dart';
import '../core/volunteer_session_guard.dart';
import 'volunteer_assignment_screen.dart';
import 'volunteer_login_screen.dart';

class AssignedTaskScreen extends StatefulWidget {
  const AssignedTaskScreen({super.key, this.assignmentId});

  final String? assignmentId;

  @override
  State<AssignedTaskScreen> createState() => _AssignedTaskScreenState();
}

class _AssignedTaskScreenState extends State<AssignedTaskScreen> {
  Map<String, dynamic>? _assignment;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAssignment();
  }

  Future<void> _loadAssignment() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final preferences = await SharedPreferences.getInstance();
    final assignmentId = widget.assignmentId ??
        preferences.getString('volunteer_active_assignment_id');
    if (assignmentId == null || assignmentId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You are not assigned to any task currently.';
      });
      return;
    }

    final result = await Api.getVolunteerAssignment(assignmentId);
    if (!mounted) return;
    final assignment = result.data;
    final isAssignedToVolunteer = assignment?['is_mine'] == true;
    setState(() {
      _loading = false;
      if (result.ok && assignment != null && isAssignedToVolunteer) {
        _assignment = assignment;
      } else if (result.errorCode == 'not_found' ||
          (result.ok && assignment != null && !isAssignedToVolunteer)) {
        _assignment = null;
        _error = 'You are not assigned to any task currently.';
      } else {
        _error = result.errorMessage ?? 'Could not load your assigned task.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => VolunteerSessionGuard(
        onUnauthorized: () => openVolunteerLogin(context),
        child: _assignment != null
            ? VolunteerAssignmentScreen(
                assignmentId: '${_assignment!['id']}',
                initialOffer: _assignment!,
              )
            : Scaffold(
                backgroundColor: appPaper,
                appBar: AppBar(
                  backgroundColor: appPaper,
                  foregroundColor: appNavy,
                  elevation: 0,
                  title: const Text('Assigned task'),
                ),
                body: RefreshIndicator(
                  onRefresh: _loadAssignment,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error ??
                                        'Could not load your assigned task.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: appMuted),
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
