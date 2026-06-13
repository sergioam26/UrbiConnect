import '../models/incident.dart';

class ExportPlatformService {
  static Future<void> exportIncidentsToCSV(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    throw UnimplementedError(
        'exportIncidentsToCSV no está implementado de forma nativa.');
  }

  static Future<void> exportIncidentsToPDF(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    throw UnimplementedError(
        'exportIncidentsToPDF no está implementado de forma nativa.');
  }

  static Future<void> exportStatsToPDF({
    required int citizens,
    required int staff,
    required int admins,
    required int pending,
    required int inProcess,
    required int resolved,
    required List<Map<String, dynamic>> categoryStats,
  }) async {
    throw UnimplementedError(
        'exportStatsToPDF no está implementado de forma nativa.');
  }
}
