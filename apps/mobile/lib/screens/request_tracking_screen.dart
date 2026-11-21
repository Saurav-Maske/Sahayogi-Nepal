import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../models/request_summary.dart';
import '../widgets/community_map_preview.dart';
import 'explore_screen.dart';
import 'volunteer_login_screen.dart';

class RequestTrackingScreen extends StatelessWidget {
  const RequestTrackingScreen({super.key, required this.request});

  final RequestSummaryData request;

  int get _currentStep => switch (request.status) {
        'Pending' => 0,
        'In progress' => 2,
        'Fulfilled' => 3,
        _ => 0,
      };

  List<_JourneyStep> get _steps {
    if (request.isDonation) {
      return switch (request.status) {
        'Pending' => const [
            _JourneyStep('Donation shared', 'Today · 08:20'),
            _JourneyStep('Recipient matched', 'Finding a nearby request'),
            _JourneyStep('Pickup coordinated', 'Waiting for a match'),
            _JourneyStep('Received', 'Awaiting delivery'),
          ],
        'Fulfilled' => const [
            _JourneyStep('Donation shared', '19 Nov · 09:10'),
            _JourneyStep('Recipient matched', '19 Nov · 11:20'),
            _JourneyStep('Picked up', '20 Nov · 14:45'),
            _JourneyStep('Received', '20 Nov · 15:35'),
          ],
        _ => const [
            _JourneyStep('Donation shared', 'Yesterday · 08:20'),
            _JourneyStep('Recipient matched', 'Yesterday · 10:05'),
            _JourneyStep('Pickup coordinated', 'Today · 09:15'),
            _JourneyStep('Received', 'Estimated today · 11:00'),
          ],
      };
    }

    return switch (request.status) {
      'Pending' => const [
          _JourneyStep('Pending', 'Today · 09:41'),
          _JourneyStep('Matched', 'Finding nearby resources'),
          _JourneyStep('In Progress', 'Awaiting a match'),
          _JourneyStep('Fulfilled', 'Awaiting delivery'),
        ],
      'Fulfilled' => const [
          _JourneyStep('Pending', '19 Nov · 10:15'),
          _JourneyStep('Matched', '19 Nov · 11:00'),
          _JourneyStep('In Progress', '19 Nov · 15:10'),
          _JourneyStep('Fulfilled', '19 Nov · 16:30'),
        ],
      _ => const [
          _JourneyStep('Pending', 'Today · 08:40'),
          _JourneyStep('Matched', 'Today · 09:05'),
          _JourneyStep('In Progress', 'Today · 09:25'),
          _JourneyStep('Fulfilled', 'Estimated today · 11:00'),
        ],
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: appNavy,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        request.isDonation ? 'Track donation' : 'Track request',
                        style: const TextStyle(
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
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.id,
                                style: const TextStyle(
                                  color: appNavy,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                request.location,
                                style: const TextStyle(
                                  color: appMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: request.status),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _RequestInfoCard(request: request),
                    const SizedBox(height: 22),
                    const Text(
                      'Your relief journey',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _JourneyCard(
                      steps: _steps,
                      currentStep: _currentStep,
                      fulfilled: request.status == 'Fulfilled',
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Latest update',
                      style: TextStyle(
                        color: appNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LatestUpdate(
                      status: request.status,
                      isDonation: request.isDonation,
                      location: request.location,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _TrackingNavigationBar(
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onExplore: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
          ),
          onRequests: () => Navigator.of(context).pop(),
          onProfile: () => openVolunteerLogin(context),
        ),
      );
}

class _JourneyStep {
  const _JourneyStep(this.title, this.time);

  final String title;
  final String time;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final background = switch (status) {
      'Pending' => const Color(0xFFFFF7DE),
      'Fulfilled' => const Color(0xFFE8F5EC),
      _ => const Color(0xFFE9F0F5),
    };
    final border = switch (status) {
      'Pending' => const Color(0xFFF0C650),
      'Fulfilled' => const Color(0xFF159B68),
      _ => appNavy,
    };

    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: status == 'Pending'
              ? const Color(0xFF866500)
              : status == 'Fulfilled'
                  ? const Color(0xFF159B68)
                  : appNavy,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestInfoCard extends StatelessWidget {
  const _RequestInfoCard({required this.request});

  final RequestSummaryData request;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.trackingTitle,
              style: const TextStyle(
                color: appNavy,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              request.requestSummary,
              style: const TextStyle(
                color: appTeal,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Submitted ${request.submittedAt}',
              style: const TextStyle(color: appMuted, fontSize: 10),
            ),
          ],
        ),
      );
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.steps,
    required this.currentStep,
    required this.fulfilled,
  });

  final List<_JourneyStep> steps;
  final int currentStep;
  final bool fulfilled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE0E6EC)),
        ),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++)
              _JourneyRow(
                step: steps[index],
                isCurrent: index == currentStep,
                isComplete: fulfilled || index < currentStep,
                isLast: index == steps.length - 1,
                fulfilled: fulfilled,
              ),
          ],
        ),
      );
}

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({
    required this.step,
    required this.isCurrent,
    required this.isComplete,
    required this.isLast,
    required this.fulfilled,
  });

  final _JourneyStep step;
  final bool isCurrent;
  final bool isComplete;
  final bool isLast;
  final bool fulfilled;

  @override
  Widget build(BuildContext context) {
    final dotColor = fulfilled
        ? const Color(0xFF159B68)
        : isComplete || isCurrent
            ? appNavy
            : const Color(0xFFE1E7ED);
    final lineColor = fulfilled || isComplete
        ? (fulfilled ? const Color(0xFF159B68) : appNavy)
        : const Color(0xFFE1E7ED);

    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 52,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isLast)
                  Positioned(
                    top: 17,
                    bottom: 0,
                    child: Container(width: 2, color: lineColor),
                  ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: isComplete || isCurrent ? appNavy : appMuted,
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.time,
                  style: const TextStyle(color: appMuted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestUpdate extends StatelessWidget {
  const _LatestUpdate({
    required this.status,
    required this.isDonation,
    required this.location,
  });

  final String status;
  final bool isDonation;
  final String location;

  @override
  Widget build(BuildContext context) {
    final isFulfilled = status == 'Fulfilled';
    final isPending = status == 'Pending';
    final background = isFulfilled
        ? const Color(0xFFECF7EF)
        : isPending
            ? const Color(0xFFFFF7DE)
            : const Color(0xFFEAF0F5);
    final title = isDonation
        ? isFulfilled
            ? 'Your donation made a difference.'
            : isPending
                ? 'Your donation is listed.'
                : 'Your donation is on the way.'
        : isFulfilled
            ? 'Delivered. Confirmed. Thank you.'
            : isPending
                ? 'Finding the right helping hand.'
                : 'Your supplies are on the way.';
    final message = isDonation
        ? isFulfilled
            ? 'Your donated supplies were received in $location. Thank you for helping your community.'
            : isPending
                ? 'We’re matching your supplies with a nearby request. We’ll update you when pickup is arranged.'
                : 'A nearby recipient has been matched. Pickup is being coordinated for $location.'
        : isFulfilled
            ? 'All 6 food kits were received at Melamchi Ward 11. Delivery confirmed by the local distribution team.'
            : isPending
                ? 'Matching by distance, resource type, quantity and urgency. We’ll notify you as soon as a donor is found.'
                : 'A nearby volunteer is coordinating this delivery. Follow the map for the community area.';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE0E6EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: appNavy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: appMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (!isPending && !isFulfilled) ...[
            const SizedBox(height: 12),
            const CommunityMapPreview(height: 82),
          ],
        ],
      ),
    );
  }
}

class _TrackingNavigationBar extends StatelessWidget {
  const _TrackingNavigationBar({
    required this.onHome,
    required this.onExplore,
    required this.onRequests,
    required this.onProfile,
  });

  final VoidCallback onHome;
  final VoidCallback onExplore;
  final VoidCallback onRequests;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Container(
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
                _TrackingNavigationItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: onHome,
                ),
                _TrackingNavigationItem(
                  icon: Icons.map_outlined,
                  label: 'Explore',
                  onTap: onExplore,
                ),
                _TrackingNavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Requests',
                  selected: true,
                  onTap: onRequests,
                ),
                _TrackingNavigationItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: onProfile,
                ),
              ],
            ),
          ),
        ),
      );
}

class _TrackingNavigationItem extends StatelessWidget {
  const _TrackingNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
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
                  color:
                      selected ? const Color(0xFFE7F0F4) : Colors.transparent,
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
