import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One subject's line in the exported attendance report.
class ReportSubjectRow {
  const ReportSubjectRow({
    required this.name,
    required this.attended,
    required this.total,
    required this.requiredPercent,
  });

  final String name;

  /// Lectures marked present.
  final int attended;

  /// Conducted lectures counted over the report's period (present + absent).
  /// Zero means the period holds no conducted lecture for this subject at all.
  final int total;

  final double requiredPercent;

  double get percent => total == 0 ? 0 : (attended / total) * 100;

  /// Same test the on-screen report applies, so the PDF and the screen can never
  /// disagree about which subjects count as met.
  bool get isOnTrack => percent >= requiredPercent;

  /// Lectures that can still be missed while staying at or above
  /// [requiredPercent] — the mirror of [lecturesToAttend].
  int get lecturesToSpare {
    final reqFrac = requiredPercent / 100;
    if (total == 0 || !isOnTrack || reqFrac <= 0) return 0;
    final spare = ((attended / reqFrac) - total).floor();
    return spare < 0 ? 0 : spare;
  }

  /// Lectures that must be attended consecutively to climb back to
  /// [requiredPercent].
  int get lecturesToAttend {
    final reqFrac = requiredPercent / 100;
    if (total == 0 || isOnTrack || reqFrac >= 1) return 0;
    final needed = (((reqFrac * total) - attended) / (1 - reqFrac)).ceil();
    return needed < 0 ? 0 : needed;
  }
}

/// Everything the exported PDF needs beyond the subject rows.
class ReportMeta {
  const ReportMeta({
    required this.periodKind,
    required this.periodLabel,
    required this.semester,
    this.studentName = '',
    this.course = '',
    this.year = '',
    this.generatedAt,
  });

  /// What kind of period the figures cover — "Semester" or "Date range".
  final String periodKind;

  /// The period itself: "Semester 5", or "12 Jan – 3 Mar 2026".
  final String periodLabel;

  final int semester;
  final String studentName;
  final String course;
  final String year;

  /// Injectable so a test can assert on a fixed stamp.
  final DateTime? generatedAt;
}

/// The report's palette.
///
/// Deliberately narrow: one brand blue for structure, one green and one red that
/// carry pass/fail meaning and nothing else, and a grey ramp for the rest.
/// Decorative colour is most of what made the previous layout read as a web page
/// pasted into a document.
class _Ink {
  static final brand = PdfColor.fromInt(0xFF2563EB);

  static final good = PdfColor.fromInt(0xFF15803D);
  static final goodWash = PdfColor.fromInt(0xFFDCFCE7);
  static final bad = PdfColor.fromInt(0xFFB91C1C);
  static final badWash = PdfColor.fromInt(0xFFFEE2E2);

  static final ink = PdfColor.fromInt(0xFF0F172A);
  static final body = PdfColor.fromInt(0xFF334155);
  static final muted = PdfColor.fromInt(0xFF64748B);
  static final faint = PdfColor.fromInt(0xFF94A3B8);
  static final rule = PdfColor.fromInt(0xFFE2E8F0);
  static final ruleSoft = PdfColor.fromInt(0xFFF1F5F9);
  static final wash = PdfColor.fromInt(0xFFF8FAFC);
}

class _ReportFonts {
  const _ReportFonts(this.regular, this.bold);

  final pw.Font regular;
  final pw.Font bold;
}

/// The bundled Inter faces, loaded once per process.
///
/// Helvetica — the pdf package's default — is a large part of why an exported
/// document looks like a fax. Inter is already bundled for the app itself, so
/// matching the on-screen report costs only this load.
_ReportFonts? _cachedFonts;

Future<_ReportFonts> _loadFonts() async {
  final cached = _cachedFonts;
  if (cached != null) return cached;

  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
  );
  // SemiBold rather than Bold as the bold face: at 9pt body sizes Inter Bold
  // reads as shouting next to Regular, and every emphasised run in this document
  // is short (a name, a percentage, a caption).
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
  );
  return _cachedFonts = _ReportFonts(regular, bold);
}

/// The target percentage most subjects share, for the one headline comparison.
///
/// Every per-subject verdict still uses that subject's own target; this only
/// backs the sentence that summarises the whole report.
double dominantTarget(List<ReportSubjectRow> rows) {
  if (rows.isEmpty) return 75;
  final counts = <double, int>{};
  for (final r in rows) {
    counts[r.requiredPercent] = (counts[r.requiredPercent] ?? 0) + 1;
  }
  var best = rows.first.requiredPercent;
  var bestCount = 0;
  counts.forEach((value, count) {
    // Ties break upward: the stricter target is the safer thing to print.
    if (count > bestCount || (count == bestCount && value > best)) {
      best = value;
      bestCount = count;
    }
  });
  return best;
}

const double _pageMargin = 38;

/// A small uppercase, letter-spaced label over a hairline.
///
/// Sections are separated by type and space rather than by boxes — a bordered
/// card inside a bordered page inside a bordered table is what made the old
/// layout feel cramped.
pw.Widget _sectionLabel(String text) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8,
          color: _Ink.muted,
          letterSpacing: 1.4,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Container(height: 0.8, color: _Ink.rule),
    ],
  );
}

/// A caption above its value, for the identity strip under the title.
pw.Widget _metaPair(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 7,
          color: _Ink.faint,
          letterSpacing: 1.1,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9.5,
          color: _Ink.ink,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  );
}

/// A thin horizontal meter with a tick at the required percentage.
///
/// The tick is the point of it: a bare percentage says nothing about whether it
/// clears the bar, and this puts the bar literally on the page. Painted directly
/// rather than composed, because the pdf package has no fractional-width box and
/// the fill width is only known once the row's column width is resolved.
class _Meter extends pw.Widget {
  _Meter({
    required this.value,
    required this.target,
    required this.color,
    this.height = 5,
  });

  /// Fraction of 1.
  final double value;

  /// Fraction of 1. Drawn only when strictly inside the track.
  final double target;

  final PdfColor color;
  final double height;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    box = PdfRect.fromPoints(
      PdfPoint.zero,
      PdfPoint(constraints.maxWidth.isFinite ? constraints.maxWidth : 0, height),
    );
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);

    final b = box!;
    final r = b.height / 2;
    final v = value.clamp(0.0, 1.0);
    final t = target.clamp(0.0, 1.0);

    context.canvas
      ..drawRRect(b.left, b.bottom, b.width, b.height, r, r)
      ..setFillColor(_Ink.ruleSoft)
      ..fillPath();

    // A rounded fill narrower than its own corner radius paints as a lens rather
    // than a bar, so anything under one full cap is squared off instead.
    final fill = b.width * v;
    if (fill > 0.1) {
      if (fill >= b.height) {
        context.canvas.drawRRect(b.left, b.bottom, fill, b.height, r, r);
      } else {
        context.canvas.drawRect(b.left, b.bottom, fill, b.height);
      }
      context.canvas
        ..setFillColor(color)
        ..fillPath();
    }

    if (t > 0 && t < 1) {
      const w = 1.2;
      context.canvas
        ..drawRect(
          b.left + b.width * t - w / 2,
          b.bottom - 1.5,
          w,
          b.height + 3,
        )
        ..setFillColor(_Ink.ink)
        ..fillPath();
    }
  }
}

/// Renders the attendance report PDF.
///
/// [rows] is drawn in the order given. The report screen hands them over worst
/// percentage first, which is the order that makes the document useful read
/// top-down — the subjects that need action are on the first screenful.
Future<Uint8List> buildAttendanceReportPdf({
  required ReportMeta meta,
  required List<ReportSubjectRow> rows,
}) async {
  final fonts = await _loadFonts();
  final generatedAt = meta.generatedAt ?? DateTime.now();

  var attended = 0;
  var conducted = 0;
  for (final r in rows) {
    attended += r.attended;
    conducted += r.total;
  }
  final overall = conducted == 0 ? 0.0 : (attended / conducted) * 100;
  final target = dominantTarget(rows);
  final counted = rows.where((r) => r.total > 0).toList();
  final behind = counted.where((r) => !r.isOnTrack).toList();

  final doc = pw.Document(
    title: 'Attendance Report — ${meta.periodLabel}',
    author: meta.studentName.isEmpty ? 'AttendEase' : meta.studentName,
    creator: 'AttendEase',
    subject: 'Attendance summary for ${meta.periodLabel}',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold)
        .copyWith(
          defaultTextStyle: pw.TextStyle(
            font: fonts.regular,
            fontNormal: fonts.regular,
            fontBold: fonts.bold,
            fontSize: 9.5,
            color: _Ink.body,
            lineSpacing: 1.5,
          ),
        ),
  );

  final identity = _identityStrip(meta);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_pageMargin),
      // The masthead belongs to page 1 only — repeating a title block on every
      // page is what makes a two-page export feel like two documents. Page 2+
      // gets the slim running head instead.
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox.shrink()
          : _runningHead(meta),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by AttendEase from records on this device.',
              style: pw.TextStyle(fontSize: 7, color: _Ink.faint),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 7, color: _Ink.faint),
            ),
          ],
        ),
      ),
      build: (context) => [
        _masthead(meta, generatedAt),
        if (identity != null) ...[
          pw.SizedBox(height: 12),
          identity,
        ],
        pw.SizedBox(height: 18),
        _headline(
          overall: overall,
          target: target,
          attended: attended,
          conducted: conducted,
          subjectCount: counted.length,
          behindCount: behind.length,
        ),
        if (behind.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _actionNote(behind),
        ],
        pw.SizedBox(height: 22),
        _sectionLabel('Subject breakdown'),
        pw.SizedBox(height: 9),
        if (rows.isEmpty)
          pw.Text(
            'No subjects are recorded for this period.',
            style: pw.TextStyle(fontSize: 9, color: _Ink.muted),
          )
        else
          pw.Table(
            columnWidths: _breakdownColumns,
            children: [
              // repeat: true carries the header onto continuation pages, so a
              // row on page 2 still has columns you can name.
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _Ink.ink, width: 0.9),
                  ),
                ),
                children: [
                  _headCell('Subject'),
                  _headCell('Attended', align: pw.TextAlign.center),
                  _headCell('Actual', align: pw.TextAlign.center),
                  _headCell('Target', align: pw.TextAlign.center),
                  _headCell('Next step', align: pw.TextAlign.right),
                ],
              ),
              for (var i = 0; i < rows.length; i++)
                _breakdownRow(rows[i], shade: i.isOdd),
            ],
          ),
      ],
    ),
  );

  return doc.save();
}

/// A pill carrying a verdict. [ok] null means "no data to judge" — a subject the
/// period holds no conducted lecture for is not failing, and colouring it red
/// (which a bare 0% comparison would) is simply wrong.
pw.Widget _chip(String text, {required bool? ok, double fontSize = 7.5}) {
  final PdfColor fg = ok == null ? _Ink.muted : (ok ? _Ink.good : _Ink.bad);
  final PdfColor bg = ok == null
      ? _Ink.ruleSoft
      : (ok ? _Ink.goodWash : _Ink.badWash);

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
    decoration: pw.BoxDecoration(
      color: bg,
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        fontSize: fontSize,
        letterSpacing: 0.5,
        fontWeight: pw.FontWeight.bold,
        color: fg,
      ),
    ),
  );
}


/// One figure in the at-a-glance strip: number over caption.
///
/// Both sizes are deliberately restrained. At 17pt the widest value here
/// ("157 / 206") overran its quarter of the strip and wrapped into its own
/// caption; captions are kept to one word for the same reason.
pw.Widget _statItem(String value, String caption, {PdfColor? color}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        value,
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: color ?? _Ink.ink,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        caption.toUpperCase(),
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: 6.6,
          letterSpacing: 0.8,
          color: _Ink.muted,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  );
}

/// Splits [items] with hairline vertical rules instead of boxing each one.
pw.Widget _statStrip(List<pw.Widget> items) {
  final children = <pw.Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) {
      children.add(
        pw.Container(
          width: 0.8,
          height: 26,
          color: _Ink.rule,
          margin: const pw.EdgeInsets.symmetric(horizontal: 10),
        ),
      );
    }
    children.add(pw.Expanded(child: items[i]));
  }
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: children,
  );
}

/// The masthead: wordmark left, period right, one rule under both.
///
/// A full-bleed blue slab was the loudest thing on the old page and carried no
/// information; a rule does the same job of saying "this is the top" without
/// spending a quarter of the sheet on it.
pw.Widget _masthead(ReportMeta meta, DateTime generatedAt) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 3,
                    height: 15,
                    color: _Ink.brand,
                    margin: const pw.EdgeInsets.only(right: 7),
                  ),
                  pw.Text(
                    'AttendEase',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: _Ink.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Attendance Report',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: _Ink.muted,
                  letterSpacing: 1.6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                meta.periodLabel,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _Ink.ink,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                '${meta.periodKind}  ·  generated '
                '${DateFormat('d MMM yyyy').format(generatedAt)}',
                style: pw.TextStyle(fontSize: 8, color: _Ink.faint),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Container(height: 1.4, color: _Ink.ink),
    ],
  );
}

/// The identity strip. Rendered only for the fields the profile actually holds —
/// printing "Course: —" three times is worse than printing nothing.
pw.Widget? _identityStrip(ReportMeta meta) {
  final pairs = <pw.Widget>[
    if (meta.studentName.trim().isNotEmpty)
      _metaPair('Student', meta.studentName.trim()),
    if (meta.course.trim().isNotEmpty) _metaPair('Course', meta.course.trim()),
    if (meta.year.trim().isNotEmpty) _metaPair('Year', meta.year.trim()),
    _metaPair('Semester', '${meta.semester}'),
  ];
  if (pairs.length <= 1) return null;

  final spaced = <pw.Widget>[];
  for (var i = 0; i < pairs.length; i++) {
    if (i > 0) spaced.add(pw.SizedBox(width: 26));
    spaced.add(pairs[i]);
  }
  return pw.Row(children: spaced);
}

/// The headline: overall percentage, the meter it sits on, and the four figures
/// that qualify it.
pw.Widget _headline({
  required double overall,
  required double target,
  required int attended,
  required int conducted,
  required int subjectCount,
  required int behindCount,
}) {
  final ok = overall >= target;
  final accent = ok ? _Ink.good : _Ink.bad;
  final gap = overall - target;

  // Square corners, and the accent as a genuine left border rather than a
  // stretched child bar: the pdf package rejects a non-uniform border once a
  // radius is involved, and a stretch-aligned Row has no finite height to
  // stretch to inside a MultiPage. A flat-edged wash panel with a rule down its
  // left side is also the more editorial of the two looks.
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 16, 15),
    decoration: pw.BoxDecoration(
      color: _Ink.wash,
      border: pw.Border(left: pw.BorderSide(color: accent, width: 2.5)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'OVERALL ATTENDANCE',
                  style: pw.TextStyle(
                    fontSize: 7,
                    letterSpacing: 1.2,
                    color: _Ink.muted,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      conducted == 0 ? '—' : overall.toStringAsFixed(1),
                      style: pw.TextStyle(
                        fontSize: 34,
                        fontWeight: pw.FontWeight.bold,
                        color: conducted == 0 ? _Ink.faint : accent,
                        lineSpacing: 0,
                      ),
                    ),
                    if (conducted > 0)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4, left: 1),
                        child: pw.Text(
                          '%',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: _statStrip([
                  _statItem('$attended / $conducted', 'attended'),
                  _statItem('${target.toStringAsFixed(0)}%', 'target'),
                  _statItem(
                    '${subjectCount - behindCount} / $subjectCount',
                    'on track',
                  ),
                  _statItem(
                    '$behindCount',
                    'at risk',
                    color: behindCount > 0 ? _Ink.bad : _Ink.good,
                  ),
                ]),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 13),
        _Meter(
          value: conducted == 0 ? 0 : overall / 100,
          target: target / 100,
          color: accent,
          height: 6,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          conducted == 0
              ? 'No lectures were conducted in this period, so there is nothing to '
                    'measure yet.'
              : ok
              ? 'Clear of the ${target.toStringAsFixed(0)}% target by '
                    '${gap.toStringAsFixed(1)} points. The tick on the bar marks '
                    'the target.'
              : '${(-gap).toStringAsFixed(1)} points short of the '
                    '${target.toStringAsFixed(0)}% target. The tick on the bar '
                    'marks the target.',
          style: pw.TextStyle(fontSize: 8, color: _Ink.muted),
        ),
      ],
    ),
  );
}

/// Column widths for the breakdown table, shared by its header and its rows.
final _breakdownColumns = <int, pw.TableColumnWidth>{
  0: const pw.FlexColumnWidth(3.4), // subject + meter
  1: const pw.FlexColumnWidth(0.95), // attended / conducted
  2: const pw.FlexColumnWidth(0.8), // percentage
  3: const pw.FlexColumnWidth(0.7), // target
  4: const pw.FlexColumnWidth(2.15), // what to do next
};

pw.Widget _headCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(0, 0, 8, 6),
    child: pw.Text(
      text.toUpperCase(),
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 6.8,
        letterSpacing: 0.9,
        color: _Ink.muted,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

/// One subject's row.
///
/// The name carries its own meter, so the eye can rank ten subjects without
/// reading ten numbers — that ranking is the thing the old all-green table could
/// not express at all. The last column says what to *do*, which is the only
/// column a student actually acts on.
pw.TableRow _breakdownRow(ReportSubjectRow r, {required bool shade}) {
  final hasData = r.total > 0;
  final ok = hasData ? r.isOnTrack : null;
  final accent = !hasData ? _Ink.faint : (r.isOnTrack ? _Ink.good : _Ink.bad);

  pw.Widget cell(pw.Widget child, {bool right = false}) => pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(0, 8, right ? 0 : 8, 8),
    child: child,
  );

  final String action;
  if (!hasData) {
    action = 'No lectures held';
  } else if (r.isOnTrack) {
    final spare = r.lecturesToSpare;
    action = spare == 0 ? 'Miss none' : 'Can miss $spare';
  } else {
    final need = r.lecturesToAttend;
    action = need == 0 ? 'Attend all' : 'Attend $need in a row';
  }

  return pw.TableRow(
    decoration: shade ? pw.BoxDecoration(color: _Ink.wash) : null,
    verticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      cell(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              r.name,
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _Ink.ink,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            _Meter(
              value: hasData ? r.percent / 100 : 0,
              target: r.requiredPercent / 100,
              color: accent,
              height: 3.5,
            ),
          ],
        ),
      ),
      cell(
        pw.Text(
          hasData ? '${r.attended} / ${r.total}' : '—',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9,
            color: hasData ? _Ink.body : _Ink.faint,
          ),
        ),
      ),
      cell(
        pw.Text(
          hasData ? '${r.percent.toStringAsFixed(1)}%' : '—',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 10,
            color: accent,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      cell(
        pw.Text(
          '${r.requiredPercent.toStringAsFixed(0)}%',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 8.5, color: _Ink.muted),
        ),
      ),
      cell(
        right: true,
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Flexible(
              child: pw.Text(
                action,
                textAlign: pw.TextAlign.right,
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: 8,
                  color: hasData ? _Ink.body : _Ink.faint,
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            _chip(
              !hasData ? 'n/a' : (r.isOnTrack ? 'on track' : 'at risk'),
              ok: ok,
            ),
          ],
        ),
      ),
    ],
  );
}

/// The running head on continuation pages, so a printed page 2 still says what
/// it belongs to.
pw.Widget _runningHead(ReportMeta meta) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _Ink.rule, width: 0.8)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'AttendEase  ·  Attendance Report',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: _Ink.muted,
            letterSpacing: 0.6,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          meta.periodLabel,
          style: pw.TextStyle(fontSize: 7.5, color: _Ink.faint),
        ),
      ],
    ),
  );
}

/// Named subjects that need action, as a sentence rather than a table to re-read.
///
/// Capped: past a handful of names the line stops informing and starts wrapping,
/// and the table above already holds the full list.
pw.Widget _actionNote(List<ReportSubjectRow> behind) {
  const shown = 4;
  final names = behind.take(shown).map((r) => r.name).join(', ');
  final rest = behind.length - shown;

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(11, 9, 11, 10),
    decoration: pw.BoxDecoration(
      color: _Ink.badWash,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          behind.length == 1
              ? '1 SUBJECT BELOW TARGET'
              : '${behind.length} SUBJECTS BELOW TARGET',
          style: pw.TextStyle(
            fontSize: 7,
            letterSpacing: 1.1,
            color: _Ink.bad,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          rest > 0
              ? '$names, and $rest more — the “next step” column below says what '
                    'each one needs.'
              : '$names — the “next step” column below says what each one needs.',
          style: pw.TextStyle(fontSize: 8.5, color: _Ink.ink),
        ),
      ],
    ),
  );
}
