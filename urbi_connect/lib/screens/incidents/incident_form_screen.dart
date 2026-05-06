import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();

  String? _selectedCategoryId;
  List<Map<String, String>> _firestoreCategories = [];
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _webImages = [];
  Position? _currentPosition;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
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
        if (cats.isNotEmpty) {
          _selectedCategoryId = cats.first['id'];
        }
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
            // Validación de tipo de archivo mejorado
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
              setState(() {
                _imageFiles.add(pickedFile);
              });
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
          // Validación de tipo de archivo mejorado
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
            setState(() {
              _imageFiles.add(pickedFile);
            });
          }
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

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
      if (kIsWeb) _webImages.removeAt(index);
    });
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
                title: const Text('Galería (múltiple)'),
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
      setState(() => _isLoading = true);

      if (_currentPosition == null) {
        if (mounted) setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Por favor, captura la ubicación GPS o selecciona una dirección de las sugerencias.')),
        );
        return;
      }

      if (_imageFiles.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Por favor, añade al menos una foto de la incidencia.')),
        );
        return;
      }

      try {
        final List<String> imageUrls = [];

        for (int i = 0; i < _imageFiles.length; i++) {
          String? url;
          if (kIsWeb) {
            url = await _dbService.uploadImageWeb(_webImages[i]);
          } else {
            url = await _dbService.uploadImage(File(_imageFiles[i].path));
          }
          if (url != null) imageUrls.add(url);
        }

        if (imageUrls.isEmpty) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir las imágenes.')),
          );
          return;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        Incident incident = Incident(
          id: '',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: imageUrls.first, // Mantenemos el primero como principal
          imageUrls: imageUrls,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          createdAt: DateTime.now(),
          status: 'pendiente',
          userId: user.uid,
          categoryId: _selectedCategoryId ?? '',
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
                    if (_firestoreCategories.isEmpty)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        items: _firestoreCategories
                            .map((cat) => DropdownMenuItem(
                                  value: cat['id'],
                                  child: Text(cat['nombre']!,
                                      style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                      ),
                    if (_selectedCategoryId != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _firestoreCategories.firstWhere((c) =>
                                  c['id'] ==
                                  _selectedCategoryId)['descripcion'] ??
                              '',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título de la incidencia',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      maxLength: 100,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, introduce un título';
                        }
                        return null;
                      },
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
                            border: const OutlineInputBorder(),
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

                          // Si tenemos ubicación previa, sesgar resultados hacia esa zona
                          if (_currentPosition != null) {
                            final double lat = _currentPosition!.latitude;
                            final double lon = _currentPosition!.longitude;
                            // Crear un "viewbox" aproximado de ~5km alrededor
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Evidencias gráficas (mín. 1):',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            if (_imageFiles.isEmpty && _isLoading == false)
                              const Text(
                                'Obligatorio *',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _imageFiles.isEmpty
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _imageFiles.length + 1,
                              itemBuilder: (context, index) {
                                if (index == _imageFiles.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: GestureDetector(
                                      onTap: () =>
                                          _showImageSourceActionSheet(context),
                                      child: Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .dividerColor),
                                        ),
                                        child: Icon(Icons.add_a_photo_outlined,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color),
                                      ),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          image: DecorationImage(
                                            image: kIsWeb
                                                ? MemoryImage(_webImages[index])
                                                : FileImage(File(
                                                        _imageFiles[index]
                                                            .path))
                                                    as ImageProvider,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () => _removeImage(index),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle),
                                            child: const Icon(Icons.close,
                                                size: 16, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ubicación del incidente:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _getCurrentLocation,
                          child: Container(
                            height: 80,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _currentPosition != null
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _currentPosition != null
                                      ? Colors.green
                                      : Theme.of(context).dividerColor),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _currentPosition != null
                                      ? Icons.location_on
                                      : Icons.location_off,
                                  color: _currentPosition != null
                                      ? Colors.green
                                      : Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _currentPosition != null
                                      ? 'Ubicación capturada correctamente'
                                      : 'Pulsa para capturar ubicación GPS',
                                  style: TextStyle(
                                    color: _currentPosition != null
                                        ? Colors.green
                                        : Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color,
                                    fontWeight: _currentPosition != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
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
                        child: const Text('Enviar incidencia',
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
