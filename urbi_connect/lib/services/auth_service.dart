import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '828754552495-p3ka5ud01ce5770tdgcodpp279qprvo7.apps.googleusercontent.com',
  );

  Stream<User?> get user => _auth.authStateChanges();

  // Sign in with Email/Username and Password
  Future<String?> signIn(String identifier, String password) async {
    try {
      String email = identifier;

      // Si no parece un email (no tiene @), buscamos el email asociado al usuario en Firestore
      if (!identifier.contains('@')) {
        final userQuery = await _db
            .collection('users')
            .where('usuario', isEqualTo: identifier)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) {
          return 'El nombre de usuario no existe.';
        }
        email = userQuery.docs.first.get('email');
      }

      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // Éxito
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No existe ninguna cuenta con este email.';
        case 'wrong-password':
          return 'La contraseña es incorrecta.';
        case 'invalid-email':
          return 'El formato del email no es válido.';
        case 'user-disabled':
          return 'Esta cuenta ha sido deshabilitada.';
        case 'invalid-credential':
          return 'Credenciales incorrectas (usuario o contraseña).';
        default:
          return 'Error: ${e.message}';
      }
    } catch (e) {
      return 'Ocurrió un error inesperado: $e';
    }
  }

  // Register with Email, Password and extra fields
  Future<User?> register({
    required String email,
    required String password,
    required String name,
    required String surnames,
    required String username,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      if (user != null) {
        // Send verification email
        await user.sendEmailVerification();

        // Store extra data in Firestore
        await _db.collection('users').doc(user.uid).set({
          'nombre': name,
          'apellidos': surnames,
          'usuario': username,
          'email': email,
          'rol': 'Ciudadano',
          'fecha_registro': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }

  // Sign in with Google
  Future<String?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // El usuario canceló

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user != null) {
        // Check if user exists in Firestore, if not, create profile
        DocumentSnapshot doc =
            await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await _db.collection('users').doc(user.uid).set({
            'nombre': user.displayName ?? '',
            'apellidos': '',
            'usuario': user.email?.split('@')[0] ?? '',
            'email': user.email ?? '',
            'rol': 'Ciudadano',
            'fecha_registro': FieldValue.serverTimestamp(),
          });
        }
      }
      return null; // Éxito
    } on FirebaseAuthException catch (e) {
      return 'Error de Firebase: ${e.message}';
    } catch (e) {
      debugPrint('Error en Google Sign-In: $e');
      return 'No se pudo iniciar sesión con Google.';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
