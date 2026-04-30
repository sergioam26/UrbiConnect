import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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

        // Check if a profile was pre-created by Admin
        final preProfileQuery = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .get();
        String role = 'ciudadano';

        // Default Admin for the project owner
        if (email == 'sergioalgmir@gmail.com') {
          role = 'admin';
        }

        String? category;

        if (preProfileQuery.docs.isNotEmpty) {
          final preDoc = preProfileQuery.docs.first;
          role = (preDoc.get('rol') ?? 'ciudadano').toString().toLowerCase();
          category = preDoc.data().containsKey('id_categoria')
              ? preDoc.get('id_categoria')
              : null;

          // Delete the temporary pre-profile if it was using email as ID
          if (preDoc.id == email) {
            await _db.collection('users').doc(email).delete();
          }
        }

        // Store extra data in Firestore with the correct UID
        await _db.collection('users').doc(user.uid).set({
          'nombre': name,
          'apellidos': surnames,
          'usuario': username,
          'email': email,
          'rol': role,
          'id_categoria': category,
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
      UserCredential userCredential;

      if (kIsWeb) {
        // En web, usamos signInWithPopup directamente con Firebase Auth.
        // Esto es más robusto para entornos de iframe y maneja mejor los orígenes autorizados.
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // En móvil/nativo, usamos el flujo normal de google_sign_in
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null; // El usuario canceló
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      User? user = userCredential.user;

      if (user != null) {
        // Check if user exists in Firestore, if not, create profile
        DocumentSnapshot doc =
            await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          final email = user.email ?? '';

          // Check if a profile was pre-created by Admin
          final preProfileQuery = await _db
              .collection('users')
              .where('email', isEqualTo: email)
              .get();
          String role = 'ciudadano';

          // Default Admin for the project owner
          if (email == 'sergioalgmir@gmail.com') {
            role = 'admin';
          }

          String? category;
          String name = user.displayName ?? '';

          if (preProfileQuery.docs.isNotEmpty) {
            final preDoc = preProfileQuery.docs.first;
            role = (preDoc.get('rol') ?? 'ciudadano').toString().toLowerCase();
            category = preDoc.data().containsKey('id_categoria')
                ? preDoc.get('id_categoria')
                : null;
            name = preDoc.get('nombre') ?? name;

            if (preDoc.id == email) {
              await _db.collection('users').doc(email).delete();
            }
          }

          await _db.collection('users').doc(user.uid).set({
            'nombre': name,
            'apellidos': '',
            'usuario': email.split('@')[0],
            'email': email,
            'rol': role,
            'id_categoria': category,
            'fecha_registro': FieldValue.serverTimestamp(),
          });
        }
      }
      return null; // Éxito
    } on FirebaseAuthException catch (e) {
      return 'Error de Firebase: ${e.message}';
    } catch (e) {
      debugPrint('Error en Google Sign-In: $e');
      return 'No se pudo iniciar sesión con Google. Revisa la consola para más detalles.';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Check if user has a password set (Email provider)
  bool get hasPassword {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }
    return user.providerData.any((p) => p.providerId == 'password');
  }

  // Check if username is available
  Future<bool> isUsernameAvailable(String username,
      {String? excludeUid}) async {
    final query = await _db
        .collection('users')
        .where('usuario', isEqualTo: username)
        .get();

    if (excludeUid != null) {
      return query.docs.isEmpty ||
          (query.docs.length == 1 && query.docs.first.id == excludeUid);
    }
    return query.docs.isEmpty;
  }

  // Check if email is available
  Future<bool> isEmailAvailable(String email, {String? excludeEmail}) async {
    // Note: This only checks Firestore, not Firebase Auth directly.
    // For a more robust check during registration, Auth throws email-already-in-use.
    final query =
        await _db.collection('users').where('email', isEqualTo: email).get();

    if (excludeEmail != null) {
      return query.docs.isEmpty ||
          (query.docs.length == 1 &&
              query.docs.first.get('email') == excludeEmail);
    }
    return query.docs.isEmpty;
  }

  // Update profile
  Future<String?> updateProfile({
    required String uid,
    required String name,
    required String surnames,
    required String username,
    String? email,
    String? currentPassword, // Required for email change
    String? photoUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return 'No hay usuario autenticado';
      }

      // 1. Handle Email Change if provided and different
      if (email != null && email != user.email) {
        if (currentPassword == null) {
          return 'Se requiere la contraseña para cambiar el email';
        }

        // Re-authenticate
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);

        // Update Email in Auth (Modern way sends verification automatically)
        await user.verifyBeforeUpdateEmail(email);
        // Note: The email in Firebase Auth won't change until the user clicks the link in their new email.
      }

      // 2. Update Firestore
      Map<String, dynamic> updates = {
        'nombre': name,
        'apellidos': surnames,
        'usuario': username,
      };

      if (email != null) {
        updates['email'] = email;
      }
      if (photoUrl != null) {
        updates['foto_perfil'] = photoUrl;
      }

      await _db.collection('users').doc(uid).update(updates);

      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Este email ya está en uso por otra cuenta.';
        case 'wrong-password':
          return 'La contraseña es incorrecta.';
        case 'requires-recent-login':
          return 'Esta operación requiere un inicio de sesión reciente.';
        case 'operation-not-allowed':
          return 'Esta operación no está permitida. Contacta con soporte.';
        default:
          if (e.message?.contains('verify the new email') ?? false) {
            return 'Por seguridad, debes verificar el nuevo email antes de que el cambio sea efectivo. Se ha enviado un correo.';
          }
          return e.message;
      }
    } catch (e) {
      return e.toString();
    }
  }

  // Upload Profile Photo
  Future<String?> uploadProfilePhoto(String uid,
      {File? imageFile, Uint8List? imageBytes}) async {
    try {
      final storageRef =
          FirebaseStorage.instance.ref().child('user_photos').child('$uid.jpg');

      if (kIsWeb && imageBytes != null) {
        await storageRef.putData(imageBytes);
      } else if (imageFile != null) {
        await storageRef.putFile(imageFile);
      } else if (imageBytes != null) {
        await storageRef.putData(imageBytes);
      } else {
        return null;
      }

      final downloadUrl = await storageRef.getDownloadURL();

      await _db.collection('users').doc(uid).update({
        'foto_perfil': downloadUrl,
      });

      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  // Change password
  Future<String?> changePassword(
      String? currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No hay usuario autenticado';

      // If user has a password, we MUST re-authenticate
      if (hasPassword) {
        if (currentPassword == null || currentPassword.isEmpty) {
          return 'Se requiere la contraseña actual';
        }
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        // For Google/Social users setting a password for the first time
        // No current password needed, but updatePassword might still require recent login
      }

      // Actualizar contraseña
      await user.updatePassword(newPassword);
      return null; // Éxito
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          return 'La contraseña actual es incorrecta.';
        case 'requires-recent-login':
          return 'Esta operación requiere que vuelvas a iniciar sesión.';
        case 'weak-password':
          return 'La nueva contraseña es demasiado débil.';
        case 'user-not-found':
          return 'Usuario no encontrado.';
        case 'invalid-credential':
          return 'Las credenciales proporcionadas son incorrectas o han caducado.';
        default:
          return 'Ocurrió un error en la autenticación: ${e.message}';
      }
    } catch (e) {
      return e.toString();
    }
  }
}
