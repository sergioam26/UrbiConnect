import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/services/database_service.dart';

class ResponsibleIncidentDetailScreen extends StatefulWidget {
  final Incident incident;

  const ResponsibleIncidentDetailScreen({super.key, required this.incident});

  @override
  State<ResponsibleIncidentDetailScreen> createState() =>
      _ResponsibleIncidentDetailScreenState();
}

class _ResponsibleIncidentDetailScreenState
    extends State<ResponsibleIncidentDetailScreen> {
  late String _currentStatus;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.incident.status;
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

  Future<void> _updateStatus(String? newStatus) async {
    if (newStatus == null || newStatus == _currentStatus) return;

    setState(() => _isUpdating = true);
    try {
      await DatabaseService()
          .updateIncidentStatus(widget.incident.id, newStatus);
      setState(() {
        _currentStatus = newStatus;
        _isUpdating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estado actualizado a: $newStatus')),
        );
      }
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar el estado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de incidencia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChatScreen(incidentId: widget.incident.id),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((widget.incident.imageUrls ?? []).isNotEmpty)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.incident.imageUrls!.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _showFullImage(
                          context, widget.incident.imageUrls![index]),
                      child: Container(
                        width: MediaQuery.of(context).size.width - 32,
                        margin: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            widget.incident.imageUrls![index],
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (widget.incident.imageUrl != null)
              GestureDetector(
                onTap: () => _showFullImage(context, widget.incident.imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.incident.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text('Cambiar estado:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _isUpdating
                ? const LinearProgressIndicator()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _currentStatus,
                        isExpanded: true,
                        items: ['pendiente', 'en proceso', 'resuelta']
                            .map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                                value[0].toUpperCase() + value.substring(1)),
                          );
                        }).toList(),
                        onChanged: _updateStatus,
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildDetailRow(
                'Reportado el:',
                DateFormat('dd/MM/yyyy HH:mm')
                    .format(widget.incident.createdAt)),
            if (widget.incident.updatedAt != null)
              _buildDetailRow(
                  'Editado el:',
                  DateFormat('dd/MM/yyyy HH:mm')
                      .format(widget.incident.updatedAt!)),
            _buildDetailRow('Título:', widget.incident.title),
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
                return _buildDetailRow('Categoría:', catName);
              },
            ),
            _buildDetailRow('Descripción:', widget.incident.description),
            const Text('Reportado por:',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.incident.userId)
                  .get(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Text('Cargando reportero...',
                      style: TextStyle(fontSize: 16));
                }
                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return Text(widget.incident.userId,
                      style: const TextStyle(fontSize: 16));
                }

                final userData = userSnap.data!.data() as Map<String, dynamic>;
                final String name = userData['nombre'] ?? '';
                final String surnames = userData['apellidos'] ?? '';
                final String username = userData['usuario'] ?? '';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$name $surnames',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    Text('@$username',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Ubicación:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.incident.latitude != 0 && widget.incident.longitude != 0)
              Container(
                key: ValueKey('map_cont_resp_${widget.incident.id}'),
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    key: ValueKey('map_resp_${widget.incident.id}'),
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                          widget.incident.latitude, widget.incident.longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('incident_loc'),
                        position: LatLng(widget.incident.latitude,
                            widget.incident.longitude),
                      ),
                    },
                  ),
                ),
              )
            else
              const Text('Ubicación no disponible',
                  style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ChatScreen(incidentId: widget.incident.id),
                    ),
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text('Abrir chat con ciudadano'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
