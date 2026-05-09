import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/support_service.dart';

class SupportScreen extends StatefulWidget {
  final bool isAdmin;
  const SupportScreen({super.key, this.isAdmin = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final SupportService _supportService = SupportService();

  void _showNewTicketDialog() {
    final controller = TextEditingController();
    String? imageUrl;
    bool isSaving = false;
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Reportar problema'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Describe el problema con la aplicación...',
                    hintStyle: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 12),
                if (imageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                          image: NetworkImage(imageUrl!), fit: BoxFit.cover),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setDialogState(() => imageUrl = null),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 50,
                            maxWidth: 1024,
                            maxHeight: 1024,
                          );
                          if (image == null) return;

                          // Validación de tipo de archivo mejorada
                          final String fileName = image.name.toLowerCase();
                          final String? mimeType =
                              image.mimeType?.toLowerCase();
                          final List<String> allowedExtensions = [
                            '.jpg',
                            '.jpeg',
                            '.png',
                            '.webp',
                            '.heic',
                            '.heif',
                            '.gif',
                            '.svg',
                            '.svgz',
                            '.bmp',
                            '.ico',
                            '.tiff',
                            '.tif',
                            '.jfif',
                            '.pjp',
                            '.apng',
                            '.xbm',
                            '.jxl',
                            '.jpe',
                            '.pjpeg',
                            '.avif'
                          ];

                          bool isImage = false;
                          if (mimeType != null &&
                              mimeType.startsWith('image/')) {
                            isImage = true;
                          } else {
                            for (var ext in allowedExtensions) {
                              if (fileName.endsWith(ext)) {
                                isImage = true;
                                break;
                              }
                            }
                          }

                          if (!isImage) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Error: "${image.name}" no es una imagen permitida.')),
                              );
                            }
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          final dbService = DatabaseService();
                          String? url;
                          if (kIsWeb) {
                            final bytes = await image.readAsBytes();
                            url = await dbService.uploadImageWeb(bytes);
                          } else {
                            url = await dbService.uploadImage(File(image.path));
                          }
                          if (url == null) {
                            setDialogState(() {
                              isSaving = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Error al subir la imagen. Por favor, inténtalo de nuevo.')),
                              );
                            }
                            return;
                          }
                          setDialogState(() {
                            imageUrl = url;
                            isSaving = false;
                          });
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                  label: const Text('Adjuntar imagen'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: (isSaving ||
                      (controller.text.trim().isEmpty && imageUrl == null))
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        await _supportService.createSupportTicket(
                          controller.text.trim(),
                          imageUrl: imageUrl,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Ticket enviado. Espera a que un administrador responda.')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      } finally {
                        if (context.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enviar'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Inicia sesión')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Soporte técnico')),
      body: StreamBuilder<QuerySnapshot>(
        stream: widget.isAdmin
            ? _supportService.getAllTickets()
            : _supportService.getUserTickets(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Error al cargar tickets:\n${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Sort in memory to avoid index requirements
          final tickets = snapshot.data!.docs;
          final List<QueryDocumentSnapshot> sortedTickets =
              List<QueryDocumentSnapshot>.from(tickets);
          sortedTickets.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            final dateA = (dataA['fecha'] as Timestamp?) ??
                (dataA['fecha_creacion'] as Timestamp?) ??
                Timestamp.now();
            final dateB = (dataB['fecha'] as Timestamp?) ??
                (dataB['fecha_creacion'] as Timestamp?) ??
                Timestamp.now();
            return dateB.compareTo(dateA);
          });

          if (sortedTickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.support_agent, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No tienes tickets de soporte activos',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedTickets.length,
            itemBuilder: (context, index) {
              final ticket = sortedTickets[index];
              final data = ticket.data() as Map<String, dynamic>;
              final date =
                  (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();

              String titleText = data['descripcion'];
              String subtitlePrefix = '';

              if (widget.isAdmin) {
                if (data['es_invitado'] == true) {
                  subtitlePrefix = 'Invitado: ${data['email_invitado']} • ';
                } else if (data['id_usuario'] != null) {
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(data['id_usuario'])
                        .get(),
                    builder: (context, userSnap) {
                      String username = 'Usuario';
                      String? role;
                      if (userSnap.hasData && userSnap.data != null) {
                        final userData =
                            userSnap.data!.data() as Map<String, dynamic>?;
                        username = userData?['usuario'] ??
                            userData?['nombre'] ??
                            'Usuario';
                        role =
                            (userData?['rol'] ?? '').toString().toLowerCase();
                      } else if (userSnap.hasError) {
                        username = 'Error';
                      } else if (userSnap.connectionState ==
                          ConnectionState.waiting) {
                        username = 'Cargando...';
                      }
                      return _buildTicketCard(ticket, data, date,
                          '$username: $titleText', '', role);
                    },
                  );
                }
              }
              final bool isGuest = data['es_invitado'] ?? false;
              return _buildTicketCard(
                  ticket, data, date, titleText, subtitlePrefix, null, isGuest);
            },
          );
        },
      ),
      floatingActionButton: !widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showNewTicketDialog,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Nueva consulta',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }

  Widget _buildTicketCard(
      QueryDocumentSnapshot ticket,
      Map<String, dynamic> data,
      DateTime date,
      String title,
      String subtitlePrefix,
      [String? role,
      bool isGuest = false]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text('$subtitlePrefix${DateFormat('dd/MM HH:mm').format(date)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.isAdmin && role != null) ...[
              _buildRoleBadge(role),
              const SizedBox(height: 4),
            ],
            if (widget.isAdmin && isGuest) ...[
              _buildBadge(
                  'Invitado',
                  isDark
                      ? const Color(0xFFFED7AA)
                      : const Color(0xFF9A3412)), // Orange 200 vs Orange 800
              const SizedBox(height: 4),
            ],
            // Usamos un badge para el estado en lugar del punto
            _buildBadge(
                data['estado'], _getStatusColor(data['estado'], isDark)),
          ],
        ),
        onTap: () {
          if (data['es_invitado'] == true && widget.isAdmin) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                title: const Text('Detalles del Invitado'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(context, 'Nombre',
                          '${data['nombre_invitado']} ${data['apellidos_invitado']}'),
                      const SizedBox(height: 12),
                      _buildDetailRow(context, 'Email',
                          data['email_invitado'] ?? 'No proporcionado'),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        'MENSAJE:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data['descripcion'] ?? 'Sin descripción',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          height: 1.5,
                        ),
                      ),
                      if (data['url_imagen'] != null) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            data['url_imagen'],
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Los tickets de invitados no permiten chat directo. Contacta por email.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupportChatScreen(
                  ticketId: ticket.id, isAdmin: widget.isAdmin),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status) {
      case 'Abierto':
        return isDark
            ? const Color(0xFF86EFAC)
            : const Color(0xFF15803D); // Green 300 vs Green 700
      case 'Cerrado':
        return isDark
            ? const Color(0xFFFCA5A5)
            : const Color(0xFFB91C1C); // Red 300 vs Red 700
      default:
        return isDark
            ? const Color(0xFFCBD5E1)
            : const Color(0xFF475569); // Slate 300 vs Slate 600
    }
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Theme.of(context)
                .textTheme
                .bodySmall
                ?.color
                ?.withValues(alpha: 0.6),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(String role) {
    final String r = role.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color color;
    String text;

    if (r.contains('responsable')) {
      text = 'Responsable';
      // Blue 200 for dark mode is much more visible
      color = isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E3A8A);
    } else if (r.contains('admin')) {
      text = 'Admin';
      // Red 200 for dark mode
      color = isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B);
    } else {
      text = 'Ciudadano';
      // Teal 200 for dark mode
      color = isDark ? const Color(0xFF99F6E4) : const Color(0xFF0F766E);
    }

    return _buildBadge(text, color);
  }

  Widget _buildBadge(String text, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: isDark
            ? Border.all(color: color.withValues(alpha: 0.4), width: 0.5)
            : null,
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
