import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/incidents/incident_detail_screen.dart';
import 'package:urbi_connect/screens/incidents/responsible_incident_detail_screen.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentListScreen extends StatefulWidget {
  const IncidentListScreen({super.key});

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  String _searchQuery = '';
  String _statusFilter = 'Todos';
  final TextEditingController _searchController = TextEditingController();
  late Stream<UserProfile?> _userProfileStream;
  UserProfile? _lastProfile;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userProfileStream = DatabaseService().getUserProfile(user.uid);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Incident> _filterIncidents(List<Incident> incidents) {
    List<Incident> filtered = incidents;

    // Status filter
    if (_statusFilter != 'Todos') {
      filtered = filtered
          .where(
              (inc) => inc.status.toLowerCase() == _statusFilter.toLowerCase())
          .toList();
    }

    // Search query filter
    if (_searchQuery.isEmpty) {
      return filtered;
    }

    final query = _searchQuery.toLowerCase();
    return filtered.where((inc) {
      final desc = inc.description.toLowerCase();
      final date = DateFormat('dd/MM/yyyy').format(inc.createdAt);
      return desc.contains(query) || date.contains(query);
    }).toList();
  }

  Map<String, List<Incident>> _groupIncidents(List<Incident> incidents) {
    Map<String, List<Incident>> groups = {};
    for (var inc in incidents) {
      groups.putIfAbsent(inc.categoryId, () => []).add(inc);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Usuario no autenticado'));
    }

    return StreamBuilder<UserProfile?>(
      stream: _userProfileStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) {
          return const Center(child: Text('Error al cargar perfil'));
        }
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            _lastProfile == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userSnapshot.hasData) {
          _lastProfile = userSnapshot.data;
        }

        final profile = _lastProfile;
        if (profile == null) {
          return const Center(child: Text('Perfil no encontrado'));
        }

        final bool isResponsible = profile.role == 'Responsable' ||
            profile.role == 'Responsable Municipal';

        return Column(
          children: [
            _buildSearchBar(),
            _buildStatusFilters(),
            Expanded(
              child: StreamBuilder<List<Incident>>(
                stream: dbService.getIncidents(profile),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error al cargar datos'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allIncidents = snapshot.data ?? [];
                  final incidents = _filterIncidents(allIncidents);

                  if (allIncidents.isEmpty) {
                    return _buildEmptyState();
                  }

                  if (incidents.isEmpty &&
                      (_searchQuery.isNotEmpty || _statusFilter != 'Todos')) {
                    return const Center(
                        child: Text(
                            'No hay coincidencias con los filtros aplicados'));
                  }

                  if (isResponsible) {
                    final grouped = _groupIncidents(incidents);
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: grouped.keys.map((catId) {
                        return _buildCategoryGroup(
                            catId, grouped[catId]!, profile);
                      }).toList(),
                    );
                  }

                  return ListView.builder(
                    itemCount: incidents.length,
                    padding: const EdgeInsets.only(bottom: 80),
                    itemBuilder: (context, index) {
                      return _buildIncidentCard(incidents[index], profile);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          key: const ValueKey('incident_search_field'),
          controller: _searchController,
          onChanged: (v) {
            if (_searchQuery != v) {
              setState(() => _searchQuery = v);
            }
          },
          decoration: InputDecoration(
            hintText: 'Buscar incidencias...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    final filters = ['Todos', 'Pendiente', 'En proceso', 'Resuelta'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8, top: 4),
          child: Text(
            'Filtrar por estado',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
              letterSpacing: 1.2,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: filters.map((status) {
              final isSelected = _statusFilter == status;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  label: Text(status),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _statusFilter = status);
                    }
                  },
                  showCheckmark: false,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                  ),
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryGroup(
      String catId, List<Incident> incidents, UserProfile profile) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('Categoria').doc(catId).get(),
      builder: (context, snapshot) {
        String catName = catId;
        if (snapshot.hasData && snapshot.data!.exists) {
          catName = snapshot.data!.get('nombre');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    catName.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            ...incidents.map((inc) => _buildIncidentCard(inc, profile)),
          ],
        );
      },
    );
  }

  Widget _buildIncidentCard(Incident incident, UserProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
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
                    builder: (context) =>
                        IncidentDetailScreen(incident: incident)),
              );
            }
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Hero(
                  tag: 'incident_image_${incident.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: incident.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: incident.imageUrl!,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFF8FAFC)),
                            errorWidget: (context, url, error) => Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFF8FAFC),
                                child: const Icon(Icons.error_outline_rounded)),
                          )
                        : Container(
                            width: 72,
                            height: 72,
                            color: const Color(0xFFF8FAFC),
                            child: Icon(Icons.image_not_supported_rounded,
                                color: const Color(0xFFCBD5E1)),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusChip(incident.status),
                      const SizedBox(height: 8),
                      Text(
                        incident.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF1E293B),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd MMM, yyyy')
                                .format(incident.createdAt),
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFCBD5E1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.assignment_rounded,
                size: 48, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 24),
          Text(
            'No hay incidencias',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Sé el primero en reportar un problema en Cantillana.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    switch (status.toLowerCase()) {
      case 'pendiente':
        color = const Color(0xFFF59E0B); // Amber
        icon = Icons.timer_outlined;
        break;
      case 'en proceso':
        color = const Color(0xFF3B82F6); // Blue
        icon = Icons.sync_rounded;
        break;
      case 'resuelta':
        color = const Color(0xFF10B981); // Emerald
        icon = Icons.check_circle_rounded;
        break;
      default:
        color = const Color(0xFF94A3B8);
        icon = Icons.help_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: GoogleFonts.inter(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
