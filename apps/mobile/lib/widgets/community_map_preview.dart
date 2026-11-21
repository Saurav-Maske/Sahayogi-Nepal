import 'package:material_ui/material_ui.dart';

class CommunityMapPreview extends StatelessWidget {
  const CommunityMapPreview({super.key, this.height = 164});

  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, height);

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  CustomPaint(
                    size: size,
                    painter: _CommunityMapPainter(),
                  ),
                  _MapLabel('Balaju',
                      left: size.width * .07, top: size.height * .14),
                  _MapLabel('Boudha',
                      right: size.width * .11, top: size.height * .19),
                  _MapLabel('Kathmandu',
                      left: size.width * .27, top: size.height * .48),
                  _MapLabel('Baneshwor',
                      right: size.width * .17, bottom: size.height * .1),
                  _MapMarker(
                    left: size.width * .18,
                    top: size.height * .68,
                    color: const Color(0xFF12A65A),
                  ),
                  _MapMarker(
                    left: size.width * .44,
                    top: size.height * .62,
                    color: const Color(0xFF18708A),
                  ),
                  _MapMarker(
                    left: size.width * .65,
                    top: size.height * .43,
                    color: const Color(0xFFF4C339),
                    size: 18,
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _MapLabel extends StatelessWidget {
  const _MapLabel(
    this.text, {
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final String text;
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF78879A),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.left,
    required this.top,
    required this.color,
    this.size = 14,
  });

  final double left;
  final double top;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        top: top,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x260F3045),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      );
}

class _CommunityMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()..color = const Color(0xFFEAF0E7);
    canvas.drawRect(rect, background);

    _drawArea(canvas, size, const Color(0xFFDCE8D4), const [
      Offset(0, 0),
      Offset(.29, 0),
      Offset(.34, .31),
      Offset(.11, .43),
      Offset(0, .35),
    ]);
    _drawArea(canvas, size, const Color(0xFFE2EBDD), const [
      Offset(.73, .04),
      Offset(1, 0),
      Offset(1, .36),
      Offset(.81, .47),
      Offset(.65, .32),
    ]);
    _drawArea(canvas, size, const Color(0xFFDDE8D8), const [
      Offset(0, .74),
      Offset(.22, .64),
      Offset(.31, 1),
      Offset(0, 1),
    ]);

    _drawRiver(canvas, size);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(-.04, .13),
          Offset(.25, .26),
          Offset(.49, .34),
          Offset(.76, .22),
          Offset(1.04, .08),
        ],
        width: 7);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(-.04, .2),
          Offset(.25, .33),
          Offset(.5, .41),
          Offset(.77, .29),
          Offset(1.04, .15),
        ],
        width: 2.5);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(.46, -.1),
          Offset(.37, .21),
          Offset(.25, .54),
          Offset(.08, 1.1),
        ],
        width: 6);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(.62, -.1),
          Offset(.51, .2),
          Offset(.4, .57),
          Offset(.27, 1.1),
        ],
        width: 6);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(1.1, .34),
          Offset(.83, .46),
          Offset(.6, .58),
          Offset(.43, 1.08),
        ],
        width: 6);
    _drawRoad(
        canvas,
        size,
        const [
          Offset(-.08, .59),
          Offset(.24, .64),
          Offset(.52, .71),
          Offset(.78, .82),
          Offset(1.08, .94),
        ],
        width: 4);
  }

  void _drawArea(
    Canvas canvas,
    Size size,
    Color color,
    List<Offset> normalizedPoints,
  ) {
    final path = Path()
      ..moveTo(normalizedPoints.first.dx * size.width,
          normalizedPoints.first.dy * size.height);
    for (final point in normalizedPoints.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawRiver(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(-size.width * .05, size.height * .77)
      ..cubicTo(
        size.width * .19,
        size.height * .62,
        size.width * .3,
        size.height * .77,
        size.width * .48,
        size.height * .66,
      )
      ..cubicTo(
        size.width * .69,
        size.height * .55,
        size.width * .82,
        size.height * .72,
        size.width * 1.05,
        size.height * .55,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFB7D9E2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawRoad(
    Canvas canvas,
    Size size,
    List<Offset> normalizedPoints, {
    required double width,
  }) {
    final path = Path()
      ..moveTo(
        normalizedPoints.first.dx * size.width,
        normalizedPoints.first.dy * size.height,
      );
    for (final point in normalizedPoints.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFC9D2CD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CommunityMapPainter oldDelegate) => false;
}
