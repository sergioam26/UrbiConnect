const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// Esta función se ejecuta sola cuando alguien crea un documento en "Notificaciones"
exports.sendPushNotification = onDocumentCreated("Notificaciones/{notifId}", async (event) => {
    const data = event.data.data(); // Datos del aviso que acabas de guardar
    const userId = data.id_usuario;

    try {
        // 1. Buscamos el token del móvil del usuario en tu colección 'users'
        const userDoc = await admin.firestore().collection("users").doc(userId).get();
        
        if (!userDoc.exists) {
            console.log("El usuario no existe");
            return null;
        }

        const fcmToken = userDoc.data().fcm_token;

        if (!fcmToken) {
            console.log("El usuario no tiene un token de dispositivo registrado");
            return null;
        }

        // 2. Construimos el mensaje que recibirá el móvil (Push)
        const message = {
            token: fcmToken,
            notification: {
                title: data.titulo,
                body: data.mensaje,
            },
            // Datos extra por si la app quiere hacer algo al pinchar (como ir a la incidencia)
            data: {
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                id_referencia: data.id_referencia || "",
                tipo: data.tipo || ""
            }
        };

        // 3. Enviamos la notificación a través de los servidores de Google
        const response = await admin.messaging().send(message);
        console.log("Notificación enviada con éxito:", response);
        return response;

    } catch (error) {
        console.error("Error al enviar la notificación:", error);
        return null;
    }
});