import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/config/app_config.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/notification_service.dart';

import 'admin/analytics_screen.dart';
import 'admin/category_management_screen.dart';
import 'admin/user_management_screen.dart';
import 'incidents/incident_form_screen.dart';
import 'incidents/incident_list_screen.dart';
import 'messages/message_center_screen.dart';
import 'notifications/notification_list_screen.dart';
import 'profile/profile_screen.dart';
import 'support/support_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late Stream<UserProfile?> _userProfileStream;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _syncEmail();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userProfileStream = DatabaseService().getUserProfile(user.uid);
    } else {
      _userProfileStream = Stream.value(null);
    }
  }

  Future<void> _syncEmail() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.syncEmailWithFirestore();
  }

  Future<void> _initNotifications() async {
    final notificationService = NotificationService();
    await notificationService.initNotifications();
    await notificationService.updateTokenInFirestore();
    if (mounted) {
      notificationService.setupInteractedMessages(context);
    }
  }

  List<Widget> _getPages(
      UserProfile profile, bool isAdmin, bool isResponsible) {
    if (isAdmin) {
      return [
        const AdminDashboard(),
        MessageCenterScreen(profile: profile),
        NotificationListScreen(profile: profile),
        ProfileScreen(profile: profile),
      ];
    }
    return [
      IncidentListScreen(profile: profile),
      MessageCenterScreen(profile: profile),
      NotificationListScreen(profile: profile),
      ProfileScreen(profile: profile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ValueListenableBuilder<String>(
      valueListenable: SuperuserSession.roleNotifier,
      builder: (context, simulatedRole, child) {
        return StreamBuilder<UserProfile?>(
          stream: _userProfileStream,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting &&
                !profileSnapshot.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final profile = profileSnapshot.data;
            if (profile == null) {
              return const Scaffold(
                  body: Center(child: Text('Cargando perfil...')));
            }

            final String userEmail =
                (user.email ?? profile.email).toLowerCase();
            final String role =
                (userEmail == AppConfig.superUserEmail.toLowerCase())
                    ? simulatedRole.toLowerCase()
                    : profile.role.toLowerCase();
            final isAdmin = role == 'admin';
            final isResponsible =
                role == 'responsable' || role == 'responsable municipal';

            final virtualProfile = UserProfile(
              uid: profile.uid,
              name: profile.name,
              surnames: profile.surnames,
              email: profile.email,
              username: profile.username,
              role: role,
              profilePhoto: profile.profilePhoto,
              categories: profile.categories,
              pushToken: profile.pushToken,
            );

            final pages = _getPages(virtualProfile, isAdmin, isResponsible);

            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                centerTitle: true,
                title: Text(
                  'UrbiConnect',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.5,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                actions: [
                  if (user.email?.toLowerCase() ==
                          AppConfig.superUserEmail.toLowerCase() ||
                      profile?.email.toLowerCase() ==
                          AppConfig.superUserEmail.toLowerCase())
                    IconButton(
                      icon: const Icon(Icons.supervised_user_circle_rounded,
                          color: Colors.amber, size: 24),
                      tooltip: 'Cambiar rol de súper usuario',
                      onPressed: () =>
                          _showSuperuserRoleSwitcher(context, user.uid, role),
                    ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          title: const Text('Cerrar sesión'),
                          content: const Text(
                              '¿Estás seguro de que deseas salir de UrbiConnect?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Provider.of<AuthService>(context, listen: false)
                                    .signOut();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[600],
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Salir'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: pages[_selectedIndex],
              floatingActionButton: (_selectedIndex == 0 &&
                      !isResponsible &&
                      !isAdmin)
                  ? FloatingActionButton.extended(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const IncidentFormScreen()),
                        );
                      },
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Reportar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  : null,
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                      top: BorderSide(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.1),
                          width: 0.5)),
                ),
                child: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  destinations: [
                    NavigationDestination(
                      icon: Icon(isAdmin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.home_outlined),
                      selectedIcon: Icon(
                          isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.home_rounded,
                          color: Theme.of(context).colorScheme.primary),
                      label: isAdmin ? 'Gestión' : 'Inicio',
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: Icon(Icons.chat_bubble_rounded,
                          color: Theme.of(context).colorScheme.primary),
                      label: 'Mensajes',
                    ),
                    NavigationDestination(
                      icon: StreamBuilder<int>(
                        stream: NotificationService().getUnreadCount(user.uid),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          if (count > 0) {
                            return Badge.count(
                              count: count,
                              child:
                                  const Icon(Icons.notifications_none_rounded),
                            );
                          }
                          return const Icon(Icons.notifications_none_rounded);
                        },
                      ),
                      selectedIcon: StreamBuilder<int>(
                        stream: NotificationService().getUnreadCount(user.uid),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          if (count > 0) {
                            return Badge.count(
                              count: count,
                              child: Icon(Icons.notifications_rounded,
                                  color: Theme.of(context).colorScheme.primary),
                            );
                          }
                          return Icon(Icons.notifications_rounded,
                              color: Theme.of(context).colorScheme.primary);
                        },
                      ),
                      label: 'Buzón',
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded,
                          color: Theme.of(context).colorScheme.primary),
                      label: 'Perfil',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSuperuserRoleSwitcher(
      BuildContext context, String uid, String currentRole) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.amber, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rol de súper usuario',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Como súper usuario, puedes simular cualquiera de los roles del sistema. Las vistas, accesos y permisos se actualizarán de forma instantánea.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
              _buildRoleOption(
                context,
                uid: uid,
                roleValue: 'admin',
                label: 'Administrador municipal',
                icon: Icons.admin_panel_settings_rounded,
                color: Colors.blueGrey,
                isSelected: currentRole == 'admin',
              ),
              const SizedBox(height: 12),
              _buildRoleOption(
                context,
                uid: uid,
                roleValue: 'responsable',
                label: 'Responsable de servicio',
                icon: Icons.engineering_rounded,
                color: Colors.teal,
                isSelected: currentRole == 'responsable' ||
                    currentRole == 'responsable municipal',
              ),
              const SizedBox(height: 12),
              _buildRoleOption(
                context,
                uid: uid,
                roleValue: 'ciudadano',
                label: 'Ciudadano general',
                icon: Icons.person_rounded,
                color: Theme.of(context).colorScheme.primary,
                isSelected: currentRole == 'ciudadano',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleOption(
    BuildContext context, {
    required String uid,
    required String roleValue,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          final isSuperuser = currentUser?.email?.toLowerCase() ==
              AppConfig.superUserEmail.toLowerCase();
          if (isSuperuser) {
            SuperuserSession.simulatedRole = roleValue;
          } else {
            final updates = <String, dynamic>{'rol': roleValue};
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update(updates);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Rol simulado cambiado a ${label.toLowerCase()} con éxito.'),
                    ),
                  ],
                ),
                backgroundColor: color,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al cambiar rol: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                  color: isSelected
                      ? color
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 20)
            else
              const Icon(Icons.circle_outlined, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Panel de administración',
            style: GoogleFonts.montserrat(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.displayLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Control administrativo y analítico municipal',
            style: GoogleFonts.inter(
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          _buildAdminCard(
            context,
            title: 'Usuarios',
            subtitle: 'Directorio y control de accesos',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF0F172A), // Slate 900
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const UserManagementScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context,
            title: 'Categorías',
            subtitle: 'Configuración de tipos de incidencia',
            icon: Icons.category_rounded,
            color: const Color(0xFF334155), // Slate 700
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CategoryManagementScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context,
            title: 'Estadísticas',
            subtitle: 'Visualización de datos y reportes',
            icon: Icons.analytics_rounded,
            color: const Color(0xFF0F766E), // Deep Teal
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context,
            title: 'Soporte técnico',
            subtitle: 'Atención al ciudadano UrbiConnect',
            icon: Icons.support_agent_rounded,
            color: const Color(0xFFB45309), // Muted Bronze/Amber
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const SupportScreen(isAdmin: true)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildAdminCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Theme.of(context).dividerColor, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
