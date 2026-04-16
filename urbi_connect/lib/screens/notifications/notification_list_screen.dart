import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/notification.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/screens/incidents/incident_detail_screen.dart';
import 'package:urbi_connect/screens/incidents/responsible_incident_detail_screen.dart';
import 'package:urbi_connect/services/notification_service.dart';

class NotificationListScreen extends StatelessWidget {
  const NotificationListScreen({super.key});

  Future<void> _handleNotificationTap(
      BuildContext context, AppNotification notification) async {
    final notificationService = NotificationService();
    if (!notification.isRead) {
      await notificationService.markAsRead(notification.id);
    }

    if (notification.referenceId == null || notification.referenceId!.isEmpty) {
      return;
    }

    try {
      if (notification.type == 'chat') {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ChatScreen(incidentId: notification.referenceId!),
            ),
          );
        }
      } else if (notification.type == 'incidencia' ||
          notification.type == 'recordatorio' ||
          notification.type == 'incidencia_eliminada') {
        // Obtener la incidencia y el perfil del usuario para saber a qué pantalla ir
        final incidentDoc = await FirebaseFirestore.instance
            .collection('Incidencia')
            .doc(notification.referenceId)
            .get();
        if (!incidentDoc.exists) return;

        final incident = Incident.fromFirestore(incidentDoc);
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (!profileDoc.exists) return;

        final profile = UserProfile.fromMap(profileDoc.data()!, user.uid);

        if (context.mounted) {
          if (profile.role == 'Responsable' ||
              profile.role == 'Responsable Municipal') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ResponsibleIncidentDetailScreen(incident: incident),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => IncidentDetailScreen(incident: incident),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error al navegar desde notificación: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
          child: Text('Inicia sesión para ver tus notificaciones'));
    }

    return StreamBuilder<List<AppNotification>>(
      stream: notificationService.getNotifications(user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error al cargar notificaciones'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final notifications = snapshot.data ?? [];

        if (notifications.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 80, color: Colors.grey),
                SizedBox(height: 16),
                Text('Tu buzón está vacío.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: notification.isRead ? Colors.white : Colors.blue[50],
              child: ListTile(
                leading: Icon(
                  notification.isRead
                      ? Icons.notifications_none
                      : Icons.notifications_active,
                  color: notification.isRead ? Colors.grey : Colors.blue,
                ),
                title: Text(
                  notification.title,
                  style: TextStyle(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notification.body),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(notification.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                onTap: () => _handleNotificationTap(context, notification),
              ),
            );
          },
        );
      },
    );
  }
}
