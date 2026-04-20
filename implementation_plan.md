# Local (Non-AI) PDF Attendance Parsing

This plan replaces the high-cost, high-latency Gemini AI dependency with a local parsing engine. Processing will happen entirely on the user's device using pattern recognition and coordinate-based text extraction.

## User Review Required

> [!WARNING]
> **Fragility**: This parser assumes a consistent PDF layout. Unlike AI, it cannot "reason" about changes in table structure.
> [!IMPORTANT]
> **Library License**: This implementation uses `syncfusion_flutter_pdf`. If this is for a commercial product, you must have a Syncfusion license or be eligible for their Community License.

## Proposed Changes

### [Core] Dependencies

#### [MODIFY] [pubspec.yaml](file:///c:/Users/intel/AndroidStudioProjects/AttendEase/pubspec.yaml)
- Add `syncfusion_flutter_pdf: ^21.1.35`
- Remove (optional) backend-related logic.

### [Data] Local Parser Service

#### [NEW] [local_pdf_parser.dart](file:///c:/Users/intel/AndroidStudioProjects/AttendEase/lib/services/local_pdf_parser.dart)
- Implement `extractAttendanceFromPdf(Uint8List bytes)`:
    1. Load PDF document.
    2. Extract all text lines with their coordinates (X, Y).
    3. **Subject Identification**: Look for known subject names in the first few lines/columns.
    4. **Row Processing**: Group text strings by Y-coordinate to identify table rows.
    5. **Status Detection**: Look for 'P' or 'A' characters within columns that align with Subject headers.
    6. Returns a structured JSON object identical to the current backend format for backward compatibility.

### [UI] Dashboard Integration

#### [MODIFY] [refresh_pdf_screen.dart](file:///c:/Users/intel/AndroidStudioProjects/AttendEase/lib/screens/dashboard/refresh_pdf_screen.dart)
- Replace the `http.MultipartRequest` call with a direct call to `LocalPdfParser.parse()`.
- Update loading state text from "Analyzing with AI..." to "Analyzing PDF Locally...".

## Verification Plan

### Manual Verification
- Upload a standard attendance PDF and verify that subjects and status pins are correctly identified.
- Verify that statistics (overall %) match the PDF's internal stats.
- **Offline Test**: Turn off WiFi/Data and ensure the parsing logic still works perfectly.

### Automated Tests
- Create a `test/parser_test.dart` to run the parser against a known sample text output to verify the regrouping logic.
