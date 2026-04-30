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
  String _statusFilter = 'Todos';
  String? _categoryFilter;
  DateTimeRange? _dateRangeFilter;
  bool _isAscending = false; // Default descending (newest first)

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

  List<Incident> _filterAndSortIncidents(List<Incident> incidents) {
    List<Incident> filtered = incidents;

    // Status filter
    if (_statusFilter != 'Todos') {
      filtered = filtered
          .where(
              (inc) => inc.status.toLowerCase() == _statusFilter.toLowerCase())
          .toList();
    }

    // Category filter
    if (_categoryFilter != null && _categoryFilter != 'Todas') {
      filtered =
          filtered.where((inc) => inc.categoryId == _categoryFilter).toList();
    }

    // Date range filter
    if (_dateRangeFilter != null) {
      filtered = filtered.where((inc) {
        return inc.createdAt.isAfter(
                _dateRangeFilter!.start.subtract(const Duration(seconds: 1))) &&
            inc.createdAt
                .isBefore(_dateRangeFilter!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Sorting
    filtered.sort((a, b) {
      if (_isAscending) {
        return a.createdAt.compareTo(b.createdAt);
      } else {
        return b.createdAt.compareTo(a.createdAt);
      }
    });

    return filtered;
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
            if (isResponsible) ...[
              const SizedBox(height: 8),
              _buildStatusFilters(),
            ] else
              _buildUnifiedFilterButton(),
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
                  final incidents = _filterAndSortIncidents(allIncidents);

                  if (allIncidents.isEmpty) {
                    return _buildEmptyState();
                  }

                  if (incidents.isEmpty &&
                      (_statusFilter != 'Todos' ||
                          _categoryFilter != null ||
                          _dateRangeFilter != null)) {
                    return const Center(
                        child: Text(
                            'No hay coincidencias con los filtros aplicados'));
                  }

                  if (isResponsible) {
                    final grouped = _groupIncidents(incidents);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
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

  Widget _buildUnifiedFilterButton() {
    final bool hasFilters = _statusFilter != 'Todos' ||
        _categoryFilter != null ||
        _dateRangeFilter != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: InkWell(
        onTap: () => _showCitizenFilters(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: hasFilters
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasFilters
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 20,
                color: hasFilters ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 12),
              Text(
                hasFilters
                    ? 'Filtros activos'
                    : 'Filtrar y ordenar incidencias',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: hasFilters ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (hasFilters)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.check,
                      size: 12, color: Theme.of(context).colorScheme.primary),
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCitizenFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filtrar y ordenar',
                            style: GoogleFonts.montserrat(
                                fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _statusFilter = 'Todos';
                                _categoryFilter = null;
                                _dateRangeFilter = null;
                                _isAscending = false;
                              });
                              setState(() {});
                            },
                            child: const Text('Limpiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ORDEN
                      _buildFilterTitle('Ordenar por fecha'),
                      Row(
                        children: [
                          _buildChoiceChip(
                            'Más recientes',
                            !_isAscending,
                            (val) {
                              setModalState(() => _isAscending = false);
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildChoiceChip(
                            'Más antiguas',
                            _isAscending,
                            (val) {
                              setModalState(() => _isAscending = true);
                              setState(() {});
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ESTADO
                      _buildFilterTitle('Estado de la incidencia'),
                      Wrap(
                        spacing: 8,
                        children: [
                          'Todos',
                          'Pendiente',
                          'En proceso',
                          'Resuelta'
                        ].map((s) {
                          return _buildChoiceChip(
                            s,
                            _statusFilter == s,
                            (val) {
                              setModalState(() => _statusFilter = s);
                              setState(() {});
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // CATEGORÍA
                      _buildFilterTitle('Categoría'),
                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('Categoria')
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          final categories = snapshot.data!.docs;
                          return Wrap(
                            spacing: 8,
                            children: [
                              _buildChoiceChip(
                                'Todas',
                                _categoryFilter == null,
                                (val) {
                                  setModalState(() => _categoryFilter = null);
                                  setState(() {});
                                },
                              ),
                              ...categories.map((doc) {
                                final name = doc.get('nombre');
                                return _buildChoiceChip(
                                  name,
                                  _categoryFilter == doc.id,
                                  (val) {
                                    setModalState(() =>
                                        _categoryFilter = val ? doc.id : null);
                                    setState(() {});
                                  },
                                );
                              }),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // FECHA
                      _buildFilterTitle('Fecha de creación'),
                      _buildNewDateFilter(setModalState),

                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            'Aplicar y ver resultados',
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildNewDateFilter(StateSetter setModalState) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDateInput(
                label: 'Desde',
                date: _dateRangeFilter?.start,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    locale: const Locale('es', 'ES'),
                    cancelText: 'CANCELAR',
                    confirmText: 'ACEPTAR',
                    initialDate: _dateRangeFilter?.start ?? DateTime.now(),
                    firstDate: DateTime(2023),
                    lastDate: _dateRangeFilter?.end ?? DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() {
                      _dateRangeFilter = DateTimeRange(
                        start: picked,
                        end: _dateRangeFilter?.end ?? picked,
                      );
                    });
                    setState(() {});
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateInput(
                label: 'Hasta',
                date: _dateRangeFilter?.end,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    locale: const Locale('es', 'ES'),
                    cancelText: 'CANCELAR',
                    confirmText: 'ACEPTAR',
                    initialDate: _dateRangeFilter?.end ?? DateTime.now(),
                    firstDate: _dateRangeFilter?.start ?? DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() {
                      _dateRangeFilter = DateTimeRange(
                        start: _dateRangeFilter?.start ?? picked,
                        end: picked,
                      );
                    });
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
        if (_dateRangeFilter != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () {
                setModalState(() => _dateRangeFilter = null);
                setState(() {});
              },
              icon: const Icon(Icons.backspace_outlined, size: 14),
              label:
                  const Text('Limpiar fechas', style: TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _buildDateInput(
      {required String label, DateTime? date, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  date == null
                      ? 'Cualquiera'
                      : DateFormat('dd/MM/yy').format(date),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF94A3B8),
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildChoiceChip(
      String label, bool selected, Function(bool) onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: GoogleFonts.inter(
        color: selected ? Colors.white : const Color(0xFF475569),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
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
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              catName,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            subtitle: Text('${incidents.length} incidencias',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.layers_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            children: incidents
                .map((inc) => _buildIncidentCard(inc, profile))
                .toList(),
          ),
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
                        incident.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        incident.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: const Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            incident.updatedAt != null
                                ? Icons.edit_calendar_rounded
                                : Icons.calendar_today_rounded,
                            size: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            incident.updatedAt != null
                                ? 'Ed: ${DateFormat('dd/MM/yy').format(incident.updatedAt!)}'
                                : DateFormat('dd MMM, yyyy')
                                    .format(incident.createdAt),
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500),
                          ),
                          if (incident.updatedAt != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.history_rounded,
                                size: 12, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 2),
                            Text(
                              'Cre: ${DateFormat('dd/MM/yy').format(incident.createdAt)}',
                              style: GoogleFonts.inter(
                                  fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
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
