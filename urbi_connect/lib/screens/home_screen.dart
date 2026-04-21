import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/notification_service.dart';

import 'admin/analytics_screen.dart';
import 'admin/category_management_screen.dart';
import 'admin/user_management_screen.dart';
import 'incidents/incident_form_screen.dart';
import 'incidents/incident_list_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final notificationService = NotificationService();
    await notificationService.initNotifications();
    await notificationService.updateTokenInFirestore();
  }

  List<Widget> _getPages(bool isAdmin) {
    if (isAdmin) {
      return [
        const AdminDashboard(),
        const NotificationListScreen(),
        const ProfileScreen(),
      ];
    }
    return [
      const IncidentListScreen(),
      const NotificationListScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<UserProfile?>(
      stream: DatabaseService().getUserProfile(user.uid),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        final isAdmin = profile?.role == 'Admin';
        final isResponsible = profile?.role == 'Responsable' ||
            profile?.role == 'Responsable Municipal';

        final pages = _getPages(isAdmin);

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false, // Quitar botón de atrás si existe
            title: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                'UrbiConnect',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.5,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
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
              )
            ],
          ),
          body: pages[_selectedIndex],
          floatingActionButton:
              (_selectedIndex == 0 && !isResponsible && !isAdmin)
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
              color: Colors.white,
              border: const Border(
                  top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              backgroundColor: Colors.white,
              indicatorColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              destinations: [
                NavigationDestination(
                  icon: Icon(isAdmin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.home_outlined),
                  selectedIcon: Icon(
                      isAdmin ? Icons.admin_panel_settings : Icons.home_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  label: isAdmin ? 'Gestión' : 'Inicio',
                ),
                NavigationDestination(
                  icon: StreamBuilder<int>(
                    stream: NotificationService().getUnreadCount(user.uid),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count > 0) {
                        return Badge.count(
                          count: count,
                          child: const Icon(Icons.notifications_none_rounded),
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
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Perfil',
                ),
              ],
            ),
          ),
        );
      },
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
            'Panel de gestión',
            style: GoogleFonts.montserrat(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Control administrativo y analítico municipal',
            style: GoogleFonts.inter(
              color: const Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          _buildAdminCard(
            context,
            title: 'Usuarios',
            subtitle: 'Directorio y control de accesos',
            icon: Icons.people_alt_rounded,
            color: Colors.blue[600]!,
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
            subtitle: 'Configuración tipográfica de incidencias',
            icon: Icons.category_rounded,
            color: Colors.indigo[600]!,
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
            color: const Color(0xFF059669),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context,
            title: 'Soporte Directo',
            subtitle: 'Atención al ciudadano UrbiConnect',
            icon: Icons.support_agent_rounded,
            color: Colors.orange[700]!,
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
    return Container(
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
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Color(0xFFCBD5E1), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
