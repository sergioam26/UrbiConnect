import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/firebase_options.dart';
import 'package:urbi_connect/screens/auth/login_screen.dart';
import 'package:urbi_connect/screens/home_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';

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
      ],
      child: MaterialApp(
        title: 'UrbiConnect',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F172A),
            primary: const Color(0xFF0F172A),
            secondary: const Color(0xFF4F46E5),
            tertiary: const Color(0xFF10B981), // Success/Mint
            surface: const Color(0xFFFFFFFF),
            surfaceContainerHighest: const Color(0xFFF8FAFC),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          textTheme: GoogleFonts.interTextTheme(
            const TextTheme(
              displayLarge: TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              displayMedium: TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              headlineMedium: TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              titleLarge: TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
          ).copyWith(
            displayLarge: GoogleFonts.montserrat(
                fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
            displayMedium: GoogleFonts.montserrat(
                fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
            headlineLarge: GoogleFonts.montserrat(
                fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
          ),
          appBarTheme: AppBarTheme(
            centerTitle: true,
            backgroundColor: const Color(0xFFF8FAFC),
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: GoogleFonts.montserrat(
              color: const Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFE2E8F0)), // Slate 200
            ),
            color: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle:
                  GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
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
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
            ),
            labelStyle: const TextStyle(color: Color(0xFF64748B)),
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
        home: const AuthWrapper(),
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
                      const Icon(Icons.mark_email_unread_outlined,
                          size: 80, color: Colors.orange),
                      const SizedBox(height: 24),
                      const Text(
                        'Verifica tu correo',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Hemos enviado un enlace a ${user.email}. Por favor, verifícalo para continuar.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () async {
                          await user.reload();
                          // El StreamBuilder se reconstruirá solo si el estado cambia
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
