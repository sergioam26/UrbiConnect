import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentDetailScreen extends StatelessWidget {
  final Incident incident;

  const IncidentDetailScreen({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de incidencia')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (incident.imageUrl != null)
              CachedNetworkImage(
                imageUrl: incident.imageUrl!,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 250,
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 250,
                  color: Colors.grey[200],
                  child: const Icon(Icons.error),
                ),
              )
            else
              Container(
                height: 200,
                width: double.infinity,
                color: Colors.grey[200],
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported,
                        size: 50, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Sin imagen disponible',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusChip(incident.status),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm')
                            .format(incident.createdAt),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('Categoria')
                        .doc(incident.categoryId)
                        .get(),
                    builder: (context, snapshot) {
                      String catName = incident.categoryId;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        catName = snapshot.data!.get('nombre');
                      }
                      return Text(
                        catName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Descripción:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    incident.description,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ubicación:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (incident.latitude != 0 && incident.longitude != 0)
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target:
                                LatLng(incident.latitude, incident.longitude),
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId('incident_loc'),
                              position:
                                  LatLng(incident.latitude, incident.longitude),
                              infoWindow:
                                  InfoWindow(title: incident.categoryId),
                            ),
                          },
                          //liteModeEnabled: true, // Desactivado temporalmente para evitar crashes nativos reportados
                          scrollGesturesEnabled: true,
                          zoomGesturesEnabled: true,
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: true,
                        ),
                      ),
                    )
                  else
                    const Center(child: Text('Ubicación no disponible')),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Acciones:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.notifications_active,
                        color: Colors.orange),
                    title: const Text('Enviar recordatorio al ayuntamiento'),
                    onTap: () async {
                      final success =
                          await DatabaseService().sendReminder(incident);

                      if (context.mounted) {
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Recordatorio enviado con éxito.')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Solo puedes enviar un recordatorio cada 3 días.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat, color: Colors.blue),
                    title: const Text('Chat con el responsable municipal'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatScreen(incidentId: incident.id),
                        ),
                      );
                    },
                  ),
                  if (FirebaseAuth.instance.currentUser?.uid ==
                      incident.userId) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      leading:
                          const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text('Eliminar incidencia',
                          style: TextStyle(color: Colors.red)),
                      onTap: () => _confirmDelete(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    FocusScope.of(context).unfocus();
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar incidencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                '¿Estás seguro de que deseas eliminar esta incidencia? Esta acción no se puede deshacer.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo de la eliminación',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, indica un motivo')),
                );
                return;
              }

              await DatabaseService()
                  .deleteIncident(incident.id, reasonController.text.trim());
              if (context.mounted) {
                Navigator.pop(context); // Cerrar diálogo
                Navigator.pop(context); // Volver a la lista
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Incidencia eliminada con éxito')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
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
    return Container(
      width: 100, // Fixed width for harmony
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
