import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/screens/incidents/incident_edit_screen.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Incident incident;

  const IncidentDetailScreen({super.key, required this.incident});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final List<String> allImages = widget.incident.imageUrls ??
        (widget.incident.imageUrl != null ? [widget.incident.imageUrl!] : []);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de incidencia')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allImages.isNotEmpty)
              SizedBox(
                height: 250,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: allImages.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _showFullImage(context, allImages[index]),
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(0),
                          child: CachedNetworkImage(
                            imageUrl: allImages[index],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                  child: CircularProgressIndicator()),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.error),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
            if (allImages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    'Desliza para ver más imágenes (${allImages.length})',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
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
                      _buildStatusChip(widget.incident.status),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Reportado: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.incident.createdAt)}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                          if (widget.incident.updatedAt != null)
                            Text(
                              'Editado: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.incident.updatedAt!)}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('Categoria')
                        .doc(widget.incident.categoryId)
                        .get(),
                    builder: (context, snapshot) {
                      String catName = widget.incident.categoryId;
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
                  Text(
                    widget.incident.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Descripción:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.incident.description,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Reportado por:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.incident.userId)
                        .get(),
                    builder: (context, userSnap) {
                      if (userSnap.connectionState == ConnectionState.waiting) {
                        return const Text('Cargando reportero...');
                      }
                      if (!userSnap.hasData || !userSnap.data!.exists) {
                        return Text(widget.incident.userId,
                            style: const TextStyle(color: Colors.grey));
                      }

                      final userData =
                          userSnap.data!.data() as Map<String, dynamic>;
                      final String name = userData['nombre'] ?? '';
                      final String surnames = userData['apellidos'] ?? '';
                      final String username = userData['usuario'] ?? '';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$name $surnames',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                          Text('@$username',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600])),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ubicación:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (widget.incident.latitude != 0 &&
                      widget.incident.longitude != 0)
                    Container(
                      key: ValueKey('map_cont_${widget.incident.id}'),
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          key: ValueKey('map_${widget.incident.id}'),
                          initialCameraPosition: CameraPosition(
                            target: LatLng(widget.incident.latitude,
                                widget.incident.longitude),
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId('incident_loc'),
                              position: LatLng(widget.incident.latitude,
                                  widget.incident.longitude),
                              infoWindow:
                                  InfoWindow(title: widget.incident.categoryId),
                            ),
                          },
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
                  if (FirebaseAuth.instance.currentUser?.uid ==
                          widget.incident.userId &&
                      widget.incident.status.toLowerCase() != 'resuelta')
                    ListTile(
                      leading: const Icon(Icons.notifications_active,
                          color: Colors.orange),
                      title: const Text('Enviar recordatorio al ayuntamiento'),
                      onTap: () async {
                        final success = await DatabaseService()
                            .sendReminder(widget.incident);

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
                    title: const Text('Chat con el responsable'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatScreen(incidentId: widget.incident.id),
                        ),
                      );
                    },
                  ),
                  if (FirebaseAuth.instance.currentUser?.uid ==
                          widget.incident.userId &&
                      widget.incident.status.toLowerCase() != 'resuelta') ...[
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.edit_note_rounded,
                          color: Colors.blue),
                      title: const Text('Editar incidencia'),
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => IncidentEditScreen(
                                  incident: widget.incident)),
                        );
                        if (result == true) {
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text('Eliminar incidencia',
                          style: TextStyle(color: Colors.red)),
                      onTap: () => _confirmDelete(context),
                    ),
                  ],
                  if (FirebaseAuth.instance.currentUser?.uid ==
                          widget.incident.userId &&
                      widget.incident.status.toLowerCase() == 'resuelta')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Esta incidencia ha sido resuelta y no se puede editar ni eliminar.',
                        style: TextStyle(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                            fontSize: 13),
                        textAlign: TextAlign.center,
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

  void _showFullImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(imageUrl),
            ),
          ),
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

              await DatabaseService().deleteIncident(
                  widget.incident.id, reasonController.text.trim());
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
