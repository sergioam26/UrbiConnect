import 'dart:io' show File;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentFormScreen extends StatefulWidget {
  const IncidentFormScreen({super.key});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  final _descriptionController = TextEditingController();

  String _category = 'LIMPIEZA';
  XFile? _imageFile;
  Uint8List? _webImage;
  Position? _currentPosition;
  bool _isLoading = false;

  final List<String> _categories = [
    'LIMPIEZA',
    'ALUMBRADO',
    'VÍA PÚBLICA',
    'RED DE ALCANTARILLADO',
    'CONTROL DE PLAGAS',
    'JARDINERÍA',
    'TRÁFICO Y SEÑALIZACIÓN',
    'MOBILIARIO URBANO',
    'OBRAS O INFRAESTRUCTURA EN CONSTRUCCIÓN',
  ];

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50, // Reducimos más la calidad para ganar velocidad
        maxWidth:
            800, // Reducimos la resolución a 800px (suficiente para ver incidencias)
        maxHeight: 800,
      );
      if (pickedFile != null) {
        // Validar que sea una imagen en Web
        if (kIsWeb) {
          final String fileName = pickedFile.name.toLowerCase();
          if (!fileName.endsWith('.jpg') &&
              !fileName.endsWith('.jpeg') &&
              !fileName.endsWith('.png') &&
              !fileName.endsWith('.webp')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Por favor, selecciona solo archivos de imagen (jpg, png, webp).')),
              );
            }
            return;
          }
        }

        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _webImage = bytes;
            _imageFile = pickedFile;
          });
        } else {
          setState(() {
            _imageFile = pickedFile;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al acceder a la cámara/galería: $e')),
        );
      }
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Cámara'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Los servicios de ubicación están desactivados.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Permisos de ubicación denegados permanentemente.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación capturada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al obtener ubicación: $e')),
      );
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_imageFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Por favor, toma una foto de la incidencia.')),
        );
        return;
      }

      if (_currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, captura la ubicación GPS.')),
        );
        return;
      }

      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      try {
        String? imageUrl;
        try {
          if (kIsWeb) {
            imageUrl = await _dbService.uploadImageWeb(_webImage!);
          } else {
            imageUrl = await _dbService.uploadImage(File(_imageFile!.path));
          }
        } catch (e) {
          debugPrint('Error uploading image: $e');
        }

        if (imageUrl == null) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          String errorMsg = 'Error al subir la imagen.';
          if (kIsWeb) {
            errorMsg +=
                ' Esto suele deberse a un problema de CORS en Firebase Storage. Por favor, sigue las instrucciones para configurar CORS.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'CERRAR',
                onPressed: () {},
              ),
            ),
          );
          return;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        Incident incident = Incident(
          id: '', // Firestore generará el ID
          description: _descriptionController.text,
          imageUrl: imageUrl,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          createdAt: DateTime.now(),
          status: 'pendiente',
          userId: user.uid,
          categoryId: _category,
        );

        await _dbService.createIncident(incident);

        if (!mounted) return;
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia enviada con éxito.')),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar incidencia: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva incidencia')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      items: _categories
                          .map((label) => DropdownMenuItem(
                              value: label,
                              child: Text(label,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (value) => setState(() => _category = value!),
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, describe el problema';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              if (_imageFile != null)
                                Container(
                                  height: 150,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb
                                        ? Image.memory(_webImage!,
                                            fit: BoxFit.cover)
                                        : Image.file(File(_imageFile!.path),
                                            fit: BoxFit.cover),
                                  ),
                                )
                              else
                                Container(
                                  height: 150,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.image,
                                      size: 50, color: Colors.grey),
                                ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _showImageSourceActionSheet(context),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Añadir Foto'),
                                style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 40)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                height: 150,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: _currentPosition != null
                                      ? Colors.green[50]
                                      : Colors.grey[200],
                                  border: Border.all(
                                      color: _currentPosition != null
                                          ? Colors.green
                                          : Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _currentPosition != null
                                          ? Icons.location_on
                                          : Icons.location_off,
                                      size: 50,
                                      color: _currentPosition != null
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                    if (_currentPosition != null)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0),
                                        child: Text(
                                          'Lat: ${_currentPosition!.latitude.toStringAsFixed(4)}\nLong: ${_currentPosition!.longitude.toStringAsFixed(4)}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _getCurrentLocation,
                                icon: const Icon(Icons.my_location),
                                label: const Text('Ubicación'),
                                style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 40)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6750A4),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('ENVIAR INCIDENCIA',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
