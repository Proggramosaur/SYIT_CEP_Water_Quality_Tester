import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('waterData');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late MqttServerClient client;
  late Box box;
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _waveController;

  double ph = 0;
  double tds = 0;
  double turbidity = 0;
  String status = "Waiting...";
  String connection = "Connecting...";

  @override
  void initState() {
    super.initState();
    box = Hive.box('waterData');

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    connectMQTT();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> connectMQTT() async {
    client = MqttServerClient('broker.hivemq.com', '');
    client.port = 1883;
    client.keepAlivePeriod = 20;

    client.onConnected = () {
      setState(() => connection = "Connected");
      client.subscribe("water/device/data", MqttQos.atMostOnce);
    };

    client.onDisconnected = () {
      setState(() => connection = "Disconnected");
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean();

    client.connectionMessage = connMessage;

    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
    }

    client.updates?.listen(onMessage);
  }

  void onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    final recMess = events[0].payload as MqttPublishMessage;
    final payload =
    MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    final data = jsonDecode(payload);

    setState(() {
      ph = (data['ph'] ?? 0).toDouble();
      tds = (data['tds'] ?? 0).toDouble();
      turbidity = (data['turbidity'] ?? 0).toDouble();
      status = data['status'] ?? "Unknown";
    });

    box.add({
      'ph': ph,
      'tds': tds,
      'turbidity': turbidity,
    });

    while (box.length > 30) {
      box.deleteAt(0);
    }

    setState(() {});
  }

  List<FlSpot> getSpots(String key) {
    List<FlSpot> spots = [];
    for (int i = 0; i < box.length; i++) {
      final value = (box.getAt(i)[key] ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), value));
    }
    return spots;
  }

  double getMinY(String key) {
    if (box.isEmpty) return 0;
    double min = (box.getAt(0)[key] ?? 0).toDouble();
    for (int i = 0; i < box.length; i++) {
      double value = (box.getAt(i)[key] ?? 0).toDouble();
      if (value < min) min = value;
    }
    return min;
  }

  double getMaxY(String key) {
    if (box.isEmpty) return 0;
    double max = (box.getAt(0)[key] ?? 0).toDouble();
    for (int i = 0; i < box.length; i++) {
      double value = (box.getAt(i)[key] ?? 0).toDouble();
      if (value > max) max = value;
    }
    return max;
  }

  Widget buildChart(String title, String key, Color color1, Color color2) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a1a2e).withOpacity(0.6),
            const Color(0xFF16213e).withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Animated background mesh
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: MeshBackgroundPainter(
                      animation: _waveController.value,
                      color: color1.withOpacity(0.03),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color1, color2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: color1.withOpacity(0.5),
                              blurRadius: 12,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          _getIconForKey(key),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color1.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: color1.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color1,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color1,
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color1,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 180,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: box.length > 0 ? box.length.toDouble() - 1 : 0,
                        minY: getMinY(key) - 5,
                        maxY: getMaxY(key) + 5,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: (() {
                            final interval = (getMaxY(key) - getMinY(key)) / 3;
                            return interval == 0 ? 1.0 : interval;
                          })(),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: getSpots(key),
                            isCurved: true,
                            preventCurveOverShooting: true,
                            curveSmoothness: 0.4,
                            gradient: LinearGradient(
                              colors: [color1, color2],
                            ),
                            barWidth: 3.5,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  color1.withOpacity(0.3),
                                  color2.withOpacity(0.1),
                                  Colors.transparent,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForKey(String key) {
    switch (key) {
      case 'ph':
        return Icons.water_drop_outlined;
      case 'tds':
        return Icons.science_outlined;
      case 'turbidity':
        return Icons.blur_circular;
      default:
        return Icons.analytics_outlined;
    }
  }

  Widget buildMetricCard(
      String label,
      String value,
      String unit,
      Color color1,
      Color color2,
      IconData icon,
      ) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a1a2e).withOpacity(0.8),
            const Color(0xFF16213e).withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Rotating gradient background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationController.value * 2 * math.pi,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            color1.withOpacity(0.15),
                            Colors.transparent,
                            color2.withOpacity(0.1),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color1.withOpacity(0.3),
                              color2.withOpacity(0.2),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color1.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: color1,
                          size: 24,
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color1,
                              boxShadow: [
                                BoxShadow(
                                  color: color1.withOpacity(0.8),
                                  blurRadius: 10 + (_pulseController.value * 5),
                                  spreadRadius: 2 + (_pulseController.value * 2),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.5),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [color1, color2],
                            ).createShader(bounds),
                            child: Text(
                              value,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                          if (unit.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 6),
                              child: Text(
                                unit,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connection == "Connected";
    bool isSafe = status.contains("SAFE");

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0f0c29),
              Color(0xFF302b63),
              Color(0xFF24243e),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Animated particles background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ParticlesPainter(
                      animation: _rotationController.value,
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => const LinearGradient(
                                  colors: [
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                    Color(0xFFf093fb),
                                  ],
                                ).createShader(bounds),
                                child: const Text(
                                  "AQUASENSE",
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Advanced Water Quality Monitor",
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white.withOpacity(0.4),
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(width: 10,),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isConnected
                                  ? [
                                const Color(0xFF11998e).withOpacity(0.3),
                                const Color(0xFF38ef7d).withOpacity(0.2),
                              ]
                                  : [
                                const Color(0xFFeb3349).withOpacity(0.3),
                                const Color(0xFFF45C43).withOpacity(0.2),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isConnected
                                  ? const Color(0xFF38ef7d).withOpacity(0.5)
                                  : const Color(0xFFeb3349).withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isConnected
                                          ? const Color(0xFF38ef7d)
                                          : const Color(0xFFeb3349),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isConnected
                                              ? const Color(0xFF38ef7d)
                                              .withOpacity(_pulseController.value)
                                              : const Color(0xFFeb3349)
                                              .withOpacity(_pulseController.value),
                                          blurRadius: 12,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Text(
                                connection.toUpperCase(),
                                style: TextStyle(
                                  color: isConnected
                                      ? const Color(0xFF38ef7d)
                                      : const Color(0xFFeb3349),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Metrics Grid
                    Row(
                      children: [
                        Expanded(
                          child: buildMetricCard(
                            "pH Level",
                            ph.toStringAsFixed(2),
                            "",
                            const Color(0xFF667eea),
                            const Color(0xFF764ba2),
                            Icons.water_drop_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildMetricCard(
                            "TDS",
                            tds.toStringAsFixed(1),
                            "ppm",
                            const Color(0xFF11998e),
                            const Color(0xFF38ef7d),
                            Icons.science_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    buildMetricCard(
                      "Turbidity",
                      turbidity.toStringAsFixed(1),
                      "NTU",
                      const Color(0xFFf093fb),
                      const Color(0xFFf5576c),
                      Icons.blur_circular,
                    ),

                    const SizedBox(height: 24),

                    // Status Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          colors: isSafe
                              ? [
                            const Color(0xFF11998e),
                            const Color(0xFF38ef7d),
                          ]
                              : [
                            const Color(0xFFeb3349),
                            const Color(0xFFF45C43),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSafe
                                ? const Color(0xFF11998e).withOpacity(0.4)
                                : const Color(0xFFeb3349).withOpacity(0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isSafe
                                  ? Icons.verified_outlined
                                  : Icons.warning_amber_outlined,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "SYSTEM STATUS",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withOpacity(0.7),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Charts
                    buildChart(
                      "pH Analytics",
                      "ph",
                      const Color(0xFF667eea),
                      const Color(0xFF764ba2),
                    ),
                    buildChart(
                      "TDS Analytics",
                      "tds",
                      const Color(0xFF11998e),
                      const Color(0xFF38ef7d),
                    ),
                    buildChart(
                      "Turbidity Analytics",
                      "turbidity",
                      const Color(0xFFf093fb),
                      const Color(0xFFf5576c),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for animated mesh background
class MeshBackgroundPainter extends CustomPainter {
  final double animation;
  final Color color;

  MeshBackgroundPainter({required this.animation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const gridSize = 30.0;
    final offset = animation * gridSize;

    for (double i = -gridSize; i < size.width + gridSize; i += gridSize) {
      for (double j = -gridSize; j < size.height + gridSize; j += gridSize) {
        final x = i + (math.sin((j + offset) / 30) * 10);
        final y = j + (math.cos((i + offset) / 30) * 10);
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom painter for animated particles
class ParticlesPainter extends CustomPainter {
  final double animation;

  ParticlesPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 30; i++) {
      final x = (i * 37.0 + animation * 100) % size.width;
      final y = (i * 53.0 + animation * 150) % size.height;
      final radius = 1 + (i % 3);
      canvas.drawCircle(Offset(x, y), radius.toDouble(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}