import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbi_connect/config/app_config.dart';
import 'package:urbi_connect/firebase_options.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/auth/login_screen.dart';
import 'package:urbi_connect/screens/home_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/notification_service.dart';
import 'package:urbi_connect/services/theme_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint(
          "Firebase ya estaba inicializado o falló en _firebaseMessagingBackgroundHandler: $e");
    }
    debugPrint("Manejando mensaje en segundo plano: ${message.messageId}");

    final notification = message.notification;
    final data = message.data;

    // Extraer título y cuerpo con total tolerancia a idiomas/formatos de FCM
    String title = notification?.title ??
        data['titulo']?.toString() ??
        data['title']?.toString() ??
        data['notification_title']?.toString() ??
        'UrbiConnect';
    String body = notification?.body ??
        data['mensaje']?.toString() ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        data['content']?.toString() ??
        data['contenido']?.toString() ??
        data['notification_body']?.toString() ??
        '';

    if (title.isNotEmpty || body.isNotEmpty) {
      // Filtrar notificaciones según los roles que el usuario tiene activados para recibir push (usando SharedPreferences para aislamiento total en segundo plano)
      bool isAllowed = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final List<String>? enabledPushRoles =
            prefs.getStringList('enabled_push_roles');

        if (enabledPushRoles != null) {
          debugPrint(
              "Filtro background: Roles habilitados encontrados en caché local: $enabledPushRoles");

          final String localRole =
              prefs.getString('user_profile_role') ?? 'ciudadano';
          final String emailVal =
              (prefs.getString('user_profile_email') ?? '').toLowerCase();

          // Determinar a qué rol va dirigida esta notificación
          final type = data['type'] ?? data['tipo'] ?? '';
          final typeStr = type.toString().toLowerCase();
          final titleLower = title.toLowerCase();
          final bodyLower = body.toLowerCase();

          // Buscar destinatarios explícitos en el mensaje
          List<dynamic>? dests;
          final destsVal = data['destinatarios'];
          if (destsVal != null) {
            if (destsVal is List) {
              dests = destsVal;
            } else if (destsVal is String) {
              final str = destsVal.trim();
              if (str.startsWith('[') && str.endsWith(']')) {
                final content = str.substring(1, str.length - 1);
                dests = content
                    .split(',')
                    .map((s) =>
                        s.replaceAll('"', '').replaceAll('\'', '').trim())
                    .toList();
              } else {
                dests = destsVal.split(',').map((s) => s.trim()).toList();
              }
            }
          }

          String targetRole = 'ciudadano'; // por defecto

          if (dests != null && dests.isNotEmpty) {
            final destList =
                dests.map((e) => e.toString().toLowerCase()).toList();
            if (destList.any((d) => d.contains('admin'))) {
              targetRole = 'admin';
            } else if (destList.any((d) => d.contains('responsable'))) {
              targetRole = 'responsable';
            } else {
              targetRole = 'ciudadano';
            }
          } else {
            if (typeStr == 'chat_soporte' ||
                typeStr == 'soporte' ||
                (data['is_admin_notification'] ?? '').toString() == 'true') {
              targetRole = 'admin';
            } else if (typeStr == 'recordatorio') {
              targetRole = 'responsable';
            } else if (typeStr == 'chat') {
              if (bodyLower.contains('designado') ||
                  titleLower.contains('asignada') ||
                  titleLower.contains('responsable') ||
                  bodyLower.contains('asignado') ||
                  bodyLower.contains('el ciudadano') ||
                  bodyLower.contains('ciudadano ha enviado')) {
                targetRole = 'responsable';
              } else if (bodyLower.contains('el responsable') ||
                  bodyLower.contains('ayuntamiento') ||
                  bodyLower.contains('municipal ha enviado')) {
                targetRole = 'ciudadano';
              } else {
                String activeUserRole = localRole;
                if (emailVal == AppConfig.superUserEmail.toLowerCase() ||
                    emailVal == 'sergioalgmir@gmail.com') {
                  final savedSuperRole = prefs.getString('super_active_role');
                  if (savedSuperRole != null) {
                    activeUserRole = savedSuperRole.toLowerCase();
                  }
                }
                targetRole = activeUserRole;
              }
            } else if (typeStr == 'incidencia' ||
                typeStr == 'incidencia_editada') {
              final isForResponsible = titleLower.contains('nueva') ||
                  titleLower.contains('asignada') ||
                  bodyLower.contains('asignado') ||
                  bodyLower.contains('se ha reportado');
              if (isForResponsible) {
                targetRole = 'responsable';
              } else {
                targetRole = 'ciudadano';
              }
            }
          }

          // Función para comprobar si el rol de destino está habilitado en este dispositivo
          bool isRoleEnabled(List<dynamic> enabled, String target) {
            if (enabled.isEmpty) return false;
            final trl = target.toLowerCase().trim();
            return enabled.any((er) {
              final erl = er.toString().toLowerCase().trim();
              return erl == trl ||
                  trl.contains(erl) ||
                  erl.contains(trl) ||
                  (trl.contains('responsable') &&
                      erl.contains('responsable')) ||
                  (trl.contains('admin') && erl.contains('admin')) ||
                  (trl.contains('ciudadano') && erl.contains('ciudadano'));
            });
          }

          if (!isRoleEnabled(enabledPushRoles, targetRole)) {
            debugPrint(
                "FILTRANDO PUSH EN SEGUNDO PLANO (RESTRICCIÓN LOCAL SHPREFS ACTIVA): El rol destino '$targetRole' NO está habilitado para recibir notificaciones en este dispositivo. Preferencias locales: $enabledPushRoles");
            isAllowed = false;
          }
        } else {
          debugPrint(
              "Filtro background: Caché local no persistida. Iniciando fallback de autenticación...");
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            final profileDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
            if (profileDoc.exists) {
              final profileData = profileDoc.data();
              if (profileData != null) {
                final emailVal =
                    (profileData['email'] ?? '').toString().toLowerCase();
                final List<dynamic> firestoreEnabledPushRoles =
                    profileData.containsKey('enabled_push_roles')
                        ? List.from(profileData['enabled_push_roles'])
                        : ['admin', 'responsable', 'ciudadano'];

                // Guardar/actualizar la caché local para futuras ejecuciones en segundo plano
                await prefs.setStringList(
                    'enabled_push_roles',
                    firestoreEnabledPushRoles
                        .map((e) => e.toString())
                        .toList());
                await prefs.setString(
                    'user_profile_role',
                    (profileData['rol'] ?? 'ciudadano')
                        .toString()
                        .toLowerCase());
                await prefs.setString('user_profile_email', emailVal);

                // Determinar a qué rol va dirigida esta notificación
                final type = data['type'] ?? data['tipo'] ?? '';
                final typeStr = type.toString().toLowerCase();
                final titleLower = title.toLowerCase();
                final bodyLower = body.toLowerCase();

                // Buscar destinatarios explícitos en el mensaje
                List<dynamic>? dests;
                final destsVal = data['destinatarios'];
                if (destsVal != null) {
                  if (destsVal is List) {
                    dests = destsVal;
                  } else if (destsVal is String) {
                    final str = destsVal.trim();
                    if (str.startsWith('[') && str.endsWith(']')) {
                      final content = str.substring(1, str.length - 1);
                      dests = content
                          .split(',')
                          .map((s) =>
                              s.replaceAll('"', '').replaceAll('\'', '').trim())
                          .toList();
                    } else {
                      dests = destsVal.split(',').map((s) => s.trim()).toList();
                    }
                  }
                }

                String targetRole = 'ciudadano'; // por defecto

                if (dests != null && dests.isNotEmpty) {
                  final destList =
                      dests.map((e) => e.toString().toLowerCase()).toList();
                  if (destList.any((d) => d.contains('admin'))) {
                    targetRole = 'admin';
                  } else if (destList.any((d) => d.contains('responsable'))) {
                    targetRole = 'responsable';
                  } else {
                    targetRole = 'ciudadano';
                  }
                } else {
                  if (typeStr == 'chat_soporte' ||
                      typeStr == 'soporte' ||
                      (data['is_admin_notification'] ?? '').toString() ==
                          'true') {
                    targetRole = 'admin';
                  } else if (typeStr == 'recordatorio') {
                    targetRole = 'responsable';
                  } else if (typeStr == 'chat') {
                    if (bodyLower.contains('designado') ||
                        titleLower.contains('asignada') ||
                        titleLower.contains('responsable') ||
                        bodyLower.contains('asignado') ||
                        bodyLower.contains('el ciudadano') ||
                        bodyLower.contains('ciudadano ha enviado')) {
                      targetRole = 'responsable';
                    } else if (bodyLower.contains('el responsable') ||
                        bodyLower.contains('ayuntamiento') ||
                        bodyLower.contains('municipal ha enviado')) {
                      targetRole = 'ciudadano';
                    } else {
                      String activeUserRole =
                          (profileData['rol'] ?? 'ciudadano')
                              .toString()
                              .toLowerCase();
                      if (emailVal == AppConfig.superUserEmail.toLowerCase() ||
                          emailVal == 'sergioalgmir@gmail.com') {
                        final savedSuperRole =
                            prefs.getString('super_active_role');
                        if (savedSuperRole != null) {
                          activeUserRole = savedSuperRole.toLowerCase();
                        }
                      }
                      targetRole = activeUserRole;
                    }
                  } else if (typeStr == 'incidencia' ||
                      typeStr == 'incidencia_editada') {
                    final isForResponsible = titleLower.contains('nueva') ||
                        titleLower.contains('asignada') ||
                        bodyLower.contains('asignado') ||
                        bodyLower.contains('se ha reportado');
                    if (isForResponsible) {
                      targetRole = 'responsable';
                    } else {
                      targetRole = 'ciudadano';
                    }
                  }
                }

                bool isRoleEnabled(List<dynamic> enabled, String target) {
                  if (enabled.isEmpty) return false;
                  final trl = target.toLowerCase().trim();
                  return enabled.any((er) {
                    final erl = er.toString().toLowerCase().trim();
                    return erl == trl ||
                        trl.contains(erl) ||
                        erl.contains(trl) ||
                        (trl.contains('responsable') &&
                            erl.contains('responsable')) ||
                        (trl.contains('admin') && erl.contains('admin')) ||
                        (trl.contains('ciudadano') &&
                            erl.contains('ciudadano'));
                  });
                }

                if (!isRoleEnabled(firestoreEnabledPushRoles, targetRole)) {
                  debugPrint(
                      "FILTRANDO PUSH EN SEGUNDO PLANO (RESTRICCIÓN FALLBACK FIRESTORE ACTIVA): El rol destino '$targetRole' NO está habilitado para recibir notificaciones en este dispositivo. Preferencias: $firestoreEnabledPushRoles");
                  isAllowed = false;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint(
            "Error consultando preferencias de roles en segundo plano: $e");
      }

      if (!isAllowed) {
        return; // Detener visualización de la notificación, está filtrada
      }

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

      // Configuración mínima de Android para segundo plano
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await flutterLocalNotificationsPlugin.initialize(initSettings);

      // Crear ambos canales para compatibilidad absoluta con cualquier backend / Cloud Function
      const channelNew = AndroidNotificationChannel(
        'urbi_connect_alerts_channel_v1',
        'UrbiConnect Notificaciones',
        description: 'Este canal se usa para notificaciones importantes.',
        importance: Importance.max,
      );

      const channelLegacy = AndroidNotificationChannel(
        'high_importance_channel',
        'UrbiConnect Alertas',
        description: 'Canal heredado de notificaciones importantes.',
        importance: Importance.max,
      );

      final androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(channelNew);
        await androidPlugin.createNotificationChannel(channelLegacy);
      }

      // Mostrar la notificación local desde segundo plano con el de mayor compatibilidad (Legacy como primario para FCM Cloud Functions y V1 como secundario)
      final String payloadChannelId = data['android_channel_id']?.toString() ??
          data['channel_id']?.toString() ??
          data['channelId']?.toString() ??
          'high_importance_channel';

      await flutterLocalNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            payloadChannelId == 'urbi_connect_alerts_channel_v1'
                ? 'urbi_connect_alerts_channel_v1'
                : 'high_importance_channel',
            'UrbiConnect Notificaciones',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: 'ic_launcher',
          ),
        ),
        payload: jsonEncode(data),
      );
      debugPrint(
          "Notificación renderizada con éxito en segundo plano para: $title - $body");
    }
  } catch (e) {
    debugPrint("Error crítico en _firebaseMessagingBackgroundHandler: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configurar manejador de mensajes en segundo plano lo antes posible
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar localización para intl
  await initializeDateFormatting('es_ES', null);
  Intl.defaultLocale = 'es_ES';

  // Cargar rol guardado del superusuario
  await SuperuserSession.loadSavedRole();

  // Cargar tema guardado
  bool isDarkStored = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    isDarkStored = prefs.getBool('is_dark_mode') ?? false;
  } catch (e) {
    debugPrint('Error loading saved theme in main: $e');
  }

  runApp(UrbiConnectApp(initialIsDark: isDarkStored));
}

class UrbiConnectApp extends StatelessWidget {
  final bool initialIsDark;

  const UrbiConnectApp({super.key, required this.initialIsDark});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(
            create: (_) => ThemeService(initialIsDark: initialIsDark)),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'UrbiConnect',
            debugShowCheckedModeBanner: false,
            locale: const Locale('es', 'ES'),
            supportedLocales: const [
              Locale('es', 'ES'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            themeMode: themeService.themeMode,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: const ColorScheme(
                brightness: Brightness.light,
                primary: Color(0xFF1E293B), // Navy Slate
                onPrimary: Colors.white,
                secondary: Color(0xFF334155), // Mid Slate
                onSecondary: Colors.white,
                tertiary: Color(0xFF475569), // Light Navy Slate
                onTertiary: Colors.white,
                error: Color(0xFFB91C1C),
                onError: Colors.white,
                surface: Colors.white,
                onSurface: Color(0xFF0F172A),
                surfaceContainerHighest: Color(0xFFF1F5F9),
                outline: Color(0xFFE2E8F0),
                outlineVariant: Color(0xFFF1F5F9),
              ),
              scaffoldBackgroundColor: const Color(0xFFF8FAFC),
              textTheme: GoogleFonts.interTextTheme(
                const TextTheme(
                  displayLarge: TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                  titleLarge: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                  bodyLarge: TextStyle(color: Color(0xFF334155)),
                ),
              ),
              appBarTheme: AppBarTheme(
                centerTitle: true,
                backgroundColor: const Color(0xFFF8FAFC),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                titleTextStyle: GoogleFonts.montserrat(
                  color: const Color(0xFF1E293B),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF1E293B), width: 2),
                ),
                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: const ColorScheme(
                brightness: Brightness.dark,
                primary:
                    Color(0xFF3B82F6), // Strong Blue for visibility on dark
                onPrimary: Colors.white,
                secondary: Color(0xFF94A3B8),
                onSecondary: Colors.black,
                tertiary: Color(0xFF1E293B),
                onTertiary: Colors.white,
                error: Color(0xFFEF4444),
                onError: Colors.white,
                surface: Color(0xFF020617), // Deep Dark Slate
                onSurface: Color(0xFFF8FAFC),
                surfaceContainerHighest: Color(0xFF0F172A),
                outline: Color(0xFF1E293B),
                outlineVariant: Color(0xFF0F172A),
              ),
              scaffoldBackgroundColor: const Color(0xFF020617),
              textTheme: GoogleFonts.interTextTheme(
                const TextTheme(
                  displayLarge: TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFFF8FAFC)),
                  titleLarge: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFF8FAFC)),
                  bodyLarge: TextStyle(color: Color(0xFFF8FAFC)),
                  bodyMedium: TextStyle(color: Color(0xFFF1F5F9)),
                ),
              ),
              appBarTheme: AppBarTheme(
                centerTitle: true,
                backgroundColor: const Color(0xFF020617),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                titleTextStyle: GoogleFonts.montserrat(
                  color: const Color(0xFFF8FAFC),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                iconTheme: const IconThemeData(color: Color(0xFFF8FAFC)),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF3B82F6), width: 2),
                ),
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            navigatorKey: NotificationService.navigatorKey,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return StreamBuilder<User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return const LoginScreen();
          }

          // Check if email is verified (only for email/password users)
          final isGoogleUser =
              user.providerData.any((p) => p.providerId == 'google.com');
          if (!user.emailVerified && !isGoogleUser) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mark_email_unread_outlined,
                          size: 80,
                          color: Theme.of(context).colorScheme.secondary),
                      const SizedBox(height: 24),
                      Text(
                        'Verifica tu correo',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Hemos enviado un enlace a ${user.email}. Por favor, verifícalo para continuar.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            await user.reload();
                            final updatedUser =
                                FirebaseAuth.instance.currentUser;
                            if (updatedUser != null &&
                                updatedUser.emailVerified) {
                              // Update Firestore flag
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(updatedUser.uid)
                                  .update({'email_verificado': true});
                            } else if (updatedUser != null &&
                                !updatedUser.emailVerified) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'El correo aún no ha sido verificado. Por favor, revisa tu bandeja de entrada o spam y vuelve a intentarlo.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error al verificar: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Ya lo he verificado'),
                      ),
                      TextButton(
                        onPressed: () => authService.signOut(),
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return const HomeScreen();
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
