import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/firebase_options.dart';
import 'package:urbi_connect/screens/auth/login_screen.dart';
import 'package:urbi_connect/screens/home_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/theme_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Manejando mensaje en segundo plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar localización para intl
  await initializeDateFormatting('es_ES', null);
  Intl.defaultLocale = 'es_ES';

  // Configurar manejador de mensajes en segundo plano
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const UrbiConnectApp());
}

class UrbiConnectApp extends StatelessWidget {
  const UrbiConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
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
