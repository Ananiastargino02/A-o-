import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Grafico de linha do RPM ao vivo (ultimas ~60 amostras).
class RpmChart extends StatelessWidget {
  final List<double> dados;
  const RpmChart({super.key, required this.dados});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (int i = 0; i < dados.length; i++) FlSpot(i.toDouble(), dados[i]),
    ];
    final ultimo = dados.isNotEmpty ? dados.last : 0;
    final redline = ultimo >= 6000;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('RPM · AO VIVO',
                  style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
              const Spacer(),
              Text('${ultimo.toInt()}',
                  style: TextStyle(
                      color: redline ? VColors.red : VColors.cyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: dados.length < 2
                ? const Center(
                    child: Text('coletando dados...',
                        style: TextStyle(color: VColors.textFaint, fontSize: 12)))
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 8000,
                      minX: 0,
                      maxX: (dados.length - 1).toDouble(),
                      clipData: FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 2000,
                        getDrawingHorizontalLine: (v) =>
                            const FlLine(color: VColors.line, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: 2000,
                            getTitlesWidget: (v, meta) => Text(
                              '${(v / 1000).toInt()}k',
                              style: const TextStyle(color: VColors.textFaint, fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.25,
                          color: redline ? VColors.red : VColors.cyan,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: (redline ? VColors.red : VColors.cyan)
                                .withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
