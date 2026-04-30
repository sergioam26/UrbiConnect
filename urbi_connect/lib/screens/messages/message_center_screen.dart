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
          length: 3,
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
                        const Tab(text: 'Soporte'),
                        const Tab(text: 'Chats'),
                        const Tab(text: 'Comunicados'),
                      ],
              ),
            ),
            body: isAdmin
                ? TabBarView(
                    children: [
                      _buildSupportList(context, user.uid, true,
                          filterAdminInitiated: false),
                      _buildSupportList(context, user.uid, true,
                          filterAdminInitiated: true),
                      _buildBroadcastHistory(context, isAdmin, user.uid, role),
                    ],
                  )
                : TabBarView(
                    children: [
                      _buildSupportList(context, user.uid, false),
                      _buildIncidentChatsList(
                          context, user.uid, isResponsible, categories),
                      _buildBroadcastHistory(context, isAdmin, user.uid, role),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSupportList(
      BuildContext context, String currentUserId, bool isAdmin,
      {bool? filterAdminInitiated}) {
    Query query = FirebaseFirestore.instance.collection('Soporte');

    // Si no es admin, solo sus propios mensajes
    if (!isAdmin) {
      query = query.where('id_usuario', isEqualTo: currentUserId);
    }
    // Para Admin, si filtramos por iniciados por admin, usamos el query directamente
    else if (filterAdminInitiated == true) {
      query = query.where('iniciado_por_admin', isEqualTo: true);
    }
    // Si es Admin y queremos los tickets de ciudadanos (iniciado_por_admin != true)
    // No usamos isNull porque falla en Firestore para docs sin el campo.
    // Simplemente traemos la colección y filtramos en memoria.

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('Error al cargar mensajes'));
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs;

        // Filtro en memoria para Admin cuando queremos ver solo tickets de ciudadanos
        if (isAdmin && filterAdminInitiated == false) {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['iniciado_por_admin'] != true;
          }).toList();
        }

        if (docs.isEmpty) {
          String emptyMsg = 'No hay chats activos';
          if (isAdmin) {
            emptyMsg = filterAdminInitiated == true
                ? 'No has iniciado chats directos'
                : 'No hay tickets de soporte pendientes';
          }
          return _buildEmptyState(emptyMsg);
        }

        final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
        sortedDocs.sort((a, b) {
          final statusA = a.get('estado') as String;
          final statusB = b.get('estado') as String;
          if (statusA == 'Abierto' && statusB != 'Abierto') return -1;
          if (statusA != 'Abierto' && statusB == 'Abierto') return 1;
          final dateA =
              (a.get('fecha') as Timestamp?)?.toDate() ?? DateTime(2000);
          final dateB =
              (b.get('fecha') as Timestamp?)?.toDate() ?? DateTime(2000);
          return dateB.compareTo(dateA);
        });

        return Column(
          children: [
            if (isAdmin &&
                docs.any((d) =>
                    (d.data() as Map<String, dynamic>)['admin_leido'] == false))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final batch = FirebaseFirestore.instance.batch();
                      for (var doc in docs) {
                        if ((doc.data()
                                as Map<String, dynamic>)['admin_leido'] ==
                            false) {
                          batch.update(doc.reference, {'admin_leido': true});
                        }
                      }
                      await batch.commit();
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Marcar todos como leídos',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedDocs.length,
                itemBuilder: (context, index) {
                  final doc = sortedDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildSupportCard(context, doc.id, data, isAdmin);
                },
              ),
            ),
          ],
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
                                if (r == 'admin') return 'Admin';
                                if (r == 'ciudadano' || r == 'ciudadanos')
                                  return 'Ciudadanos';
                                if (r == 'responsable' ||
                                    r == 'responsables' ||
                                    r == 'responsable municipal')
                                  return 'Responsables Municipales';
                                return r[0].toUpperCase() + r.substring(1);
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
                                          fontSize: 15))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.indigo,
                                    borderRadius: BorderRadius.circular(6)),
                                child: const Text('OFICIAL',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      DateFormat('dd/MM/yyyy, HH:mm')
                                          .format(date),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500)),
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
                                                fontWeight: FontWeight.bold));
                                      },
                                    )
                                  else
                                    Text(targetText,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF6366F1),
                                            fontWeight: FontWeight.bold)),
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

  Widget _buildIncidentChatsList(BuildContext context, String currentUserId,
      bool isResponsible, List<String> categories) {
    Stream<QuerySnapshot> stream;
    if (isResponsible) {
      if (categories.isEmpty)
        return _buildEmptyState(
            'No tienes categorías asignadas para gestionar');
      stream = FirebaseFirestore.instance
          .collection('Incidencia')
          .where('id_categoria', whereIn: categories)
          .snapshots();
    } else {
      stream = FirebaseFirestore.instance
          .collection('Incidencia')
          .where('id_usuario', isEqualTo: currentUserId)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
              child: Text('Error al cargar chats de incidencias'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        var incidents = snapshot.data!.docs;

        // Ocultamos las eliminadas (soft delete) para todos en la vista de chats
        incidents = incidents.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['es_eliminada'] != true;
        }).toList();

        if (incidents.isEmpty) {
          return _buildEmptyState('No tienes chats activos en tus incidencias');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: incidents.length,
          itemBuilder: (context, index) {
            final incidentDoc = incidents[index];
            final data = incidentDoc.data() as Map<String, dynamic>;
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text(
                    'ID #${incidentDoc.id.substring(0, 5).toUpperCase()} • $status',
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chat_bubble_rounded,
                    color: Color(0xFF0F172A)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          ChatScreen(incidentId: incidentDoc.id)),
                ),
              ),
            );
          },
        );
      },
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

  Widget _buildSupportCard(BuildContext context, String docId,
      Map<String, dynamic> data, bool isAdmin) {
    final String status = data['estado'] ?? 'Abierto';
    final bool isGuest = data['es_invitado'] == true;
    final String userId = data['id_usuario'] ?? '';
    final DateTime date =
        (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();
    final bool isUnread = isAdmin
        ? (data['admin_leido'] == false)
        : (data['not_admin_leido'] == false);

    Color statusColor;
    switch (status) {
      case 'Abierto':
        statusColor = Colors.red;
        break;
      case 'En proceso':
        statusColor = Colors.orange;
        break;
      case 'Cerrado':
        statusColor = Colors.green;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnread ? const Color(0xFFF0F7FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
        border: isUnread
            ? Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    SupportChatScreen(ticketId: docId, isAdmin: isAdmin)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    _buildUserAvatar(userId, isGuest, data),
                    if (isUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSenderName(userId, isGuest, data, isAdmin),
                          Text(DateFormat('dd MMM, HH:mm').format(date),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isUnread
                                      ? Colors.blue[700]
                                      : Colors.grey[500],
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(data['descripcion'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isUnread ? Colors.black87 : Colors.grey[600],
                            fontWeight:
                                isUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(status,
                                style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (data['iniciado_por_admin'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.indigo[50],
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('Oficial',
                                  style: TextStyle(
                                      color: Colors.indigo[700],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: isUnread ? Colors.blue : Colors.grey),
              ],
            ),
          ),
        ),
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
}
