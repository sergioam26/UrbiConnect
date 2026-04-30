import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
import 'package:urbi_connect/services/support_service.dart';

class MessageCenterScreen extends StatefulWidget {
  const MessageCenterScreen({super.key});

  @override
  State<MessageCenterScreen> createState() => _MessageCenterScreenState();
}

class _MessageCenterScreenState extends State<MessageCenterScreen> {
  final SupportService _supportService = SupportService();

  @override
  void initState() {
    super.initState();
    _checkCleanup();
  }

  Future<void> _checkCleanup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final String role = userDoc.data()?['rol']?.toString().toLowerCase() ?? '';
    if (role == 'admin') {
      await _supportService.performAutoCleanup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, userDocSnap) {
        final userData = userDocSnap.data?.data() as Map<String, dynamic>?;
        final String role = (userData?['rol'] ?? '').toString().toLowerCase();
        final bool isAdmin = role == 'admin';
        final bool isResponsible =
            role == 'responsable' || role == 'responsable municipal';
        final List<String> categories =
            List<String>.from(userData?['id_categorias'] ?? []);

        return DefaultTabController(
          length: isAdmin ? 3 : 2,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              centerTitle: true,
              title: const Text(
                'Centro de mensajes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              bottom: TabBar(
                isScrollable: false,
                labelColor: const Color(0xFF0F172A),
                indicatorColor: const Color(0xFF0F172A),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.normal, fontSize: 13),
                tabs: isAdmin
                    ? [
                        const Tab(text: 'Tickets'),
                        const Tab(text: 'Directos'),
                        const Tab(text: 'Comunicados'),
                      ]
                    : [
                        const Tab(text: 'Chats'),
                        const Tab(text: 'Comunicados'),
                      ],
              ),
            ),
            body: isAdmin
                ? TabBarView(
                    children: [
                      _buildSupportList(context, 'admin_support'),
                      _buildSupportList(context, 'admin_direct'),
                      _buildBroadcastHistory(context, isAdmin, user.uid, role),
                    ],
                  )
                : TabBarView(
                    children: [
                      _buildUserDirectAndIncidentChatsList(
                          context, user.uid, isResponsible, categories),
                      _buildBroadcastHistory(context, isAdmin, user.uid, role),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSupportList(BuildContext context, String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: _supportService.getAdminTickets(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState('Error al conectar con la base de datos');
        }

        // Mientras carga, mostramos spinner
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data?.docs ?? [];

        // Filtramos en cliente para evitar fallos por falta de índices compuestos en Firestore
        final filteredTickets = allDocs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final bool isDirect = d['iniciado_por_admin'] ?? false;
          return type == 'admin_direct' ? isDirect : !isDirect;
        }).toList();

        if (filteredTickets.isEmpty) {
          return _buildEmptyState(type == 'admin_support'
              ? 'No hay tickets de soporte pendientes'
              : 'No has iniciado chats directos todavía');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredTickets.length,
          itemBuilder: (context, index) {
            final ticket = filteredTickets[index];
            return _buildSupportCard(context, ticket, true);
          },
        );
      },
    );
  }

  Widget _buildSupportCard(
      BuildContext context, DocumentSnapshot ticket, bool isAdmin) {
    final data = ticket.data() as Map<String, dynamic>;
    final String? userId = data['id_usuario'];
    final String status = data['estado'] ?? 'Cerrado';
    final String lastMessage = data['descripcion'] ?? 'Inicia conversación';
    final DateTime lastUpdate =
        (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();
    final bool isUnreadByAdmin = !(data['admin_leido'] ?? true);
    final bool isGuest = data['es_invitado'] ?? false;
    final bool isDirect = data['iniciado_por_admin'] ?? false;

    // Determinar etiqueta de estado para Admin
    String statusLabel = 'Pendiente';
    Color statusColor = Colors.orange;

    if (status == 'Abierto' || status == 'En proceso') {
      statusLabel = 'Activo';
      statusColor = Colors.green;
    } else if (status == 'Cerrado') {
      if (isDirect) {
        statusLabel = 'Finalizado';
        statusColor = Colors.grey;
      } else {
        // Si es un ticket de usuario y sigue cerrado, es que no hemos respondido
        statusLabel = 'Pendiente';
        statusColor = Colors.orange;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildUserAvatar(userId ?? '', isGuest, data),
        title: _buildSenderName(userId ?? '', isGuest, data, isAdmin),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(lastMessage,
                style: TextStyle(
                    fontSize: 13,
                    color: isUnreadByAdmin ? Colors.black : Colors.grey[600],
                    fontWeight:
                        isUnreadByAdmin ? FontWeight.bold : FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(DateFormat('dd/MM HH:mm').format(lastUpdate),
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isAdmin && !isGuest && userId != null) ...[
              _buildUserRoleBadge(userId),
              const SizedBox(height: 4),
            ],
            if (isGuest) ...[
              _buildBadge('Invitado', Colors.orange[800]!),
              const SizedBox(height: 4),
            ],
            _buildBadge(statusLabel, statusColor),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  SupportChatScreen(ticketId: ticket.id, isAdmin: isAdmin)),
        ),
      ),
    );
  }

  Widget _buildUserRoleBadge(String userId) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists)
          return const SizedBox();
        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final String role = (userData?['rol'] ?? '').toString().toLowerCase();

        Color color = Colors.blue;
        String text = 'Ciudadano';

        if (role.contains('responsable')) {
          color = Colors.purple;
          text = 'Responsable';
        } else if (role.contains('admin')) {
          color = Colors.red;
          text = 'Admin';
        }

        return _buildBadge(text, color);
      },
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSenderName(
      String userId, bool isGuest, Map<String, dynamic> data, bool isAdmin) {
    if (isGuest) {
      return Text('${data['nombre_invitado']} ${data['apellidos_invitado']}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15));
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnap) {
        String name = isAdmin ? 'Usuario' : 'Administración';
        if (userSnap.hasData == true) {
          final userData = userSnap.data!.data() as Map<String, dynamic>?;
          name = userData?['usuario'] ??
              userData?['nombre'] ??
              (isAdmin ? 'Usuario' : 'Administración');
        }
        return Text(name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15));
      },
    );
  }

  Widget _buildUserAvatar(
      String userId, bool isGuest, Map<String, dynamic> data) {
    if (isGuest)
      return CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey[100],
          child: const Icon(Icons.person_outline_rounded, color: Colors.grey));
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        final userData = snapshot.hasData
            ? snapshot.data!.data() as Map<String, dynamic>?
            : null;
        final photoUrl = userData?['foto_perfil'];
        return CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey[100],
          child: photoUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(photoUrl, fit: BoxFit.cover))
              : const Icon(Icons.person, color: Colors.grey),
        );
      },
    );
  }

  // Variable para filtrar comunicados en Admin
  final ValueNotifier<String> _broadcastFilter = ValueNotifier<String>('Todos');

  Widget _buildBroadcastHistory(
      BuildContext context, bool isAdmin, String currentUserId, String role) {
    return ValueListenableBuilder<String>(
      valueListenable: _broadcastFilter,
      builder: (context, activeFilter, child) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Notificaciones')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Error al cargar comunicados'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var allDocs = snapshot.data!.docs;
            List<Map<String, dynamic>> filteredDocs = [];

            if (isAdmin) {
              final Map<String, Map<String, dynamic>> uniqueMessages = {};
              for (var doc in allDocs) {
                final d = doc.data() as Map<String, dynamic>;
                if (d['tipo'] == 'broadcast' || d['tipo'] == 'oficial') {
                  final date = (d['fecha_creacion'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  final timeKey =
                      "${date.year}${date.month}${date.day}${date.hour}${date.minute}";
                  final key =
                      '${d['titulo']}_${d['mensaje']}_${d['tipo']}_$timeKey';

                  if (!uniqueMessages.containsKey(key)) {
                    uniqueMessages[key] = Map<String, dynamic>.from(d);
                    uniqueMessages[key]!['docId'] = doc.id;
                  }
                }
              }
              filteredDocs = uniqueMessages.values.toList();

              if (activeFilter != 'Todos') {
                filteredDocs = filteredDocs.where((d) {
                  final type = d['tipo'] ?? '';
                  final targets = (d['destinatarios'] as List?)
                          ?.map((e) => e.toString().toLowerCase())
                          .toList() ??
                      [];
                  final String normalizedFilter = activeFilter.toLowerCase();

                  if (normalizedFilter == 'ciudadanos') {
                    return targets.contains('ciudadano') ||
                        targets.contains('ciudadanos');
                  }
                  if (normalizedFilter == 'responsables') {
                    return targets.contains('responsable') ||
                        targets.contains('responsables') ||
                        targets.contains('responsable municipal');
                  }
                  if (normalizedFilter == 'individuales') {
                    return type == 'oficial' || type == 'individual';
                  }
                  return true;
                }).toList();
              }
            } else {
              // Ciudadano/Responsable: ver broadcast + individuales dirigidos a él
              filteredDocs = allDocs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final bool isDirect =
                    d['tipo'] == 'oficial' && d['id_usuario'] == currentUserId;
                if (isDirect) {
                  return true;
                }

                if (d['tipo'] == 'broadcast') {
                  final targets = (d['destinatarios'] as List?)
                          ?.map((e) => e.toString().toLowerCase())
                          .toList() ??
                      [];

                  if (role == 'ciudadano') {
                    return targets.contains('ciudadano') ||
                        targets.contains('ciudadanos');
                  } else if (role == 'responsable' ||
                      role == 'responsable municipal') {
                    return targets.contains('responsable') ||
                        targets.contains('responsables') ||
                        targets.contains('responsable municipal');
                  }
                  return false;
                }
                return false;
              }).map((doc) {
                final data = Map<String, dynamic>.from(
                    doc.data() as Map<String, dynamic>);
                data['docId'] = doc.id;
                return data;
              }).toList();
            }

            // Ordenar por fecha
            filteredDocs.sort((a, b) {
              final dateA = a['fecha_creacion'] as Timestamp?;
              final dateB = b['fecha_creacion'] as Timestamp?;
              if (dateA == null) return 1;
              if (dateB == null) return -1;
              return dateB.compareTo(dateA);
            });

            if (filteredDocs.isEmpty) {
              return Column(
                children: [
                  if (isAdmin) _buildBroadcastFilters(),
                  Expanded(
                      child: _buildEmptyState(
                          'No hay comunicados oficiales todavía')),
                ],
              );
            }

            return Column(
              children: [
                if (isAdmin) _buildBroadcastFilters(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final data = filteredDocs[index];
                      final DateTime date =
                          (data['fecha_creacion'] as Timestamp?)?.toDate() ??
                              DateTime.now();
                      final List<dynamic>? targets =
                          data['destinatarios'] as List<dynamic>?;
                      final String type = data['tipo'] ?? '';
                      final String? userId = data['id_usuario'];

                      String targetText = 'Administración';
                      if (isAdmin) {
                        if (type == 'broadcast' && targets != null) {
                          final formattedTargets = targets
                              .map((t) {
                                final r = t.toString().toLowerCase();
                                if (r == 'admin') {
                                  return 'admin';
                                }
                                if (r == 'ciudadano' || r == 'ciudadanos') {
                                  return 'ciudadanos';
                                }
                                if (r == 'responsable' ||
                                    r == 'responsables' ||
                                    r == 'responsable municipal') {
                                  return 'responsables municipales';
                                }
                                return r;
                              })
                              .toSet()
                              .join(", ");
                          targetText = 'Enviado a: $formattedTargets';
                        } else if (type == 'oficial') {
                          targetText = 'individual';
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7FF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.indigo.withValues(alpha: 0.15),
                              width: 1),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.indigo.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.campaign_rounded,
                                color: Color(0xFF6366F1), size: 24),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(data['titulo'] ?? 'Sin título',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ),
                              _buildBadge('OFICIAL', Colors.indigo),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              if (data['url_imagen'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: GestureDetector(
                                    onTap: () => _showFullImage(
                                        context, data['url_imagen']),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Hero(
                                        tag: data['url_imagen'],
                                        child: Image.network(
                                          data['url_imagen'],
                                          height: 120,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Text(data['mensaje'] ?? '',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[800]),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      DateFormat('dd/MM/yyyy, HH:mm')
                                          .format(date),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  if (isAdmin &&
                                      type == 'oficial' &&
                                      userId != null)
                                    FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(userId)
                                          .get(),
                                      builder: (context, userSnap) {
                                        String userName = 'Cargando...';
                                        if (userSnap.hasData &&
                                            userSnap.data!.exists) {
                                          final userData = userSnap.data!.data()
                                              as Map<String, dynamic>;
                                          userName =
                                              '${userData['nombre']} ${userData['apellidos']}';
                                        }
                                        return Text('Para: $userName',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF6366F1),
                                                fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis);
                                      },
                                    )
                                  else
                                    Text(targetText,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF6366F1),
                                            fontWeight: FontWeight.bold),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBroadcastFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: ['Todos', 'Ciudadanos', 'Responsables', 'Individuales']
              .map((filter) {
            final isSelected = _broadcastFilter.value == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter,
                    style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.indigo)),
                selected: isSelected,
                selectedColor: Colors.indigo,
                checkmarkColor: Colors.white,
                onSelected: (selected) {
                  if (selected) _broadcastFilter.value = filter;
                },
              ),
            );
          }).toList(),
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
            child: Hero(
              tag: imageUrl,
              child: InteractiveViewer(
                child: Image.network(imageUrl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserDirectAndIncidentChatsList(BuildContext context,
      String currentUserId, bool isResponsible, List<String> categories) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _supportService.getUserTickets(currentUserId),
            builder: (context, supportSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: isResponsible
                    ? (categories.isEmpty
                        ? const Stream.empty()
                        : FirebaseFirestore.instance
                            .collection('Incidencia')
                            .where('id_categoria', whereIn: categories)
                            .snapshots())
                    : FirebaseFirestore.instance
                        .collection('Incidencia')
                        .where('id_usuario', isEqualTo: currentUserId)
                        .snapshots(),
                builder: (context, incidentSnapshot) {
                  if (supportSnapshot.hasError || incidentSnapshot.hasError) {
                    return const Center(child: Text('Error al cargar chats'));
                  }

                  // Solo mostramos spinner si AMBOS están cargando.
                  // Si uno tiene datos, permitimos que se vea algo.
                  if (supportSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      incidentSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Procesar tickets de soporte (incluye directos del admin)
                  final List<Map<String, dynamic>> allChats = [];
                  if (supportSnapshot.hasData) {
                    allChats.addAll(supportSnapshot.data!.docs
                        .map((doc) => {'type': 'support', 'doc': doc}));
                  }

                  // Procesar incidencias
                  if (incidentSnapshot.hasData) {
                    final incidents = incidentSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['es_eliminada'] != true;
                    }).map((doc) => {'type': 'incident', 'doc': doc});
                    allChats.addAll(incidents);
                  }

                  if (allChats.isEmpty) {
                    // Si aún está cargando uno de los streams, esperamos antes de mostrar vacío
                    if (supportSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        incidentSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildEmptyState('No tienes chats activos todavía');
                  }

                  // Ordenar por fecha de última actividad (si existe el campo)
                  allChats.sort((a, b) {
                    final dataA = (a['doc'] as DocumentSnapshot).data()
                        as Map<String, dynamic>;
                    final dataB = (b['doc'] as DocumentSnapshot).data()
                        as Map<String, dynamic>;
                    final dateA = (dataA['fecha'] as Timestamp?) ??
                        (dataA['fecha_creacion'] as Timestamp?) ??
                        Timestamp.now();
                    final dateB = (dataB['fecha'] as Timestamp?) ??
                        (dataB['fecha_creacion'] as Timestamp?) ??
                        Timestamp.now();
                    return dateB.compareTo(dateA);
                  });

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: allChats.length,
                    itemBuilder: (context, index) {
                      final chat = allChats[index];
                      final doc = chat['doc'] as DocumentSnapshot;
                      final data = doc.data() as Map<String, dynamic>;
                      final type = chat['type'];

                      if (type == 'support') {
                        final bool isUnread =
                            !(data['not_admin_leido'] ?? true);
                        return _buildSupportChatTile(context, doc, isUnread);
                      } else {
                        return _buildIncidentChatTile(context, doc);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSupportChatTile(
      BuildContext context, DocumentSnapshot doc, bool isUnread) {
    final data = doc.data() as Map<String, dynamic>;
    final String title = data['iniciado_por_admin'] == true
        ? 'Mensaje de Administración'
        : 'Ticket de soporte';
    final String lastMessage = data['descripcion'] ?? 'Sin mensajes';
    final DateTime date =
        (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnread ? const Color(0xFFF0F7FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isUnread
            ? Border.all(color: Colors.indigo.withValues(alpha: 0.1))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: Colors.indigo[50],
              borderRadius: BorderRadius.circular(12)),
          child:
              const Icon(Icons.shield_outlined, color: Colors.indigo, size: 24),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: isUnread ? Colors.black87 : Colors.grey[600])),
            const SizedBox(height: 4),
            Text(DateFormat('dd/MM HH:mm').format(date),
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  SupportChatScreen(ticketId: doc.id, isAdmin: false)),
        ),
      ),
    );
  }

  Widget _buildIncidentChatTile(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String title = data['titulo'] ?? 'Sin título';
    final String status = data['estado'] ?? 'Reportada';
    final String? imageUrl = data['foto_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl), fit: BoxFit.cover)
                : null,
          ),
          child: imageUrl == null
              ? Icon(Icons.report_problem_outlined,
                  color: Colors.amber[800], size: 24)
              : null,
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text('ID #${doc.id.substring(0, 5).toUpperCase()} • $status',
            style: const TextStyle(fontSize: 12)),
        trailing:
            const Icon(Icons.chat_bubble_rounded, color: Color(0xFF0F172A)),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ChatScreen(incidentId: doc.id))),
      ),
    );
  }

  Widget _buildIncidentChatsList(BuildContext context, String currentUserId,
      bool isResponsible, List<String> categories) {
    // This is now replaced by _buildUserDirectAndIncidentChatsList but kept for potential legacy reference if needed
    // However, I've updated the build method to use the new one.
    return const SizedBox();
  }

  String _formatRole(String role) {
    final r = role.toLowerCase();
    if (r == 'admin') return 'Admin';
    if (r == 'ciudadano') return 'Ciudadano';
    if (r == 'responsable' || r == 'responsable municipal')
      return 'Responsable municipal';
    return r;
  }
}
