import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

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
            _buildIncidentStats(),
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
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
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
            _buildStatCard('Ciudadanos', citizens.toString(), Colors.blue),
            const SizedBox(width: 12),
            _buildStatCard('Personal', responsibles.toString(), Colors.teal),
            const SizedBox(width: 12),
            _buildStatCard('Admins', admins.toString(), Colors.purple),
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
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Incidencia')
          .where('es_eliminada', isEqualTo: false)
          .snapshots(),
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
                  sections: [
                    PieChartSectionData(
                        value: pending.toDouble(),
                        color: Colors.orange,
                        title: 'Pend.',
                        radius: 50,
                        titleStyle:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                    PieChartSectionData(
                        value: inProcess.toDouble(),
                        color: Colors.blue,
                        title: 'Proc.',
                        radius: 50,
                        titleStyle:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                    PieChartSectionData(
                        value: resolved.toDouble(),
                        color: Colors.green,
                        title: 'Resu.',
                        radius: 50,
                        titleStyle:
                            const TextStyle(color: Colors.white, fontSize: 10)),
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

  Widget _buildCategoryActivity() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Incidencia').snapshots(),
      builder: (context, incSnapshot) {
        if (!incSnapshot.hasData) {
          return const SizedBox();
        }

        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('Categoria').get(),
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
                    toY: count == 0 ? 1.0 : count.toDouble(),
                    color: count == 0
                        ? Colors.transparent
                        : Theme.of(context).primaryColor,
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
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                height: 1.1),
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
                              leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Theme.of(context).primaryColor,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                  String catName =
                                      cats[groupIndex].get('nombre') ?? '';
                                  int realCount = rod.toY <= 1.0 &&
                                          incs
                                              .where((inc) =>
                                                  inc.get('id_categoria') ==
                                                  cats[groupIndex].id)
                                              .isEmpty
                                      ? 0
                                      : rod.toY.toInt();
                                  return BarTooltipItem(
                                    '$catName\n',
                                    const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                    children: [
                                      TextSpan(
                                        text: '$realCount incidencias',
                                        style: const TextStyle(
                                            color: Colors.white,
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
                    const Text('Incidencias registradas por categoría',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
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
