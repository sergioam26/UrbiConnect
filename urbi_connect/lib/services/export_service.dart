import '../models/incident.dart';
import 'export_service_stub.dart'
    if (dart.library.html) 'export_service_web.dart'
    if (dart.library.io) 'export_service_mobile.dart' as impl;

class ExportService {
  static Future<void> exportIncidentsToCSV(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    return impl.ExportPlatformService.exportIncidentsToCSV(
        incidents, categoryNames, userEmails);
  }

  static Future<void> exportIncidentsToPDF(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    return impl.ExportPlatformService.exportIncidentsToPDF(
        incidents, categoryNames, userEmails);
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
    return impl.ExportPlatformService.exportStatsToPDF(
      citizens: citizens,
      staff: staff,
      admins: admins,
      pending: pending,
      inProcess: inProcess,
      resolved: resolved,
      categoryStats: categoryStats,
    );
  }
}
