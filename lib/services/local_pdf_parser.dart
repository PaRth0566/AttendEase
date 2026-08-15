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
    return compute(_parse, bytes);
  }

  // ── Pattern: matches the RIGHT side of each attendance row ────────────
  //
  //   <Month Day, Year>  <H:MM:SS AM/PM>  <H:MM:SS AM/PM>  <P|A|AG|NU>
  //
  // Groups: (1) = full date string, (2) = start time, (3) = status
  static final _dateTimeStatusRe = RegExp(
    r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\.?\s+\d{1,2},?\s+\d{4})'
    r'\s+(\d{1,2}:\d{2}(?::\d{2})?\s*[AP]M)' // Capture start time
    r'\s+\d{1,2}:\d{2}(?::\d{2})?\s*[AP]M'
    r'\s+(P|A|AG|Attendance\s+Granted|NU|Cancelled|Not\s+Conducted)\b',
    caseSensitive: false,
  );

  // ── Course-name resolution ────────────────────────────────────────────
  //
  // A row's text chunk ends with "<Sr No> <Course Name>". The name is recovered
  // by splitting on Sr No candidates and keeping the longest tail that reads as
  // a clean name — see [_courseNameFrom].

  /// A candidate Sr No: a short digit run bounded by whitespace.
  ///
  /// The trailing lookahead is what makes a time column ineligible — the parts
  /// of "9:20:00 AM" are bounded by ':', never whitespace — so a clock can
  /// never be mistaken for a serial number.
  static final _srNoCandidateRe = RegExp(r'(?:^|\s)\d{1,4}(?=\s)');

  /// A whole course name.
  ///
  /// The leading '.' admits ".NET". Digits and '-' admit "Applied
  /// Mathematics-IV" and "Engineering Physics 1", which the previous
  /// letters-only class silently truncated — and, for two variants of one stem
  /// ("…-III" and "…-IV"), collapsed into a single merged subject with pooled
  /// attendance. ':' is deliberately absent so a stray time cannot validate.
  static final _courseNameRe = RegExp(
    r"^[A-Za-z.][A-Za-z0-9 .+#&()\-/,'’]*$",
  );

  /// Column-header and metadata-label phrases. Matched as whole-word phrases,
  /// not loose words: "Time" and "Name" are legitimate parts of subject names
  /// ("Real Time Systems"), so blacklisting them individually would drop real
  /// rows. Word-bounded rather than substring, so "Front**end Time** Series"
  /// does not trip the "end time" phrase.
  static final _headerPhraseRe = RegExp(
    r'\b(sr\s*no|course\s+name|start\s+time|end\s+time|lecture\s+date'
    r'|attendance\s+report|student\s+name|academic\s+session|program\s+name)\b',
    caseSensitive: false,
  );

  /// Tails that are a bare header cell rather than a subject.
  static const _headerWords = <String>{
    'sr', 'no', 'no.', 'course', 'name', 'date', 'start', 'end', 'time',
    'attendance', 'page', 'of', 'status', 'am', 'pm', 'lecture', 'total',
  };

  /// The longest a subject name is allowed to be. Real names run well under
  /// this; a run-on past it means the tail has swallowed surrounding banner
  /// text rather than isolating a name.
  static const _maxCourseNameLength = 80;

  /// Extracts the course name from the text chunk preceding a row's
  /// DATE·TIME·TIME·STATUS anchor.
  ///
  /// The chunk ends with `<Sr No> <Course Name>`, so every Sr No candidate
  /// splits it into a possible name. This takes the **longest** tail that still
  /// reads as a clean name.
  ///
  /// Longest-clean rather than rightmost is what handles both failure modes at
  /// once. A page-break banner ("… Page 3 of 12 Sr No. Course Name 45 DBMS")
  /// yields longer tails, but each trips a header phrase or the length ceiling,
  /// leaving "DBMS". A name with an interior digit ("Engineering Physics 1 Lab")
  /// yields a short rightmost tail ("Lab") and a longer clean one, and the
  /// longer wins — a rightmost rule would silently truncate it.
  ///
  /// Returns null when no candidate yields a plausible name, so the caller skips
  /// the row rather than inventing a subject.
  static String? _courseNameFrom(String between) {
    String? best;
    for (final srNo in _srNoCandidateRe.allMatches(between)) {
      final name = between.substring(srNo.end).trim();
      // "C#" and "AI" are real subjects, so the floor is 2. A single stray
      // letter left by a column split is not.
      if (name.length < 2 || name.length > _maxCourseNameLength) continue;
      if (!_courseNameRe.hasMatch(name)) continue;
      final lower = name.toLowerCase();
      if (_headerWords.contains(lower)) continue;
      if (_headerPhraseRe.hasMatch(name)) continue;
      if (best == null || name.length > best.length) best = name;
    }
    return best;
  }

  // ── Semester resolution ───────────────────────────────────────────────
  //
  // In a real SVKM report the semester is not a field of its own — it is the
  // tail of the Academic Session value, written label-first:
  //
  //     Academic Year & Academic Session    2026-2027, Semester V
  //     Program Name                        Bachelor of Science (Computer Science)
  //     Attendance Report Duration :        From 01.06.2026 to 06.08.2026
  //
  // So the reading that matters is "Semester" followed by its value. Both
  // orders are still accepted, because the value-first spelling ("V Semester")
  // does occur, but label-first is tried first since that is what the reports
  // in hand actually use.
  //
  // The one thing that must never happen is taking a digit out of the *middle*
  // of a longer number: "From 01.06.2026" is what previously produced
  // Semester 1. Both patterns below therefore require the captured value to be
  // bounded by a non-digit that is also not a date separator, so no part of
  // "01.06.2026" or "2026-2027" can be read as a semester.

  /// Canonical semester Roman numerals. An explicit table rather than a general
  /// Roman parser, so a token like "MIX" or "CD" cannot become a semester.
  static const _romanSemesters = <String, int>{
    'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6,
    'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12,
  };

  /// The highest semester treated as real, so a stray number cannot become one.
  static const _maxSemester = 12;

  // Both patterns bound the captured value the same way:
  //
  //   (?<!\d)          not continuing a longer number, so the "26" of
  //                    "2026-2027" cannot be picked up
  //   (?![\d.\-/])     not the head of a date or range, so the "01" of
  //                    "01.06.2026" cannot become Semester 1
  //
  // The date guard belongs only after the value — putting it before would reject
  // the separator the label pattern has just consumed, breaking "Sem-IV".

  /// "Semester V", "Semester: 5", "Sem-IV", "Semester 05".
  ///
  /// `\b` after the label is what keeps a subject called "Seminar" out — there
  /// is no word boundary inside "Seminar".
  static final _semesterLabelFirstRe = RegExp(
    r'\bSem(?:ester)?\b[\s.:\-]*(?<!\d)([IVX]{1,4}|\d{1,2})(?![\d.\-/])',
    caseSensitive: false,
  );

  /// "V Semester", "5th Sem" — the value ahead of the label.
  static final _semesterValueFirstRe = RegExp(
    r'(?<!\d)([IVX]{1,4}|\d{1,2})(?![\d.\-/])'
    r'(?:st|nd|rd|th)?[\s.:\-]*\bSem(?:ester)?\b',
    caseSensitive: false,
  );

  /// Reads the semester number out of a report's header text.
  ///
  /// Returns null when the report names no semester, so the caller can say so
  /// instead of silently importing one term's report on top of another.
  static int? extractSemesterNumber(String text) {
    for (final re in [_semesterLabelFirstRe, _semesterValueFirstRe]) {
      for (final match in re.allMatches(text)) {
        final value = semesterTokenValue(match.group(1)!);
        if (value != null) return value;
      }
    }
    return null;
  }

  /// The semester a single token denotes: "V" → 5, "05" → 5, "5," → 5.
  ///
  /// Null unless the *whole* token is a semester, which is what rejects a date,
  /// an academic session ("2026-2027") and a roll number.
  static int? semesterTokenValue(String raw) {
    final token = raw.replaceAll(
      RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'),
      '',
    );
    if (token.isEmpty) return null;
    if (RegExp(r'^\d{1,2}$').hasMatch(token)) {
      // Parsed whole, so a zero-padded "05" resolves to 5 instead of falling
      // through to a default the way the old `\b[1-8]\b` search did.
      final value = int.parse(token);
      return value >= 1 && value <= _maxSemester ? value : null;
    }
    return _romanSemesters[token.toUpperCase()];
  }

  /// Reads a semester out of a short label string such as "Semester V", "Sem 5"
  /// or a bare "5". For full header text use [extractSemesterNumber].
  static int? semesterNumberFrom(String raw) =>
      extractSemesterNumber(raw) ?? semesterTokenValue(raw);

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
    int? semesterNumber;
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
      debugPrint(
        '[Parser] First 500 chars: ${text.substring(0, text.length.clamp(0, 500))}',
      );

      // ══════════════════════════════════════════════════════════════════
      // Step 2: Extract metadata using VALUE patterns (not label-based)
      // ══════════════════════════════════════════════════════════════════

      // Student name: Match between "Attendance Report" and "Student Name"
      final nameExact = RegExp(
        r'Attendance Report\s+(.+?)Student Name',
        caseSensitive: false,
      ).firstMatch(text);
      if (nameExact != null) {
        studentName = nameExact.group(1)!.trim();
      } else {
        // Fallback: consecutive UPPERCASE words
        final nameMatch = RegExp(
          r'\b([A-Z][A-Z]+(?:\s+[A-Z][A-Z]+)+)\b',
        ).firstMatch(text);
        if (nameMatch != null) studentName = nameMatch.group(1)!.trim();
      }

      // Academic year: YYYY-YYYY
      final yearMatch = RegExp(r'(\d{4}\s*-\s*\d{4})').firstMatch(text);
      if (yearMatch != null) year = yearMatch.group(1)!.replaceAll(' ', '');

      semesterNumber = extractSemesterNumber(text);
      semester = semesterNumber == null ? '' : 'Semester $semesterNumber';

      // Program: Match between "Academic Session" and "Program Name"
      final progExact = RegExp(
        r'Academic Session\s+(.+?)Program Name',
        caseSensitive: false,
      ).firstMatch(text);
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
      final dateSpanMatch = RegExp(
        r'From\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})\s+to\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})',
        caseSensitive: false,
      ).firstMatch(text);
      if (dateSpanMatch != null) {
        // Convert to ISO 8601 (yyyy-mm-dd)
        startDate =
            '${dateSpanMatch.group(3)}-${dateSpanMatch.group(2)}-${dateSpanMatch.group(1)}';
        endDate =
            '${dateSpanMatch.group(6)}-${dateSpanMatch.group(5)}-${dateSpanMatch.group(4)}';
      }

      debugPrint(
        '[Parser] Metadata: name="$studentName" year="$year" sem="$semester" course="$course" dates="$startDate to $endDate"',
      );
      if (semesterNumber == null) {
        debugPrint(
          '[Parser] No semester in header — the import will keep the '
          'semester the user already has open.',
        );
      }

      // ══════════════════════════════════════════════════════════════════
      // Step 3: Extract attendance records
      // Strategy: find each DATE+TIMES+STATUS pattern, then look at the
      // text BETWEEN the previous match's end and this match's start
      // to find the Sr No. + Course Name.
      // ══════════════════════════════════════════════════════════════════

      final allMatches = _dateTimeStatusRe.allMatches(text).toList();
      debugPrint(
        '[Parser] Found ${allMatches.length} date+time+status matches',
      );

      int lastEnd = 0;
      final seenKeys = <String>{};
      final dateCounts = <String, int>{};

      for (final m in allMatches) {
        final dateStr = m.group(1)!.trim();
        final timeStr = m.group(2)!.trim();
        final rawStatus = m.group(3)!.toUpperCase();
        final status = rawStatus == 'AG' || rawStatus == 'ATTENDANCE GRANTED'
            ? 'P'
            : rawStatus == 'CANCELLED' || rawStatus == 'NOT CONDUCTED'
            ? 'NC'
            : rawStatus;
        if (!const {'P', 'A', 'NU', 'NC'}.contains(status)) continue;

        // Text between previous match end and current match start
        final between = text.substring(lastEnd, m.start).trim();
        lastEnd = m.end;

        // The name is the tail after the row's Sr No. Resolved right-to-left so
        // a page-break banner before the row cannot be absorbed into it.
        final courseName = _courseNameFrom(between);
        if (courseName == null) {
          debugPrint(
            '[Parser] No course found in between text: "${between.length > 100 ? between.substring(between.length - 100) : between}"',
          );
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
        records.add({
          'date': finalDate,
          'subject': courseName,
          'status': status,
          'time': timeStr,
        });
        // Pending and not-conducted records don't count toward P/A stats.
        if (status == 'P' || status == 'A') {
          stats.putIfAbsent(courseName, () => {'attended': 0, 'total': 0});
          stats[courseName]!['total'] = stats[courseName]!['total']! + 1;
          if (status == 'P') {
            stats[courseName]!['attended'] =
                stats[courseName]!['attended']! + 1;
          }
        }
      }

      debugPrint(
        '[Parser] Parsed ${records.length} records, ${subjects.length} subjects',
      );
      if (subjects.isNotEmpty) {
        debugPrint('[Parser] Subjects: ${subjects.join(', ')}');
      }
    } finally {
      document.dispose();
    }

    final inferredTimetable = inferWeeklyTimetable(records);

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
      // The resolved number alongside the display string. Every consumer needs
      // the number, and each re-deriving it from "Semester V" is how the roman
      // form came to be handled three different ways.
      'semesterNumber': semesterNumber,
      'course': course,
      'startDate': startDate,
      'endDate': endDate,
      'subjects': subjects.toList(),
      'subjectStats': stats,
      'attendanceRecords': records,
      'inferredTimetable': inferredTimetable,
    };
  }

  // ── Weekly timetable reconstruction ─────────────────────────────────────
  //
  // Reconstructs the CURRENT recurring weekly timetable from raw attendance
  // rows. This is deliberately robust to timetables that shift partway through
  // the semester (a class moving from a 9:20 slot to an 11:20 slot, subjects
  // added/dropped, exam weeks, etc.) — a naïve "merge every week" approach
  // produces bloated days with overlapping/duplicate lectures.
  //
  // For each weekday we keep only subjects that:
  //   1. genuinely recur — appear on ≥ 2 distinct dates of that weekday, and
  //   2. are current — appear within the most recent 3 dates of that weekday
  //      (drops stale early-semester slots that were later rescheduled).
  // The lecture count per day and the ordering are taken from each subject's
  // most recent occurrence, so the output mirrors the schedule as it stands
  // today. NU rows are included here on purpose: an NU still means a lecture
  // occurred. NC rows are excluded because no lecture took place.
  //
  // `records` items use the same shape produced by the parser:
  //   {'date': 'yyyy-MM-dd' (optionally with a '_n' suffix), 'subject': ...,
  //    'time': '9:20:01 AM', 'status': 'P'|'A'|'NU'|'NC'}
  static Map<String, List<String>> inferWeeklyTimetable(
    List<Map<String, String>> records,
  ) {
    final dayDates = <int, Set<String>>{};
    final daySubjectDateCount = <int, Map<String, Map<String, int>>>{};
    final daySubjectDateStart = <int, Map<String, Map<String, int>>>{};

    for (final r in records) {
      if (r['status'] == 'NC') continue;
      final subject = (r['subject'] ?? '').trim();
      if (subject.isEmpty) continue;
      final baseDate = (r['date'] ?? '').split('_').first;
      final dt = DateTime.tryParse(baseDate);
      if (dt == null) continue;
      final day = dt.weekday; // 1 = Monday … 7 = Sunday
      final startMin = _timeToMinutes(r['time'] ?? '');

      (dayDates[day] ??= <String>{}).add(baseDate);
      final dateCounts = (daySubjectDateCount[day] ??= {}).putIfAbsent(
        subject,
        () => <String, int>{},
      );
      dateCounts[baseDate] = (dateCounts[baseDate] ?? 0) + 1;
      final dateStarts = (daySubjectDateStart[day] ??= {}).putIfAbsent(
        subject,
        () => <String, int>{},
      );
      final existingStart = dateStarts[baseDate];
      if (existingStart == null || startMin < existingStart) {
        dateStarts[baseDate] = startMin;
      }
    }

    final inferredTimetable = <String, List<String>>{};
    for (int day = 1; day <= 7; day++) {
      final dates = (dayDates[day]?.toList() ?? <String>[])..sort();
      if (dates.isEmpty) continue;

      // The most recent (up to) 3 dates for this weekday define "recent".
      final recentDates = dates
          .sublist(dates.length <= 3 ? 0 : dates.length - 3)
          .toSet();

      final subjects = daySubjectDateCount[day] ?? const {};
      final slots = <({int start, String subject, int count})>[];
      for (final entry in subjects.entries) {
        final subject = entry.key;
        final subjectDates = entry.value.keys.toList()..sort();
        if (subjectDates.length < 2) continue; // one-off, not a real class
        if (!subjectDates.any(recentDates.contains)) continue; // stale slot
        final mostRecent = subjectDates.last;
        final count = entry.value[mostRecent]!.clamp(1, 8);
        final start = daySubjectDateStart[day]?[subject]?[mostRecent] ?? 0;
        slots.add((start: start, subject: subject, count: count));
      }
      if (slots.isEmpty) continue;

      slots.sort((a, b) => a.start.compareTo(b.start));
      final daySchedule = <String>[];
      for (final slot in slots) {
        for (int i = 0; i < slot.count; i++) {
          daySchedule.add(slot.subject);
        }
      }
      if (daySchedule.isNotEmpty) {
        inferredTimetable[day.toString()] = daySchedule;
      }
    }
    return inferredTimetable;
  }

  // ── Date normalisation ────────────────────────────────────────────────

  static const _monthMap = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'sept': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
    'january': 1,
    'february': 2,
    'march': 3,
    'april': 4,
    'june': 6,
    'july': 7,
    'august': 8,
    'september': 9,
    'october': 10,
    'november': 11,
    'december': 12,
  };

  static String? _toIsoDate(String raw) {
    final parts = raw.split(RegExp(r'[\s,]+'));
    if (parts.length >= 3) {
      // The row anchor admits a dotted abbreviation ("Sep. 15, 2025"), so the
      // trailing '.' is stripped before lookup — otherwise every row of such a
      // report silently fails to parse and the import reports zero records.
      final monthKey = parts[0].toLowerCase().replaceAll('.', '');
      final month = _monthMap[monthKey];
      final day = int.tryParse(parts[1].replaceAll(',', ''));
      final year = int.tryParse(parts.last);
      if (month != null && day != null && year != null) {
        // Range-check rather than trusting the values: DateTime(2025, 9, 45)
        // silently rolls over into October, which would file a lecture under a
        // date that never appeared in the report.
        if (day < 1 || day > 31 || year < 1900 || year > 2200) return null;
        final probe = DateTime(year, month, day);
        if (probe.year != year || probe.month != month || probe.day != day) {
          return null; // e.g. Feb 30
        }
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

  static int _timeToMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) return 0;
      final timeParts = parts[0].split(':');
      if (timeParts.isEmpty) return 0;
      int hours = int.parse(timeParts[0]);
      int minutes = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      if (parts.length > 1) {
        final ampm = parts[1].toUpperCase();
        if (ampm.contains('PM') && hours < 12) hours += 12;
        if (ampm.contains('AM') && hours == 12) hours = 0;
      }
      return hours * 60 + minutes;
    } catch (e) {
      return 0;
    }
  }
}
