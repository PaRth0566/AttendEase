import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Locally parses an attendance PDF and returns structured data.
///
/// Strategy: instead of trying to match entire rows left-to-right,
/// we anchor from the highly-specific DATE+TIME+TIME+STATUS pattern
/// (which is unique to attendance rows), then look BACKWARDS in the
/// text to find the Sr No. and Course Name.
class LocalPdfParser {
  static Future<Map<String, dynamic>> extractAttendanceFromPdf(
    Uint8List bytes,
  ) async {
    return _parse(bytes);
  }

  // ── Pattern: matches the RIGHT side of each attendance row ────────────
  //
  //   <Month Day, Year>  <H:MM:SS AM/PM>  <H:MM:SS AM/PM>  <P|A>
  //
  // Groups: (1) = full date string, (2) = start time, (3) = status (P or A)
  static final _dateTimeStatusRe = RegExp(
    r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\.?\s+\d{1,2},?\s+\d{4})'
    r'\s+(\d{1,2}:\d{2}(?::\d{2})?\s*[AP]M)' // Capture start time
    r'\s+\d{1,2}:\d{2}(?::\d{2})?\s*[AP]M'
    r'\s+([PA])\b',
    caseSensitive: false,
  );

  // ── Pattern: finds <number> <course name> at the end of a text chunk ──
  // Course name = letters and spaces only, at least 3 chars, ends with letter.
  static final _srNoCourseRe = RegExp(r'(\d+)\s+([A-Za-z][A-Za-z ]*[A-Za-z])');

  // ── Core parsing ──────────────────────────────────────────────────────

  static Map<String, dynamic> _parse(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);

    final records = <Map<String, String>>[];
    final stats = <String, Map<String, int>>{};
    final subjects = <String>{};
    String studentName = '';
    String course = '';
    String year = '';
    String semester = '';
    String startDate = '';
    String endDate = '';

    var text = '';

    try {
      final pageCount = document.pages.count;
      debugPrint('[Parser] $pageCount page(s)');

      // Step 1: Extract all text
      final buf = StringBuffer();
      for (int p = 0; p < pageCount; p++) {
        try {
          buf.write(extractor.extractText(startPageIndex: p, endPageIndex: p));
          buf.write(' ');
        } catch (e) {
          debugPrint('[Parser] extractText failed on page $p: $e');
        }
      }
      final rawText = buf.toString();

      // Collapse all whitespace to single spaces
      text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
      debugPrint('[Parser] Collapsed text length: ${text.length}');
      debugPrint('[Parser] First 500 chars: ${text.substring(0, text.length.clamp(0, 500))}');

      // ══════════════════════════════════════════════════════════════════
      // Step 2: Extract metadata using VALUE patterns (not label-based)
      // ══════════════════════════════════════════════════════════════════

      // Student name: Match between "Attendance Report" and "Student Name"
      final nameExact = RegExp(r'Attendance Report\s+(.+?)Student Name', caseSensitive: false).firstMatch(text);
      if (nameExact != null) {
        studentName = nameExact.group(1)!.trim();
      } else {
        // Fallback: consecutive UPPERCASE words
        final nameMatch = RegExp(r'\b([A-Z][A-Z]+(?:\s+[A-Z][A-Z]+)+)\b').firstMatch(text);
        if (nameMatch != null) studentName = nameMatch.group(1)!.trim();
      }

      // Academic year: YYYY-YYYY
      final yearMatch = RegExp(r'(\d{4}\s*-\s*\d{4})').firstMatch(text);
      if (yearMatch != null) year = yearMatch.group(1)!.replaceAll(' ', '');

      // Semester: "Semester IV" / "Semester 4" etc.
      final semMatch = RegExp(r'Semester\s+([IVX]+|\d+)', caseSensitive: false).firstMatch(text);
      if (semMatch != null) semester = 'Semester ${semMatch.group(1)!}';

      // Program: Match between "Academic Session" and "Program Name"
      final progExact = RegExp(r'Academic Session\s+(.+?)Program Name', caseSensitive: false).firstMatch(text);
      if (progExact != null) {
        course = progExact.group(1)!.trim();
      } else {
        // Fallback
        final progMatch = RegExp(
          r'((?:Bachelor|Master|B\.?\s*(?:Sc|Tech|E|A|Com)|M\.?\s*(?:Sc|Tech|E|A|Com))'
          r'(?:\w|\s)*?(?:\([^)]+\))?)',
          caseSensitive: false,
        ).firstMatch(text);
        if (progMatch != null) course = progMatch.group(1)!.trim();
      }

      // Start / End Date Extract: "From 01.11.2025 to 25.02.2026"
      final dateSpanMatch = RegExp(r'From\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})\s+to\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})', caseSensitive: false).firstMatch(text);
      if (dateSpanMatch != null) {
        // Convert to ISO 8601 (yyyy-mm-dd)
        startDate = '${dateSpanMatch.group(3)}-${dateSpanMatch.group(2)}-${dateSpanMatch.group(1)}';
        endDate = '${dateSpanMatch.group(6)}-${dateSpanMatch.group(5)}-${dateSpanMatch.group(4)}';
      }

      debugPrint('[Parser] Metadata: name="$studentName" year="$year" sem="$semester" course="$course" dates="$startDate to $endDate"');

      // ══════════════════════════════════════════════════════════════════
      // Step 3: Extract attendance records
      // Strategy: find each DATE+TIMES+STATUS pattern, then look at the
      // text BETWEEN the previous match's end and this match's start
      // to find the Sr No. + Course Name.
      // ══════════════════════════════════════════════════════════════════

      final allMatches = _dateTimeStatusRe.allMatches(text).toList();
      debugPrint('[Parser] Found ${allMatches.length} date+time+status matches');

      int lastEnd = 0;
      final seenKeys = <String>{};
      final dateCounts = <String, int>{};

      for (final m in allMatches) {
        final dateStr = m.group(1)!.trim();
        final timeStr = m.group(2)!.trim();
        final status = m.group(3)!.toUpperCase();
        if (status != 'P' && status != 'A') continue;

        // Text between previous match end and current match start
        final between = text.substring(lastEnd, m.start).trim();
        lastEnd = m.end;

        // Find ALL <number> <letter-text> patterns in the between text
        // and take the LAST one — that's our Sr No. + Course Name
        final srMatches = _srNoCourseRe.allMatches(between).toList();
        if (srMatches.isEmpty) {
          debugPrint('[Parser] No course found in between text: "${between.length > 100 ? between.substring(between.length - 100) : between}"');
          continue;
        }

        final lastSr = srMatches.last;
        final courseName = lastSr.group(2)!.trim();

        // Skip if course name looks like a header fragment
        if (courseName.length < 3) continue;
        if (RegExp(r'^(Sr|No|Course|Name|Date|Start|End|Time|Attendance|Page|of)$',
            caseSensitive: false).hasMatch(courseName)) {
          continue;
        }

        final isoDate = _toIsoDate(dateStr);
        if (isoDate == null) {
          debugPrint('[Parser] Bad date: "$dateStr"');
          continue;
        }

        // Deduplicate EXACT IDENTICAL rows (same subject, date, time)
        // This prevents double-counting if the PDF parser weirdly repeats a line.
        final key = '$courseName|$isoDate|$timeStr';
        if (seenKeys.contains(key)) continue;
        seenKeys.add(key);

        // Track how many lectures for this subject on this date have been seen.
        // If > 1, append an index (e.g., "2025-11-05_2").
        // This stops SQLite from overwriting the first lecture on the same day,
        // while also excluding it from calendar views (because length > 10).
        final dateCountKey = '$courseName|$isoDate';
        dateCounts[dateCountKey] = (dateCounts[dateCountKey] ?? 0) + 1;
        final count = dateCounts[dateCountKey]!;
        final finalDate = count > 1 ? '${isoDate}_$count' : isoDate;

        subjects.add(courseName);
        records.add({'date': finalDate, 'subject': courseName, 'status': status});
        stats.putIfAbsent(courseName, () => {'attended': 0, 'total': 0});
        stats[courseName]!['total'] = stats[courseName]!['total']! + 1;
        if (status == 'P') {
          stats[courseName]!['attended'] = stats[courseName]!['attended']! + 1;
        }
      }

      debugPrint('[Parser] Parsed ${records.length} records, ${subjects.length} subjects');
      if (subjects.isNotEmpty) {
        debugPrint('[Parser] Subjects: ${subjects.join(', ')}');
      }

    } finally {
      document.dispose();
    }

    if (records.isEmpty) {
      throw const FormatException(
        'No attendance records found in this PDF. '
        'Please make sure you are uploading the correct attendance report from the SAP Portal.',
      );
    }

    return {
      'name': studentName,
      'year': year,
      'semester': semester,
      'course': course,
      'startDate': startDate,
      'endDate': endDate,
      'subjects': subjects.toList(),
      'subjectStats': stats,
      'attendanceRecords': records,
    };
  }

  // ── Date normalisation ────────────────────────────────────────────────

  static const _monthMap = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'june': 6, 'july': 7, 'august': 8, 'september': 9,
    'october': 10, 'november': 11, 'december': 12,
  };

  static String? _toIsoDate(String raw) {
    final parts = raw.split(RegExp(r'[\s,]+'));
    if (parts.length >= 3) {
      final month = _monthMap[parts[0].toLowerCase()];
      final day = int.tryParse(parts[1].replaceAll(',', ''));
      final year = int.tryParse(parts.last);
      if (month != null && day != null && year != null) {
        return '${year.toString().padLeft(4, '0')}-'
            '${month.toString().padLeft(2, '0')}-'
            '${day.toString().padLeft(2, '0')}';
      }
    }
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }
    return null;
  }
}
