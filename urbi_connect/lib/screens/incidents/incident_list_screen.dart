import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/incidents/incident_detail_screen.dart';
import 'package:urbi_connect/screens/incidents/responsible_incident_detail_screen.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentListScreen extends StatelessWidget {
  const IncidentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Usuario no autenticado'));
    }

    return StreamBuilder<UserProfile?>(
      stream: dbService.getUserProfile(user.uid),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) {
          return const Center(child: Text('Error al cargar perfil'));
        }
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final profile = userSnapshot.data;
        if (profile == null) {
          return const Center(child: Text('Perfil no encontrado'));
        }

        return StreamBuilder<List<Incident>>(
          stream: dbService.getIncidents(profile),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('Error en stream de incidencias: ${snapshot.error}');
              return const Center(child: Text('Error al cargar datos'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final incidents = snapshot.data ?? [];

            if (incidents.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 80, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No hay incidencias reportadas aún.',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: incidents.length,
              padding: const EdgeInsets.only(bottom: 80),
              itemBuilder: (context, index) {
                final incident = incidents[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: incident.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: incident.imageUrl!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200]),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_not_supported),
                            ),
                    ),
                    title: Text(
                      incident.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('Categoria')
                              .doc(incident.categoryId)
                              .get(),
                          builder: (context, catSnapshot) {
                            String catName = incident.categoryId;
                            if (catSnapshot.hasData &&
                                catSnapshot.data!.exists) {
                              catName = catSnapshot.data!.get('nombre');
                            }
                            return Text(catName,
                                style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 12));
                          },
                        ),
                        Text(
                            DateFormat('dd/MM/yyyy HH:mm')
                                .format(incident.createdAt),
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    trailing: _buildStatusChip(incident.status),
                    onTap: () {
                      if (profile.role == 'Responsable' ||
                          profile.role == 'Responsable Municipal') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ResponsibleIncidentDetailScreen(
                                    incident: incident),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                IncidentDetailScreen(incident: incident),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
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
        status[0].toUpperCase() + status.substring(1),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
    );
  }
}
