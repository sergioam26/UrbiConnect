import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentListScreen extends StatelessWidget {
  const IncidentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return StreamBuilder<List<Incident>>(
      stream: dbService.getIncidents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error al cargar datos'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final incidents = snapshot.data ?? [];

        return ListView.builder(
          itemCount: incidents.length,
          itemBuilder: (context, index) {
            final incident = incidents[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: incident.imageUrl != null
                    ? Image.network(
                        incident.imageUrl!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.image_not_supported),
                title: Text(
                  incident.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy').format(incident.createdAt),
                ),
                trailing: _buildStatusChip(incident.status),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'pendiente':
        color = Colors.orange;
        break;
      case 'en proceso':
        color = Colors.blue;
        break;
      case 'resuelta':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      label: Text(
        status,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
    );
  }
}
