import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/firebase_options.dart';
import 'package:urbi_connect/screens/auth/login_screen.dart';
import 'package:urbi_connect/screens/home_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            primary: const Color(0xFF6750A4),
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
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
                        child: const Text('YA LO HE VERIFICADO'),
                      ),
                      TextButton(
                        onPressed: () => authService.signOut(),
                        child: const Text('Cerrar Sesión'),
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
