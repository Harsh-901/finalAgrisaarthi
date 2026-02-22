import 'package:flutter/foundation.dart';
import '../../../core/services/farmer_service.dart';

/// Holds a fully-resolved field-value mapping ready for form injection.
class FormMapping {
  final String id;
  final String name;
  final String label;
  final String type;
  final String section;
  final dynamic value; // null = unmapped
  final List<Map<String, String>> options;

  const FormMapping({
    required this.id,
    required this.name,
    required this.label,
    required this.type,
    required this.section,
    required this.value,
    this.options = const [],
  });

  bool get isMapped => value != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
      };
}

/// Extracted DOM form field (raw, before mapping).
class DomField {
  final String id;
  final String name;
  final String label;
  final String type;
  final String section;
  final List<Map<String, String>> options;

  const DomField({
    required this.id,
    required this.name,
    required this.label,
    required this.type,
    required this.section,
    this.options = const [],
  });

  factory DomField.fromJson(Map<String, dynamic> json) {
    return DomField(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      section: json['section']?.toString() ?? '',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => {
                'value': (o['value'] ?? '').toString(),
                'text': (o['text'] ?? '').toString(),
              })
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FieldMapperService — Phase 3, Stage 1: Deterministic alias matching
// ─────────────────────────────────────────────────────────────────────────────

class FieldMapperService {
  /// Canonical alias table: maps farm-data keys → list of label aliases
  static const Map<String, List<String>> _aliases = {
    'name': [
      'name',
      'full name',
      'farmer name',
      'applicant name',
      'your name',
      'naam',
      'नाम',
      'नाव',
    ],
    'phone': [
      'phone',
      'mobile',
      'contact',
      'mobile number',
      'phone number',
      'contact number',
      'फोन',
      'मोबाइल',
    ],
    'state': [
      'state',
      'राज्य',
      'State',
    ],
    'district': [
      'district',
      'जिला',
      'जिल्हा',
      'District',
    ],
    'village': [
      'village',
      'gram',
      'panchayat',
      'गांव',
      'गाव',
      'Village',
    ],
    'land_size': [
      'land',
      'land size',
      'area',
      'land area',
      'acres',
      'hectares',
      'जमीन',
      'क्षेत्र',
    ],
    'crop_type': [
      'crop',
      'crop type',
      'primary crop',
      'main crop',
      'फसल',
      'पीक',
    ],
    'aadhaar': [
      'aadhaar',
      'aadhar',
      'adhaar',
      'uid',
      'unique id',
      'आधार',
    ],
    'pan': [
      'pan',
      'pan card',
      'pan number',
      'permanent account',
    ],
    'bank_account': [
      'bank account',
      'account number',
      'bank acc',
      'बैंक खाता',
    ],
    'ifsc': [
      'ifsc',
      'ifsc code',
      'bank code',
    ],
    'dob': [
      'date of birth',
      'dob',
      'birth date',
      'जन्म तिथि',
      'जन्मतारीख',
    ],
    'gender': [
      'gender',
      'sex',
      'लिंग',
    ],
    'pincode': [
      'pincode',
      'pin code',
      'zip',
      'postal code',
      'पिन कोड',
    ],
  };

  /// Maps a list of DomFields to FormMappings using farmer profile data.
  static List<FormMapping> map(
    List<DomField> fields,
    FarmerProfile profile,
  ) {
    final dataMap = _buildDataMap(profile);
    return fields.map((field) {
      final value = _findBestValue(field, dataMap);
      return FormMapping(
        id: field.id,
        name: field.name,
        label: field.label,
        type: field.type,
        section: field.section,
        value: value,
        options: field.options,
      );
    }).toList();
  }

  static Map<String, dynamic> _buildDataMap(FarmerProfile p) => {
        'name': p.fullName,
        'phone': p.phoneNumber,
        'state': p.state,
        'district': p.district,
        'village': p.village,
        'land_size': p.landSize.toString(),
        'crop_type': p.primaryCrop,
      };

  static dynamic _findBestValue(DomField field, Map<String, dynamic> data) {
    final needle =
        (field.label + ' ' + field.name + ' ' + field.id).toLowerCase().trim();

    String? bestKey;
    int bestScore = 0;

    data.forEach((dataKey, _) {
      final aliases = _aliases[dataKey] ?? [dataKey];
      for (final alias in aliases) {
        final a = alias.toLowerCase();
        int score = 0;
        if (needle == a) {
          score = 100;
        } else if (needle.contains(a) || a.contains(needle)) {
          score = 80;
        } else if (_subsequenceScore(needle, a) > 0) {
          score = _subsequenceScore(needle, a);
        }
        if (score > bestScore) {
          bestScore = score;
          bestKey = dataKey;
        }
      }
    });

    if (bestScore >= 60 && bestKey != null) {
      final raw = data[bestKey!];
      // For select fields, snap to closest option
      if (field.type == 'select' && field.options.isNotEmpty) {
        return _snapToOption(raw.toString(), field.options) ?? raw;
      }
      return raw;
    }
    return null;
  }

  static String? _snapToOption(
      String value, List<Map<String, String>> options) {
    final lv = value.toLowerCase();
    for (final opt in options) {
      final ov = (opt['value'] ?? '').toLowerCase();
      final ot = (opt['text'] ?? '').toLowerCase();
      if (ov == lv || ot == lv) return opt['value'];
    }
    for (final opt in options) {
      final ov = (opt['value'] ?? '').toLowerCase();
      final ot = (opt['text'] ?? '').toLowerCase();
      if (ov.contains(lv) ||
          ot.contains(lv) ||
          lv.contains(ov) ||
          lv.contains(ot)) {
        return opt['value'];
      }
    }
    return null;
  }

  static int _subsequenceScore(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    int ni = 0;
    for (var i = 0; i < haystack.length && ni < needle.length; i++) {
      if (haystack[i] == needle[ni]) ni++;
    }
    if (ni == needle.length) {
      return (ni / needle.length * 60).round();
    }
    return 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SmartFormMapper — Phases 3: orchestrates Stage 1 → Stage 2 → (Stage 3 stub)
// ─────────────────────────────────────────────────────────────────────────────

class SmartFormMapper {
  /// Run the full 3-stage mapping pipeline.
  ///
  /// Stage 1 — Deterministic alias match (FieldMapperService)
  /// Stage 2 — Regex snippet search on known data text
  /// Stage 3 — LLM fallback (stubbed; extend with on-device model)
  static List<FormMapping> map(
    List<DomField> fields,
    FarmerProfile profile,
  ) {
    // Stage 1
    List<FormMapping> result = FieldMapperService.map(fields, profile);

    // Stage 2: try regex snippet search for unmapped fields
    result = result.map((m) {
      if (m.isMapped) return m;
      final v = _snippetSearch(m, profile);
      if (v != null) {
        return FormMapping(
          id: m.id,
          name: m.name,
          label: m.label,
          type: m.type,
          section: m.section,
          value: v,
          options: m.options,
        );
      }
      return m;
    }).toList();

    // Stage 3: LLM (stubbed — add Gemma integration here)
    // For now we just leave remaining fields unmapped for human review.

    final mapped = result.where((m) => m.isMapped).length;
    debugPrint('SmartFormMapper: ${fields.length} fields → $mapped mapped');

    return result;
  }

  /// Stage 2: Targeted regex search using known farmer text patterns.
  static dynamic _snippetSearch(FormMapping m, FarmerProfile profile) {
    final label = m.label.toLowerCase();

    // Try each known data source with pattern matching
    final patterns = <String, dynamic>{
      'account|acc no|bank no': null, // Placeholder — extend with OCR data
      'pincode|pin code|zip': null,
      'aadhaar|aadhar|uid': null,
    };

    for (final entry in patterns.entries) {
      if (RegExp(entry.key).hasMatch(label) && entry.value != null) {
        return entry.value;
      }
    }

    return null;
  }
}
