import 'dart:math' as math;

import 'package:adomob/m_build_from_json.dart';
import 'package:adomob/my_mqtt/state_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// ConsumerWidget for riverpod
class TemperaturesParetoWidget extends ConsumerWidget {
  const TemperaturesParetoWidget({super.key, required this.bundle});
  final Bundle bundle;

  @override
  Widget build(BuildContext context, ref) {
    //******************* reception des donnees telemetry et autres ************/
    final deviceState = ref.watch(getDeviceStateProvider(bundle.master));
    Map<String, dynamic> masterData;
    masterData = deviceState['telemetry'];
    List<Map<String, dynamic>?> slaveData = [];

    for (var slave in bundle.listSlaves) {
      final slaveState = ref.watch(getDeviceStateProvider(slave));
      if (slaveState.isNotEmpty) {
        slaveData.add(slaveState['telemetry']);
      } else {
        slaveData.add({});
      }
    }

    final isEmpty = masterData.isEmpty;
    final isReady = deviceState.isNotEmpty && !isEmpty;
    final masterTemperature = isEmpty ? 0.0 : (masterData['Temperature'] ?? 0).toDouble();

    final labels = bundle.location.split('/');

    // Get the slave temperature data and add the "Autres" data
    final slaveTemperatureData = getSlaveTemperatureData(slaveData, labels);
    if (slaveTemperatureData.isEmpty) {
      slaveTemperatureData.add(SlaveTemperatureData('En attente', 0));
    }

    // Sort the data from largest to smallest value
    slaveTemperatureData.sort((a, b) => b.temperature.compareTo(a.temperature));

    return Opacity(
        opacity: isReady ? 1 : 0.55,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;
            final chartWidth = math.max(availableWidth, slaveTemperatureData.length * 45.0);

            return Column(
              children: [
                Container(
                  width: MediaQuery.of(context).size.width,
                  margin: const EdgeInsets.all(8.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        isEmpty ? '${labels[0]} --°C' : '${labels[0]} ${(masterTemperature).toStringAsFixed(1)}°C',
                        style: const TextStyle(fontSize: 18.0),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth, // Fill the viewport; scroll when the bars need more space.
                    child: SfCartesianChart(
                      primaryXAxis: const CategoryAxis(
                        labelRotation: 90, // Rotate the labels
                      ),
                      primaryYAxis: const NumericAxis(
                        labelFormat: '{value}°C', // Add unit to y-axis labels
                      ),
                      legend: const Legend(isVisible: false), // Hide the legend
                      tooltipBehavior: TooltipBehavior(enable: false),
                      isTransposed: true, // Make the chart horizontal
                      enableAxisAnimation: false,
                      series: <CartesianSeries>[
                        BarSeries<SlaveTemperatureData, String>(
                          dataSource: slaveTemperatureData,
                          xValueMapper: (SlaveTemperatureData data, _) => data.slaveLabel,
                          yValueMapper: (SlaveTemperatureData data, _) => data.temperature,
                          spacing: 0.01,
                          width: 0.99,
                          animationDuration: 0,
                          dataLabelSettings: DataLabelSettings(
                            isVisible: true,
                            textStyle: const TextStyle(
                              fontSize: 10, // Ensure text size is set to 10
                              color: Colors.black,
                            ),
                            labelAlignment: ChartDataLabelAlignment.outer,
                            labelPosition: ChartDataLabelPosition.outside,
                            builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                              final value = data.temperature;
                              final formattedValue = value.toStringAsFixed(1);
                              return Text(
                                formattedValue,
                                style: const TextStyle(fontSize: 10), // Ensure text size is set to 10
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ));
  }

  List<SlaveTemperatureData> getSlaveTemperatureData(List<Map<String, dynamic>?> slaveData, List<String> labels) {
    List<SlaveTemperatureData> data = [];
    for (int i = 0; i < slaveData.length; i++) {
      final slaveLabel = labels.length > i + 1 ? labels[i + 1] : 'Slave ${i + 1}';
      final temperature = (slaveData[i]?['Temperature'] ?? 0).toDouble();
      data.add(SlaveTemperatureData(slaveLabel, temperature));
    }
    return data;
  }
}

class SlaveTemperatureData {
  SlaveTemperatureData(this.slaveLabel, this.temperature);
  final String slaveLabel;
  final double temperature;
}
