# UrbiConnect 🏙️

[![Flutter](https://img.shields.io/badge/Flutter-3.0.0+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Enterprise-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com/)
[![Google Maps](https://img.shields.io/badge/Google%20Maps-Platform-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white)](https://mapsplatform.google.com/)

**UrbiConnect** es una plataforma de gestión de incidencias municipal desarrollada para el **Ayuntamiento de Cantillana**. El sistema facilita la comunicación entre los ciudadanos y los servicios operativos, permitiendo el reporte, seguimiento y resolución de problemas en la vía pública de manera organizada.

---

## Vista general

La aplicación está estructurada para dar servicio a tres tipos de perfiles:

1.  **Ciudadano:** Registra incidencias con fotos y ubicación GPS, y recibe actualizaciones sobre su estado.
2.  **Responsable municipal:** Recibe y gestiona las incidencias asignadas según su categoría profesional.
3.  **Administrador:** Supervisa el sistema, gestiona usuarios y emite comunicados oficiales.

---

## Funcionalidades principales

### Gestión de incidencias

- **Reporte ciudadano:** Interfaz para documentar incidencias con descripción, categoría y archivos multimedia.
- **Seguimiento en tiempo real:** Historial de reportes con estados actualizados (Abierto, En proceso, Finalizado).
- **Geolocalización:** Uso de Google Maps para situar con precisión el origen de la incidencia.

### Herramientas para responsables

- **Bandeja de trabajo:** Listado de incidencias filtrado automáticamente por la categoría asignada al técnico.

### Administración y soporte

- **Control de usuarios:** Gestión de roles y permisos desde el panel administrativo.
- **Notificaciones push:** Envío de avisos individuales o masivos (broadcast) a los ciudadanos.
- **Centro de soporte:** Chat integrado para la resolución de dudas técnicas sobre la aplicación.

---

## Especificaciones técnicas

- **Framework:** [Flutter](https://flutter.dev/) (v3.0+) para soporte multiplataforma (Web y móvil).
- **Base de datos:** [Cloud Firestore](https://firebase.google.com/docs/firestore) para persistencia en tiempo real.
- **Almacenamiento:** [Firebase Storage](https://firebase.google.com/docs/storage) para la gestión de imágenes.
- **Autenticación:** [Firebase Auth](https://firebase.google.com/docs/auth) con soporte para Google Sign-In y Email/Password.
- **Localización:** Integración con la API de Google Maps.

---

## Estructura del proyecto

```text
lib/
├── components/     # Componentes de interfaz reutilizables.
├── models/         # Modelos de datos y lógica de serialización.
├── screens/        # Vistas organizadas por módulos:
│   ├── auth/       # Registro y acceso.
│   ├── admin/      # Gestión de usuarios y reportes.
│   ├── incidents/  # Reporte y mapas de incidencias.
│   ├── messages/   # Mensajería y notificaciones.
│   ├── support/    # Chat de soporte técnico.
│   └── profile/    # Gestión de cuenta personal.
├── services/       # Integración con Firebase y lógica de negocio.
└── main.dart       # Punto de entrada de la aplicación.
```

---

## Configuración y ejecución

### Requisitos previos

- Flutter SDK instalado.
- Proyecto configurado en Firebase Console.
- API Key de Google Maps habilitada.

### Pasos para ejecución local

1.  **Clonar el repositorio:** `git clone https://github.com/tu-usuario/urbi_connect.git`
2.  **Instalar dependencias:** `flutter pub get`
3.  **Configurar Firebase:** Añadir los archivos `google-services.json` (Android) o `GoogleService-Info.plist` (iOS) correspondientes.
4.  **Ejecutar:** `flutter run`

---

## Despliegue

### Compilación para web

```bash
flutter build web --release
```

### Compilación para Android

```bash
flutter build apk --release
```

---

## Información del proyecto

Este software ha sido desarrollado específicamente para el **Ayuntamiento de Cantillana**.  
© 2026 UrbiConnect. Todos los derechos reservados.
