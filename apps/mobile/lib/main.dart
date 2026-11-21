import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const ProviderScope(child: SahayogiApp()));
}

const _navy = Color(0xFF183D58);
const _teal = Color(0xFF08728B);
const _gold = Color(0xFFF9C83E);
const _paper = Color(0xFFF4F6FA);
const _muted = Color(0xFF708198);

class SahayogiApp extends StatelessWidget {
  const SahayogiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sahayogi Nepal',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: _paper,
          colorScheme: ColorScheme.fromSeed(seedColor: _navy, primary: _navy, surface: _paper),
          fontFamily: 'Roboto',
        ),
        home: const StartupScreen(),
      );
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _continueAfterSplash();
  }

  Future<void> _continueAfterSplash() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => prefs.getBool('onboarding_complete') == true
          ? const HomeScreen()
          : const OnboardingScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: _navy,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('../public/images/SahayogiNepalLogo.png', width: 58, height: 58),
              SizedBox(height: 53),
              Text('Sahayogi\nNepal', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 38, height: 1.42, fontWeight: FontWeight.w700)),
              SizedBox(height: 24),
              Text('Helping Hands,\nSafer Communities.', textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFC5D0DA), fontSize: 16, height: 1.5)),
              SizedBox(height: 29),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _Dot(color: _gold), SizedBox(width: 6), _Dot(color: Color(0xFF526273)), SizedBox(width: 6), _Dot(color: Color(0xFF526273)),
              ]),
              SizedBox(height: 30),
              Text('TOGETHER, WE RESPOND.', style: TextStyle(color: _gold, fontSize: 11, letterSpacing: 2.1, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _OnboardingPage {
  const _OnboardingPage(this.title, this.description, this.scene);
  final String title;
  final String description;
  final int scene;
}

const _pages = [
  _OnboardingPage('Help is closer\nthan you think.', 'Request essentials for yourself or your\ncommunity. The right support starts here.', 0),
  _OnboardingPage('Small acts.\nExtraordinary impact.', 'Connect with local donors, volunteers and\norganizations ready to lend a hand.', 1),
  _OnboardingPage('Every resource.\nEvery step. Visible.', 'Follow your request from first match to safe\ndelivery. Trust built into every update.', 2),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final compact = box.maxHeight < 760;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Sahayogi', style: TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w700)),
                TextButton(onPressed: _finish, style: TextButton.styleFrom(foregroundColor: _teal), child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w600))),
              ]),
              SizedBox(height: compact ? 18 : 34),
              Expanded(flex: 12, child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360, maxHeight: 310),
                child: OnboardingIllustration(scene: page.scene),
              ))),
              SizedBox(height: compact ? 12 : 28),
              Text('${(_index + 1).toString().padLeft(2, '0')} / 03', style: const TextStyle(color: _teal, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              Text(page.title, style: const TextStyle(color: _navy, fontSize: 30, height: 1.17, fontWeight: FontWeight.w700, letterSpacing: -.5)),
              const SizedBox(height: 19),
              Text(page.description, style: const TextStyle(color: _muted, fontSize: 15, height: 1.48)),
              const SizedBox(height: 27),
              Row(children: List.generate(3, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 6), width: i == _index ? 26 : 7, height: 7,
                    decoration: BoxDecoration(color: i == _index ? _navy : const Color(0xFFCCD6DF), borderRadius: BorderRadius.circular(10)),
                  ))),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, height: 52, child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(backgroundColor: _index == 2 ? _gold : _navy, foregroundColor: _index == 2 ? _navy : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: _index == 2 ? 2 : 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_index == 2 ? 'Get started' : 'Continue', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10), const Icon(Icons.arrow_forward_rounded, size: 20),
                ]),
              )),
              SizedBox(height: compact ? 8 : 18),
            ]),
          );
        }),
      ),
    );
  }
}

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.scene});
  final int scene;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ScenePainter(scene), child: const SizedBox.expand());
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);
  final int scene;
  final Paint p = Paint()..isAntiAlias = true;
  void fill(Canvas c, Color color, Path path) { p.color = color; p.style = PaintingStyle.fill; c.drawPath(path, p); }
  void line(Canvas c, Color color, double width, List<Offset> pts) { p.color = color; p.strokeWidth = width; p.style = PaintingStyle.stroke; p.strokeCap = StrokeCap.round; p.strokeJoin = StrokeJoin.round; final path = Path()..moveTo(pts.first.dx, pts.first.dy); for (final pt in pts.skip(1)) { path.lineTo(pt.dx, pt.dy); } c.drawPath(path, p); p.style = PaintingStyle.fill; }
  Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 360, sy = size.height / 300;
    canvas.save(); canvas.scale(sx, sy);
    final bg = Path()..addOval(const Rect.fromLTWH(34, 22, 292, 242));
    fill(canvas, const Color(0xFFE5EFF2), bg);
    if (scene == 0) _village(canvas);
    if (scene == 1) _helpers(canvas);
    if (scene == 2) _supplies(canvas);
    canvas.restore();
  }

  void _house(Canvas c, double x, double y, double scale) {
    c.save(); c.translate(x, y); c.scale(scale);
    fill(c, const Color(0xFFB9D0D8), poly([const Offset(0, 58), const Offset(40, 39), const Offset(78, 57), const Offset(39, 78)]));
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(12, 24), const Offset(42, 10), const Offset(65, 23), const Offset(65, 58), const Offset(38, 72), const Offset(12, 57)]));
    fill(c, const Color(0xFF27788C), poly([const Offset(5, 27), const Offset(40, 0), const Offset(72, 24), const Offset(42, 42)]));
    line(c, _navy, 3, [const Offset(5, 27), const Offset(40, 0), const Offset(72, 24), const Offset(42, 42), const Offset(5, 27)]);
    fill(c, _navy, poly([const Offset(34, 50), const Offset(46, 50), const Offset(46, 70), const Offset(34, 70)]));
    c.restore();
  }

  void _person(Canvas c, double x, double y, Color shirt) {
    fill(c, const Color(0xFFDBA985), Path()..addOval(Rect.fromLTWH(x + 11, y, 27, 30)));
    fill(c, _navy, poly([Offset(x + 9, y + 11), Offset(x + 13, y + 2), Offset(x + 27, y - 1), Offset(x + 40, y + 8), Offset(x + 42, y + 15), Offset(x + 14, y + 12)]));
    fill(c, shirt, poly([Offset(x + 8, y + 34), Offset(x + 40, y + 34), Offset(x + 48, y + 86), Offset(x + 1, y + 86)]));
    line(c, _navy, 3, [Offset(x + 8, y + 36), Offset(x + 2, y + 84), Offset(x + 46, y + 84), Offset(x + 40, y + 36)]);
    line(c, _navy, 8, [Offset(x + 15, y + 84), Offset(x + 12, y + 119)]);
    line(c, _navy, 8, [Offset(x + 34, y + 84), Offset(x + 39, y + 119)]);
  }

  void _village(Canvas c) {
    _house(c, 44, 112, .9); _house(c, 231, 107, .88); _house(c, 35, 205, .8);
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(137, 129), const Offset(197, 99), const Offset(255, 128), const Offset(255, 188), const Offset(196, 217), const Offset(137, 188)]));
    fill(c, const Color(0xFF27788C), poly([const Offset(128, 132), const Offset(190, 89), const Offset(266, 132), const Offset(197, 165)]));
    line(c, _navy, 4, [const Offset(128, 132), const Offset(190, 89), const Offset(266, 132), const Offset(197, 165), const Offset(128, 132)]);
    fill(c, _navy, poly([const Offset(177, 161), const Offset(197, 170), const Offset(197, 209), const Offset(177, 199)]));
    fill(c, const Color(0xFFBFE0E5), poly([const Offset(204, 172), const Offset(245, 151), const Offset(245, 184), const Offset(204, 205)]));
    line(c, _teal, 2, [const Offset(211, 179), const Offset(238, 166)]); line(c, _teal, 2, [const Offset(211, 188), const Offset(238, 175)]);
    fill(c, _gold, poly([const Offset(221, 119), const Offset(231, 124), const Offset(231, 135), const Offset(221, 141), const Offset(211, 135), const Offset(211, 124)]));
    p.color = const Color(0xFF348A70); c.drawCircle(const Offset(278, 213), 25, p); p.color = Colors.white; p.style = PaintingStyle.stroke; p.strokeWidth = 4; c.drawCircle(const Offset(278, 213), 25, p); p.style = PaintingStyle.fill;
    line(c, Colors.white, 4, [const Offset(267, 213), const Offset(276, 222), const Offset(291, 205)]);
  }

  void _helpers(Canvas c) {
    _person(c, 55, 74, const Color(0xFF1C7288)); _person(c, 122, 78, const Color(0xFF1C7288)); _person(c, 252, 80, const Color(0xFF27788C));
    fill(c, const Color(0xFFD9E2E7), poly([const Offset(123, 145), const Offset(234, 145), const Offset(239, 181), const Offset(122, 181)]));
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(135, 126), const Offset(224, 126), const Offset(224, 169), const Offset(135, 169)]));
    fill(c, const Color(0xFFE0AB3B), poly([const Offset(165, 137), const Offset(183, 137), const Offset(183, 147), const Offset(165, 147)]));
    line(c, _navy, 4, [const Offset(135, 126), const Offset(224, 126), const Offset(224, 169), const Offset(135, 169), const Offset(135, 126)]);
    fill(c, const Color(0xFFA9CDD4), poly([const Offset(170, 112), const Offset(170, 99), const Offset(183, 99), const Offset(183, 112), const Offset(196, 126), const Offset(157, 126)]));
    line(c, _navy, 3, [const Offset(88, 147), const Offset(122, 149), const Offset(136, 136)]); line(c, _navy, 3, [const Offset(255, 145), const Offset(232, 151), const Offset(224, 145)]);
    line(c, const Color(0xFF9DBFC8), 3, [const Offset(58, 267), const Offset(304, 267)]);
  }

  void _supplies(Canvas c) {
    fill(c, const Color(0xFFA8CAD2), poly([const Offset(42, 230), const Offset(98, 178), const Offset(155, 232), const Offset(206, 186), const Offset(316, 233), const Offset(316, 255), const Offset(42, 255)]));
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(69, 129), const Offset(94, 98), const Offset(118, 129), const Offset(139, 112), const Offset(172, 149), const Offset(69, 149)]));
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(201, 137), const Offset(224, 106), const Offset(246, 137), const Offset(264, 122), const Offset(288, 153), const Offset(201, 153)]));
    fill(c, const Color(0xFFFFFFFF), poly([const Offset(72, 173), const Offset(112, 141), const Offset(172, 173), const Offset(172, 235), const Offset(72, 235)]));
    fill(c, const Color(0xFF27788C), poly([const Offset(58, 177), const Offset(100, 143), const Offset(181, 143), const Offset(172, 179)]));
    line(c, _navy, 4, [const Offset(58, 177), const Offset(100, 143), const Offset(181, 143), const Offset(172, 179), const Offset(58, 179)]);
    fill(c, _navy, poly([const Offset(91, 190), const Offset(109, 190), const Offset(109, 209), const Offset(91, 209)]));
    fill(c, _navy, poly([const Offset(132, 190), const Offset(150, 190), const Offset(150, 209), const Offset(132, 209)]));
    fill(c, _navy, poly([const Offset(112, 211), const Offset(132, 211), const Offset(132, 235), const Offset(112, 235)]));
    _person(c, 218, 148, const Color(0xFF26788D));
    line(c, _navy, 7, [const Offset(257, 204), const Offset(281, 183), const Offset(288, 158)]);
    fill(c, _gold, Path()..addOval(const Rect.fromLTWH(269, 93, 49, 55)));
    fill(c, Colors.white, Path()..addOval(const Rect.fromLTWH(285, 107, 17, 17)));
    p.color = _navy; p.style = PaintingStyle.stroke; p.strokeWidth = 3; c.drawCircle(const Offset(293.5, 115.5), 8.5, p); p.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => oldDelegate.scene != scene;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sahayogi Nepal', style: TextStyle(fontWeight: FontWeight.w700)), backgroundColor: _paper),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('How can we help?', style: TextStyle(color: _navy, fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _homeTile(context, Icons.volunteer_activism_rounded, 'Request help', 'Ask for essentials for you or your community'),
          _homeTile(context, Icons.favorite_rounded, 'Offer a donation', 'Share resources with people who need them'),
          _homeTile(context, Icons.people_alt_rounded, 'Volunteer login / apply', 'Join local response efforts'),
          _homeTile(context, Icons.map_rounded, 'Map', 'Explore needs and resources nearby'),
          _homeTile(context, Icons.local_shipping_rounded, 'Track my request', 'See updates on a request'),
        ]),
      );

  Widget _homeTile(BuildContext context, IconData icon, String title, String subtitle) => Card(
        color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFFE5EFF2), foregroundColor: _teal, child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _navy)), subtitle: Text(subtitle, style: const TextStyle(color: _muted)), trailing: const Icon(Icons.chevron_right_rounded, color: _teal)),
      );
}
