import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:urbi_connect/config/app_config.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthService() {
    _auth.setLanguageCode('es');
  }

  Stream<User?> get user => _auth.userChanges();

  // Helper para manejar timeouts y errores de red
  Future<T> _withTimeout<T>(Future<T> operation, {String? actionName}) async {
    try {
      return await operation.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw Exception('La conexión es lenta. Por favor, reintenta.'),
      );
    } catch (e) {
      debugPrint('Error en ${actionName ?? 'operación'}: $e');
      if (e.toString().contains('network-request-failed') ||
          e.toString().contains('unavailable')) {
        throw Exception(
            'Sin conexión estable. La operación se reintentará automáticamente.');
      }
      rethrow;
    }
  }

  // Sign in with Email/Username and Password
  Future<String?> signIn(String identifier, String password) async {
    return _withTimeout(() async {
      try {
        String email = identifier;

        if (!identifier.contains('@')) {
          final userQuery = await _db
              .collection('users')
              .where('usuario', isEqualTo: identifier)
              .limit(1)
              .get();

          if (userQuery.docs.isEmpty) {
            // Check if it might be a deleted account by checking his username?
            // Better to just say it doesn't exist if not in users.
            return 'El nombre de usuario no existe.';
          }
          email = userQuery.docs.first.get('email');
        }

        // Check if blocked/deleted
        if (await isEmailBlocked(email)) {
          return 'Esta cuenta ha sido eliminada y el acceso está bloqueado.';
        }

        await _auth.signInWithEmailAndPassword(
            email: email, password: password);
        return null;
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
    }(), actionName: 'Inicio de sesión');
  }

  // Register with Email, Password and extra fields
  Future<String?> register({
    required String email,
    required String password,
    required String name,
    required String surnames,
    required String username,
  }) async {
    try {
      // Check if email is blocked/deleted
      if (await isEmailBlocked(email)) {
        return 'Esta cuenta ha sido eliminada previamente y no se permite un nuevo registro con este correo.';
      }

      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      if (user != null) {
        // Configuración para que el enlace devuelva al usuario a tu web
        final actionCodeSettings = ActionCodeSettings(
          url: 'https://alumno21.fpcantillana.org/',
          handleCodeInApp: true,
        );

        // Envío de correo de verificación en español (configurado en el constructor)
        await user.sendEmailVerification(actionCodeSettings);

        // Check if a profile was pre-created by Admin
        final preProfileQuery = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .get();
        String role = 'ciudadano';

        // Default Admin for the project owner
        if (email.toLowerCase() == AppConfig.superUserEmail.toLowerCase()) {
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
          'email_verificado': false, // New flag for verification tracking
        });
      }
      return null; // Éxito
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Este correo electrónico ya está registrado. Intenta iniciar sesión.';
        case 'invalid-email':
          return 'El formato del email no es válido.';
        case 'weak-password':
          return 'La contraseña es muy débil. Usa al menos 6 caracteres.';
        case 'operation-not-allowed':
          return 'El registro con email/password no está habilitado.';
        default:
          return 'Error en Firebase: ${e.message}';
      }
    } catch (e) {
      debugPrint(e.toString());
      return 'Ocurrió un error inesperado al registrarse.';
    }
  }

  // Sign in with Google
  Future<String?> signInWithGoogle() async {
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        // Remove the restrictive 5s timeout for user-interactive popups
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return null; // User cancelled
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
        final email = user.email ?? '';

        // Comprobar si el usuario está bloqueado antes de procesar nada más
        if (await isEmailBlocked(email)) {
          await signOut();
          return 'Acceso denegado. Esta cuenta fue eliminada y no puede volver a utilizarse en el sistema.';
        }

        DocumentSnapshot doc =
            await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          final email = user.email ?? '';
          final preProfileQuery = await _db
              .collection('users')
              .where('email', isEqualTo: email)
              .get();
          String role = 'ciudadano';

          if (email.toLowerCase() == AppConfig.superUserEmail.toLowerCase()) {
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
            'email_verificado': true, // Google accounts are verified by default
          });
        } else {
          // Ensure verification flag is true for existing users signing in with Google
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null && data['email_verificado'] != true) {
            await _db
                .collection('users')
                .doc(user.uid)
                .update({'email_verificado': true});
          }
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      // Handle cancellation codes to not show them as errors
      final code = e.code.toLowerCase();
      if (code.contains('closed-by-user') ||
          code.contains('cancelled-popup-request') ||
          code.contains('user-cancelled')) {
        return null; // Silent return on cancel
      }
      return 'Error de Firebase: ${e.message}';
    } catch (e) {
      debugPrint('Error en Google Sign-In: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('popup_closed_by_user') ||
          errStr.contains('cancelled') ||
          errStr.contains('cancelado')) {
        return null;
      }
      return 'No se pudo iniciar sesión con Google.';
    }
  }

  // Enviar correo de recuperación de contraseña
  Future<String?> sendPasswordResetEmail(String email) async {
    return _withTimeout(() async {
      try {
        final emailLower = email.trim().toLowerCase();

        // 0. Validar formato de email
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
        if (!emailRegex.hasMatch(emailLower)) {
          return 'El formato del correo electrónico no es válido.';
        }

        // 1. Comprobar si está bloqueado/eliminado
        if (await isEmailBlocked(emailLower)) {
          return 'Esta cuenta ha sido eliminada y no es posible recuperar el acceso.';
        }

        // 2. Comprobar si existe en el sistema (usuarios activos y verificados)
        final userQuery = await _db
            .collection('users')
            .where('email', isEqualTo: emailLower)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) {
          return 'No hay ningún usuario activo registrado con ese email.';
        }

        final userData = userQuery.docs.first.data();
        if (userData['email_verificado'] != true) {
          return 'Debes verificar tu correo electrónico antes de poder recuperar la contraseña.';
        }

        await _auth.sendPasswordResetEmail(email: emailLower);
        return null;
      } on FirebaseAuthException catch (e) {
        switch (e.code) {
          case 'user-not-found':
            return 'No hay ningún usuario registrado con ese email.';
          case 'invalid-email':
            return 'El formato del email no es válido.';
          default:
            return e.message;
        }
      } catch (e) {
        return 'Error al enviar el correo de recuperación.';
      }
    }(), actionName: 'Recuperar contraseña');
  }

  // Comprobar si un email está en la lista de usuarios eliminados/bloqueados
  Future<bool> isEmailBlocked(String email) async {
    try {
      final doc = await _db
          .collection('deleted_users')
          .doc(email.trim().toLowerCase())
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('Error al comprobar email bloqueado: $e');
      return false;
    }
  }

  // Sync Auth email with Firestore
  Future<void> syncEmailWithFirestore() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        await user.reload(); // Refresh user state
        final refreshedUser = _auth.currentUser;
        if (refreshedUser != null && refreshedUser.email != null) {
          // Check if Firestore email differs
          final doc =
              await _db.collection('users').doc(refreshedUser.uid).get();
          if (doc.exists) {
            final firestoreEmail = doc.get('email') as String?;
            if (firestoreEmail != refreshedUser.email) {
              await _db.collection('users').doc(refreshedUser.uid).update({
                'email': refreshedUser.email,
              });
              debugPrint('Firestore email synced with verified Auth email');
            }
          }
        }
      } catch (e) {
        debugPrint('Error syncing email: $e');
      }
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

      bool emailChangeRequested = false;

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
        final actionCodeSettings = ActionCodeSettings(
          url: 'https://alumno21.fpcantillana.org/',
          handleCodeInApp: true,
        );
        await user.verifyBeforeUpdateEmail(email, actionCodeSettings);
        emailChangeRequested = true;
      }

      // 2. Update Firestore
      Map<String, dynamic> updates = {
        'nombre': name,
        'apellidos': surnames,
        'usuario': username,
      };

      // ONLY update email in Firestore if it matched the current verified email
      // and NO new email change was requested in this turn.
      // This prevents the Firestore email from changing before verification.
      if (email != null && !emailChangeRequested) {
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
      {File? imageFile,
      Uint8List? imageBytes,
      bool updateFirestore = true}) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${uid}_$timestamp.jpg');

      // SOLUCIÓN: Definimos los metadatos de imagen
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (kIsWeb && imageBytes != null) {
        await storageRef.putData(imageBytes, metadata);
      } else if (imageFile != null) {
        await storageRef.putFile(imageFile, metadata);
      } else if (imageBytes != null) {
        await storageRef.putData(imageBytes, metadata);
      } else {
        return null;
      }

      final downloadUrl = await storageRef.getDownloadURL();

      if (updateFirestore) {
        await _db.collection('users').doc(uid).update({
          'foto_perfil': downloadUrl,
        });
      }

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
      if (user == null) {
        return 'No hay usuario autenticado';
      }

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
