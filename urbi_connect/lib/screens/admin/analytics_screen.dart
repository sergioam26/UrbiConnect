import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Stream<QuerySnapshot> _userStream;
  late Stream<QuerySnapshot> _incidentStream;
  late Stream<QuerySnapshot> _activityIncidentStream;
  late Future<QuerySnapshot> _categoryFuture;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance.collection('users').snapshots();
    _incidentStream = FirebaseFirestore.instance
        .collection('Incidencia')
        .where('es_eliminada', isEqualTo: false)
        .snapshots();
    _activityIncidentStream =
        FirebaseFirestore.instance.collection('Incidencia').snapshots();
    _categoryFuture = FirebaseFirestore.instance.collection('Categoria').get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análisis de UrbiConnect')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumen general',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildUserStats(),
            const SizedBox(height: 24),
            Text('Estado de incidencias',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _IncidentStatsPie(stream: _incidentStream),
            const SizedBox(height: 24),
            Text('Actividad por categorías',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildCategoryActivity(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildUserStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final users = snapshot.data!.docs;
        final citizens = users
            .where((u) => u.get('rol').toString().toLowerCase() == 'ciudadano')
            .length;
        final responsibles = users
            .where((u) =>
                u.get('rol').toString().toLowerCase() == 'responsable' ||
                u.get('rol').toString().toLowerCase() ==
                    'responsable municipal')
            .length;
        final admins = users
            .where((u) => u.get('rol').toString().toLowerCase() == 'admin')
            .length;

        return Row(
          children: [
            _buildStatCard('Ciudadanos', citizens.toString(),
                Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            _buildStatCard('Personal', responsibles.toString(), Colors.teal),
            const SizedBox(width: 12),
            _buildStatCard('Admins', admins.toString(), Colors.blueGrey),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryActivity() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activityIncidentStream,
      builder: (context, incSnapshot) {
        if (!incSnapshot.hasData) {
          return const SizedBox();
        }

        return FutureBuilder<QuerySnapshot>(
          future: _categoryFuture,
          builder: (context, catSnapshot) {
            if (!catSnapshot.hasData) {
              return const SizedBox();
            }

            final cats = catSnapshot.data!.docs;
            final incs = incSnapshot.data!.docs;

            List<BarChartGroupData> groups = [];
            for (int i = 0; i < cats.length; i++) {
              final count = incs
                  .where((inc) => inc.get('id_categoria') == cats[i].id)
                  .length;
              groups.add(BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: count == 0 ? 0.1 : count.toDouble(),
                    color: count == 0
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white10
                            : Colors.black12)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.7)),
                    width: 16,
                    borderRadius: BorderRadius.circular(4),
                  )
                ],
              ));
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: 300,
                        width: cats.length * 80.0 >
                                MediaQuery.of(context).size.width
                            ? cats.length * 80.0
                            : MediaQuery.of(context).size.width - 48,
                        child: BarChart(
                          BarChartData(
                            barGroups: groups,
                            alignment: BarChartAlignment.spaceAround,
                            maxY: groups.isEmpty
                                ? 10
                                : groups
                                        .map((e) => e.barRods[0].toY)
                                        .reduce((a, b) => a > b ? a : b) +
                                    2,
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    int index = value.toInt();
                                    if (index >= 0 && index < cats.length) {
                                      String name =
                                          cats[index].get('nombre') ?? '';
                                      return SideTitleWidget(
                                        axisSide: meta.axisSide,
                                        space: 12,
                                        child: SizedBox(
                                          width: 70,
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              height: 1.1,
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                  reservedSize: 45,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) => Text(
                                    value.toInt().toString(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color),
                                  ),
                                  reservedSize: 24,
                                ),
                              ),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.1),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                  String catName =
                                      cats[groupIndex].get('nombre') ?? '';
                                  int realCount = rod.toY <= 0.1 &&
                                          incs
                                              .where((inc) =>
                                                  inc.get('id_categoria') ==
                                                  cats[groupIndex].id)
                                              .isEmpty
                                      ? 0
                                      : rod.toY.toInt();
                                  return BarTooltipItem(
                                    '$catName\n',
                                    TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                    children: [
                                      TextSpan(
                                        text: '$realCount incidencias',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer
                                                .withValues(alpha: 0.8),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Incidencias registradas por categoría',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _IncidentStatsPie extends StatefulWidget {
  final Stream<QuerySnapshot> stream;
  const _IncidentStatsPie({super.key, required this.stream});

  @override
  State<_IncidentStatsPie> createState() => _IncidentStatsPieState();
}

class _IncidentStatsPieState extends State<_IncidentStatsPie> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }
        final incidents = snapshot.data!.docs;
        final pending = incidents
            .where(
                (i) => i.get('estado').toString().toLowerCase() == 'pendiente')
            .length;
        final inProcess = incidents
            .where(
                (i) => i.get('estado').toString().toLowerCase() == 'en proceso')
            .length;
        final resolved = incidents
            .where(
                (i) => i.get('estado').toString().toLowerCase() == 'resuelta')
            .length;

        if (incidents.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: Text('No hay datos suficientes')),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          touchedIndex = -1;
                          return;
                        }
                        touchedIndex = pieTouchResponse
                            .touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  sections: [
                    PieChartSectionData(
                      value: pending.toDouble(),
                      color: Colors.orange,
                      title: touchedIndex == 0 ? '$pending\nPend.' : 'Pend.',
                      radius: touchedIndex == 0 ? 60 : 50,
                      titleStyle: TextStyle(
                        color: Colors.white,
                        fontSize: touchedIndex == 0 ? 14 : 10,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 2)
                        ],
                      ),
                    ),
                    PieChartSectionData(
                      value: inProcess.toDouble(),
                      color: Theme.of(context).colorScheme.primary,
                      title: touchedIndex == 1 ? '$inProcess\nProc.' : 'Proc.',
                      radius: touchedIndex == 1 ? 60 : 50,
                      titleStyle: TextStyle(
                        color: Colors.white,
                        fontSize: touchedIndex == 1 ? 14 : 10,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 2)
                        ],
                      ),
                    ),
                    PieChartSectionData(
                      value: resolved.toDouble(),
                      color: Colors.green,
                      title: touchedIndex == 2 ? '$resolved\nResu.' : 'Resu.',
                      radius: touchedIndex == 2 ? 60 : 50,
                      titleStyle: TextStyle(
                        color: Colors.white,
                        fontSize: touchedIndex == 2 ? 14 : 10,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 2)
                        ],
                      ),
                    ),
                  ],
                  centerSpaceRadius: 40,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
