import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.scene});

  final int scene;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ScenePainter(scene),
        child: const SizedBox.expand(),
      );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);

  final int scene;
  final Paint _paint = Paint()..isAntiAlias = true;

  void _fill(Canvas canvas, Color color, Path path) {
    _paint
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, _paint);
  }

  void _line(Canvas canvas, Color color, double width, List<Offset> points) {
    _paint
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, _paint);
    _paint.style = PaintingStyle.fill;
  }

  Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 360, size.height / 300);

    final background = Path()..addOval(const Rect.fromLTWH(34, 22, 292, 242));
    _fill(canvas, const Color(0xFFE5EFF2), background);

    switch (scene) {
      case 0:
        _village(canvas);
        break;
      case 1:
        _helpers(canvas);
        break;
      case 2:
        _supplies(canvas);
        break;
    }

    canvas.restore();
  }

  void _house(Canvas canvas, double x, double y, double scale) {
    canvas.save();
    canvas
      ..translate(x, y)
      ..scale(scale);
    _fill(
      canvas,
      const Color(0xFFB9D0D8),
      _poly(const [
        Offset(0, 58),
        Offset(40, 39),
        Offset(78, 57),
        Offset(39, 78),
      ]),
    );
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(12, 24),
        Offset(42, 10),
        Offset(65, 23),
        Offset(65, 58),
        Offset(38, 72),
        Offset(12, 57),
      ]),
    );
    _fill(
      canvas,
      const Color(0xFF27788C),
      _poly(const [
        Offset(5, 27),
        Offset(40, 0),
        Offset(72, 24),
        Offset(42, 42),
      ]),
    );
    _line(canvas, appNavy, 3, const [
      Offset(5, 27),
      Offset(40, 0),
      Offset(72, 24),
      Offset(42, 42),
      Offset(5, 27),
    ]);
    _fill(
      canvas,
      appNavy,
      _poly(const [
        Offset(34, 50),
        Offset(46, 50),
        Offset(46, 70),
        Offset(34, 70),
      ]),
    );
    canvas.restore();
  }

  void _person(Canvas canvas, double x, double y, Color shirt) {
    _fill(
      canvas,
      const Color(0xFFDBA985),
      Path()..addOval(Rect.fromLTWH(x + 11, y, 27, 30)),
    );
    _fill(
      canvas,
      appNavy,
      _poly([
        Offset(x + 9, y + 11),
        Offset(x + 13, y + 2),
        Offset(x + 27, y - 1),
        Offset(x + 40, y + 8),
        Offset(x + 42, y + 15),
        Offset(x + 14, y + 12),
      ]),
    );
    _fill(
      canvas,
      shirt,
      _poly([
        Offset(x + 8, y + 34),
        Offset(x + 40, y + 34),
        Offset(x + 48, y + 86),
        Offset(x + 1, y + 86),
      ]),
    );
    _line(canvas, appNavy, 3, [
      Offset(x + 8, y + 36),
      Offset(x + 2, y + 84),
      Offset(x + 46, y + 84),
      Offset(x + 40, y + 36),
    ]);
    _line(
        canvas, appNavy, 8, [Offset(x + 15, y + 84), Offset(x + 12, y + 119)]);
    _line(
        canvas, appNavy, 8, [Offset(x + 34, y + 84), Offset(x + 39, y + 119)]);
  }

  void _village(Canvas canvas) {
    _house(canvas, 44, 112, .9);
    _house(canvas, 231, 107, .88);
    _house(canvas, 35, 205, .8);
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(137, 129),
        Offset(197, 99),
        Offset(255, 128),
        Offset(255, 188),
        Offset(196, 217),
        Offset(137, 188),
      ]),
    );
    _fill(
      canvas,
      const Color(0xFF27788C),
      _poly(const [
        Offset(128, 132),
        Offset(190, 89),
        Offset(266, 132),
        Offset(197, 165),
      ]),
    );
    _line(canvas, appNavy, 4, const [
      Offset(128, 132),
      Offset(190, 89),
      Offset(266, 132),
      Offset(197, 165),
      Offset(128, 132),
    ]);
    _fill(
      canvas,
      appNavy,
      _poly(const [
        Offset(177, 161),
        Offset(197, 170),
        Offset(197, 209),
        Offset(177, 199),
      ]),
    );
    _fill(
      canvas,
      const Color(0xFFBFE0E5),
      _poly(const [
        Offset(204, 172),
        Offset(245, 151),
        Offset(245, 184),
        Offset(204, 205),
      ]),
    );
    _line(canvas, appTeal, 2, const [Offset(211, 179), Offset(238, 166)]);
    _line(canvas, appTeal, 2, const [Offset(211, 188), Offset(238, 175)]);
    _fill(
      canvas,
      appGold,
      _poly(const [
        Offset(221, 119),
        Offset(231, 124),
        Offset(231, 135),
        Offset(221, 141),
        Offset(211, 135),
        Offset(211, 124),
      ]),
    );
    _paint.color = const Color(0xFF348A70);
    canvas.drawCircle(const Offset(278, 213), 25, _paint);
    _paint
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(278, 213), 25, _paint);
    _paint.style = PaintingStyle.fill;
    _line(canvas, Colors.white, 4, const [
      Offset(267, 213),
      Offset(276, 222),
      Offset(291, 205),
    ]);
  }

  void _helpers(Canvas canvas) {
    _person(canvas, 55, 74, const Color(0xFF1C7288));
    _person(canvas, 122, 78, const Color(0xFF1C7288));
    _person(canvas, 252, 80, const Color(0xFF27788C));
    _fill(
      canvas,
      const Color(0xFFD9E2E7),
      _poly(const [
        Offset(123, 145),
        Offset(234, 145),
        Offset(239, 181),
        Offset(122, 181),
      ]),
    );
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(135, 126),
        Offset(224, 126),
        Offset(224, 169),
        Offset(135, 169),
      ]),
    );
    _fill(
      canvas,
      const Color(0xFFE0AB3B),
      _poly(const [
        Offset(165, 137),
        Offset(183, 137),
        Offset(183, 147),
        Offset(165, 147),
      ]),
    );
    _line(canvas, appNavy, 4, const [
      Offset(135, 126),
      Offset(224, 126),
      Offset(224, 169),
      Offset(135, 169),
      Offset(135, 126),
    ]);
    _fill(
      canvas,
      const Color(0xFFA9CDD4),
      _poly(const [
        Offset(170, 112),
        Offset(170, 99),
        Offset(183, 99),
        Offset(183, 112),
        Offset(196, 126),
        Offset(157, 126),
      ]),
    );
    _line(canvas, appNavy, 3, const [
      Offset(88, 147),
      Offset(122, 149),
      Offset(136, 136),
    ]);
    _line(canvas, appNavy, 3, const [
      Offset(255, 145),
      Offset(232, 151),
      Offset(224, 145),
    ]);
    _line(canvas, const Color(0xFF9DBFC8), 3, const [
      Offset(58, 267),
      Offset(304, 267),
    ]);
  }

  void _supplies(Canvas canvas) {
    _fill(
      canvas,
      const Color(0xFFA8CAD2),
      _poly(const [
        Offset(42, 230),
        Offset(98, 178),
        Offset(155, 232),
        Offset(206, 186),
        Offset(316, 233),
        Offset(316, 255),
        Offset(42, 255),
      ]),
    );
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(69, 129),
        Offset(94, 98),
        Offset(118, 129),
        Offset(139, 112),
        Offset(172, 149),
        Offset(69, 149),
      ]),
    );
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(201, 137),
        Offset(224, 106),
        Offset(246, 137),
        Offset(264, 122),
        Offset(288, 153),
        Offset(201, 153),
      ]),
    );
    _fill(
      canvas,
      Colors.white,
      _poly(const [
        Offset(72, 173),
        Offset(112, 141),
        Offset(172, 173),
        Offset(172, 235),
        Offset(72, 235),
      ]),
    );
    _fill(
      canvas,
      const Color(0xFF27788C),
      _poly(const [
        Offset(58, 177),
        Offset(100, 143),
        Offset(181, 143),
        Offset(172, 179),
      ]),
    );
    _line(canvas, appNavy, 4, const [
      Offset(58, 177),
      Offset(100, 143),
      Offset(181, 143),
      Offset(172, 179),
      Offset(58, 179),
    ]);
    _fill(
      canvas,
      appNavy,
      _poly(const [
        Offset(91, 190),
        Offset(109, 190),
        Offset(109, 209),
        Offset(91, 209),
      ]),
    );
    _fill(
      canvas,
      appNavy,
      _poly(const [
        Offset(132, 190),
        Offset(150, 190),
        Offset(150, 209),
        Offset(132, 209),
      ]),
    );
    _fill(
      canvas,
      appNavy,
      _poly(const [
        Offset(112, 211),
        Offset(132, 211),
        Offset(132, 235),
        Offset(112, 235),
      ]),
    );
    _person(canvas, 218, 148, const Color(0xFF26788D));
    _line(canvas, appNavy, 7, const [
      Offset(257, 204),
      Offset(281, 183),
      Offset(288, 158),
    ]);
    _fill(
      canvas,
      appGold,
      Path()..addOval(const Rect.fromLTWH(269, 93, 49, 55)),
    );
    _fill(
      canvas,
      Colors.white,
      Path()..addOval(const Rect.fromLTWH(285, 107, 17, 17)),
    );
    _paint
      ..color = appNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(const Offset(293.5, 115.5), 8.5, _paint);
    _paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
