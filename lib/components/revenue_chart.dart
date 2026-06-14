import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../services/database_service.dart';

class RevenueChart extends StatefulWidget {
  const RevenueChart({super.key});

  @override
  State<RevenueChart> createState() => _RevenueChartState();
}

class _RevenueChartState extends State<RevenueChart> {
  // 定義圖表顏色 (您可以修改這裡！)
  // 建議使用漸層色，讓線條看起來更高級
  final List<Color> gradientColors = [
    const Color(0xFF64B5F6), // 起點：品牌淺藍色
    const Color(0xFFCE93D8), // 終點：亮紫色
  ];

  @override
  Widget build(BuildContext context) {
    // 取得過去 7 天的範圍
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Weekly Revenue Trend',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: StreamBuilder<List<Order>>(
            stream: DatabaseService().getOrdersByDateRangeStream(start, end),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = _processData(snapshot.data ?? [], start);
              final maxY =
                  (data.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.2)
                      .clamp(1000.0, double.infinity);

              return LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1000,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white.withValues(alpha: 0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final date = start.add(Duration(days: value.toInt()));
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('E').format(date),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1000,
                        reservedSize: 38,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(
                              color: const Color.fromARGB(255, 9, 9, 9),
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      gradient: LinearGradient(colors: gradientColors),
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: gradientColors
                              .map((color) => color.withValues(alpha: 0.2))
                              .toList(),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<FlSpot> _processData(List<Order> orders, DateTime start) {
    final dailyTotals = List<double>.filled(7, 0.0);

    for (final order in orders) {
      if (order.createdAt == null) continue;
      final difference = order.createdAt!.difference(start).inDays;
      if (difference >= 0 && difference < 7) {
        dailyTotals[difference] += order.total;
      }
    }

    return List.generate(
      7,
      (index) => FlSpot(index.toDouble(), dailyTotals[index]),
    );
  }
}
