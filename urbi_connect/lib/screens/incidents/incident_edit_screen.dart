import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentEditScreen extends StatefulWidget {
  final Incident incident;
  const IncidentEditScreen({super.key, required this.incident});

  @override
  State<IncidentEditScreen> createState() => _IncidentEditScreenState();
}

class _IncidentEditScreenState extends State<IncidentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _addressController;

  String? _selectedCategoryId;
  List<Map<String, String>> _firestoreCategories = [];
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _webImages = [];
  List<String> _existingUrls = [];
  Position? _currentPosition;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.incident.title);
    _descriptionController =
        TextEditingController(text: widget.incident.description);
    _addressController = TextEditingController(text: widget.incident.address);
    _selectedCategoryId = widget.incident.categoryId;
    _existingUrls = List<String>.from(widget.incident.imageUrls ??
        (widget.incident.imageUrl != null ? [widget.incident.imageUrl!] : []));
    _currentPosition = Position(
      latitude: widget.incident.latitude,
      longitude: widget.incident.longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('Categoria').get();
      final cats = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'nombre': doc.get('nombre').toString(),
                'descripcion': doc.data().containsKey('descripcion')
                    ? doc.get('descripcion').toString()
                    : '',
              })
          .toList();

      setState(() {
        _firestoreCategories = cats;
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
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

      // Intentar obtener dirección (Reverse Geocoding)
      String? addr;
      try {
        // Preferimos Nominatim para todas las plataformas por consistencia y calidad de nombres
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1');
        final response = await http
            .get(url, headers: {'User-Agent': 'UrbiConnect_App_v1_Sergio'});
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final addrMap = data['address'] as Map<String, dynamic>?;
          if (addrMap != null) {
            final street = addrMap['road'] ??
                addrMap['pedestrian'] ??
                addrMap['cycleway'] ??
                '';
            final houseNum = addrMap['house_number'] ?? '';
            final city =
                addrMap['city'] ?? addrMap['town'] ?? addrMap['village'] ?? '';
            final postcode = addrMap['postcode'] ?? '';

            List<String> parts = [];
            if (street.isNotEmpty)
              parts.add(houseNum.isNotEmpty ? '$street, $houseNum' : street);
            if (city.isNotEmpty) parts.add(city);
            if (postcode.isNotEmpty) parts.add(postcode);
            addr = parts.join(', ');
          }
          if (addr == null || addr.isEmpty) {
            addr = data['display_name'];
          }
        }
      } catch (e) {
        debugPrint("Nominatim reverse geocoding fail: $e");
      }

      // Si falla Nominatim en móvil, intentamos con el paquete nativo
      if (addr == null && !kIsWeb) {
        try {
          List<geocoding.Placemark> placemarks = await geocoding
              .placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            geocoding.Placemark place = placemarks[0];
            addr =
                "${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}";
            addr = addr.replaceAll(RegExp(r'^, | ,'), '').trim();
            if (addr.endsWith(',')) addr = addr.substring(0, addr.length - 1);
          }
        } catch (e) {
          debugPrint("Native reverse geocoding fail: $e");
        }
      }

      if (addr != null && mounted) {
        _addressController.text = addr;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación actualizada correctamente.')),
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
      setState(() => _isLoading = true);

      final bool isWithin48Hours =
          DateTime.now().difference(widget.incident.createdAt).inHours < 48;
      if (!isWithin48Hours) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'El plazo de edición de 48 horas para este reporte ha expirado.'),
          ),
        );
        return;
      }

      if (_currentPosition == null) {
        if (mounted) setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Por favor, captura la ubicación GPS o selecciona una dirección de las sugerencias.')),
        );
        return;
      }

      if (_existingUrls.isEmpty && _imageFiles.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, añade al menos una foto')),
        );
        return;
      }

      try {
        final List<String> allUrls = List<String>.from(_existingUrls);

        // Subir nuevas imagenes
        for (int i = 0; i < _imageFiles.length; i++) {
          String? url;
          if (kIsWeb) {
            url = await _dbService.uploadImageWeb(_webImages[i]);
          } else {
            url = await _dbService.uploadImage(File(_imageFiles[i].path));
          }
          if (url != null) allUrls.add(url);
        }

        final updatedIncident = Incident(
          id: widget.incident.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: allUrls.first,
          imageUrls: allUrls,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          createdAt: widget.incident.createdAt,
          status: widget.incident.status,
          userId: widget.incident.userId,
          categoryId: _selectedCategoryId ?? widget.incident.categoryId,
        );

        await _dbService.updateIncident(updatedIncident);

        if (!mounted) return;
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia actualizada con éxito.')),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar incidencia: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar incidencia')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Editar los detalles de tu reporte',
                        style: TextStyle(color: Color(0xFF94A3B8))),
                    const SizedBox(height: 24),
                    if (_firestoreCategories.isEmpty)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        items: _firestoreCategories
                            .map((cat) => DropdownMenuItem(
                                  value: cat['id'],
                                  child: Text(cat['nombre']!,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        isExpanded: true,
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Título de la incidencia',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        counterText: '',
                      ),
                      maxLength: 100,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Introduce un título'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Describe el problema'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TypeAheadField<Map<String, dynamic>>(
                      controller: _addressController,
                      builder: (context, controller, focusNode) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Dirección (Manual o captura GPS)',
                            hintText: 'Ej: Calle Real, 5',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            prefixIcon: const Icon(Icons.map_outlined),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.my_location),
                              onPressed: _getCurrentLocation,
                              tooltip: 'Usar mi ubicación actual',
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Por favor, introduce una dirección o usa el GPS';
                            }
                            return null;
                          },
                        );
                      },
                      suggestionsCallback: (pattern) async {
                        if (pattern.length < 2) return [];
                        try {
                          String urlStr =
                              'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(pattern)}&format=json&limit=10&addressdetails=1&countrycodes=es&accept-language=es';

                          if (_currentPosition != null) {
                            final double lat = _currentPosition!.latitude;
                            final double lon = _currentPosition!.longitude;
                            const double delta = 0.05;
                            urlStr +=
                                '&viewbox=${lon - delta},${lat + delta},${lon + delta},${lat - delta}&bounded=0';
                          }

                          final url = Uri.parse(urlStr);
                          final response = await http.get(url, headers: {
                            'User-Agent': 'UrbiConnect_App_v1_Sergio'
                          });
                          if (response.statusCode == 200) {
                            final List data = json.decode(response.body);
                            // Filtrar resultados muy genéricos o poco útiles si hay otros mejores
                            final filtered = data.where((item) {
                              final type = item['type'] ?? '';
                              final cls = item['class'] ?? '';
                              // Excluir tipos administrativos muy amplios si no son lo que se busca
                              if (cls == 'boundary' && type == 'administrative')
                                return false;
                              return true;
                            }).toList();
                            return (filtered.isNotEmpty ? filtered : data)
                                .cast<Map<String, dynamic>>();
                          }
                        } catch (e) {
                          debugPrint("Suggestion error: $e");
                        }
                        return [];
                      },
                      itemBuilder: (context, suggestion) {
                        final addrMap =
                            suggestion['address'] as Map<String, dynamic>?;
                        String title = '';
                        if (addrMap != null) {
                          final street = addrMap['road'] ??
                              addrMap['pedestrian'] ??
                              addrMap['cycleway'] ??
                              '';
                          final houseNum = addrMap['house_number'] ?? '';
                          title = street;
                          if (houseNum.isNotEmpty) title += ' $houseNum';
                          if (title.isEmpty)
                            title = suggestion['display_name'] ?? '';
                        } else {
                          title = suggestion['display_name'] ?? '';
                        }

                        return ListTile(
                          leading:
                              const Icon(Icons.location_on, color: Colors.blue),
                          title: Text(title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(suggestion['display_name'] ?? '',
                              style: const TextStyle(fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        );
                      },
                      onSelected: (suggestion) {
                        final addrMap =
                            suggestion['address'] as Map<String, dynamic>?;
                        String cleanAddr = '';
                        if (addrMap != null) {
                          final street = addrMap['road'] ??
                              addrMap['pedestrian'] ??
                              addrMap['cycleway'] ??
                              '';
                          final houseNum = addrMap['house_number'] ?? '';
                          final city = addrMap['city'] ??
                              addrMap['town'] ??
                              addrMap['village'] ??
                              '';
                          final postcode = addrMap['postcode'] ?? '';

                          List<String> parts = [];
                          if (street.isNotEmpty)
                            parts.add(houseNum.isNotEmpty
                                ? '$street, $houseNum'
                                : street);
                          if (city.isNotEmpty) parts.add(city);
                          if (postcode.isNotEmpty) parts.add(postcode);
                          cleanAddr = parts.join(', ');
                        }

                        if (cleanAddr.isEmpty) {
                          cleanAddr = suggestion['display_name'] ?? '';
                        }

                        _addressController.text = cleanAddr;
                        setState(() {
                          _currentPosition = Position(
                            latitude: double.parse(suggestion['lat']),
                            longitude: double.parse(suggestion['lon']),
                            timestamp: DateTime.now(),
                            accuracy: 0,
                            altitude: 0,
                            heading: 0,
                            speed: 0,
                            speedAccuracy: 0,
                            altitudeAccuracy: 0,
                            headingAccuracy: 0,
                          );
                        });
                      },
                      emptyBuilder: (context) => const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No se encontraron direcciones'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Ubicación del incidente (GPS):',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _getCurrentLocation,
                      child: Container(
                        height: 60,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.my_location),
                            const SizedBox(width: 12),
                            const Text('Actualizar ubicación GPS'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Evidencia fotográfica (actuales y nuevas)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildImagePreview(),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Guardar cambios',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Imágenes actuales y nuevas:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Imágenes existentes
              ..._existingUrls.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                              image: NetworkImage(entry.value),
                              fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _existingUrls.removeAt(entry.key)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Imágenes nuevas
              ..._imageFiles.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: kIsWeb
                                ? MemoryImage(_webImages[entry.key])
                                : FileImage(File(entry.value.path))
                                    as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _imageFiles.removeAt(entry.key);
                            if (kIsWeb) _webImages.removeAt(entry.key);
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Botón añadir
              GestureDetector(
                onTap: () => _showImageSourceActionSheet(context),
                child: Container(
                  width: 100,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(Icons.add_a_photo_outlined,
                      color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería (múltiple)'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        if (pickedFiles.isNotEmpty) {
          for (var pickedFile in pickedFiles) {
            // Validación de tipo de archivo mejorada
            final String fileName = pickedFile.name.toLowerCase();
            final String? mimeType = pickedFile.mimeType?.toLowerCase();
            final List<String> allowedExtensions = [
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
              '.heic',
              '.heif',
              '.gif',
              '.svg',
              '.svgz',
              '.bmp',
              '.ico',
              '.tiff',
              '.tif',
              '.jfif',
              '.pjp',
              '.apng',
              '.xbm',
              '.jxl',
              '.jpe',
              '.pjpeg',
              '.avif'
            ];

            bool isImage = false;
            if (mimeType != null && mimeType.startsWith('image/')) {
              isImage = true;
            } else {
              for (var ext in allowedExtensions) {
                if (fileName.endsWith(ext)) {
                  isImage = true;
                  break;
                }
              }
            }

            if (!isImage) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Error: "$fileName" no es una imagen permitida.')),
                );
              }
              continue;
            }

            if (kIsWeb) {
              final bytes = await pickedFile.readAsBytes();
              setState(() {
                _webImages.add(bytes);
                _imageFiles.add(pickedFile);
              });
            } else {
              setState(() => _imageFiles.add(pickedFile));
            }
          }
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        if (pickedFile != null) {
          // Validación de tipo de archivo mejorada
          final String fileName = pickedFile.name.toLowerCase();
          final String? mimeType = pickedFile.mimeType?.toLowerCase();
          final List<String> allowedExtensions = [
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.heic',
            '.heif',
            '.gif',
            '.svg',
            '.svgz',
            '.bmp',
            '.ico',
            '.tiff',
            '.tif',
            '.jfif',
            '.pjp',
            '.apng',
            '.xbm',
            '.jxl',
            '.jpe',
            '.pjpeg',
            '.avif'
          ];

          bool isImage = false;
          if (mimeType != null && mimeType.startsWith('image/')) {
            isImage = true;
          } else {
            for (var ext in allowedExtensions) {
              if (fileName.endsWith(ext)) {
                isImage = true;
                break;
              }
            }
          }

          if (!isImage) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Error: "$fileName" no es una imagen permitida.')),
              );
            }
            return;
          }

          if (kIsWeb) {
            final bytes = await pickedFile.readAsBytes();
            setState(() {
              _webImages.add(bytes);
              _imageFiles.add(pickedFile);
            });
          } else {
            setState(() => _imageFiles.add(pickedFile));
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }
}
