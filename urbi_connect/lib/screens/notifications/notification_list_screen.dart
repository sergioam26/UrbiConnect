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
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
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
          notification.type == 'incidencia_editada' ||
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
      } else if (notification.type == 'soporte' ||
          notification.type == 'chat_soporte') {
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
            .get();
        final isAdmin =
            profileDoc.exists && profileDoc.data()?['rol'] == 'Admin';

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupportChatScreen(
                ticketId: notification.referenceId!,
                isAdmin: isAdmin,
              ),
            ),
          );
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
            final isOfficial = notification.isOfficial;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: isOfficial ? 4 : 1,
              shadowColor: isOfficial
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.black12,
              color: isOfficial
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.1)
                  : (notification.isRead
                      ? Theme.of(context).cardColor
                      : Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.05)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isOfficial
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5)
                    : BorderSide.none,
              ),
              child: ListTile(
                leading: SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      if (!notification.isRead) {
                        await notificationService.markAsRead(notification.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Notificación marcada como leída'),
                                duration: Duration(seconds: 1)),
                          );
                        }
                      }
                    },
                    icon: Icon(
                      isOfficial
                          ? Icons.verified_user_rounded
                          : (notification.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active),
                      color: isOfficial
                          ? Theme.of(context).colorScheme.primary
                          : (notification.isRead
                              ? Theme.of(context).textTheme.bodySmall?.color
                              : Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.isRead
                              ? FontWeight.normal
                              : FontWeight.bold,
                          color: isOfficial
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    if (isOfficial)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'OFICIAL',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.body,
                      style: TextStyle(
                        color: isOfficial
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(notification.createdAt),
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color),
                        ),
                        if (isOfficial)
                          Text(
                            'Administración UrbiConnect',
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600),
                          ),
                      ],
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
