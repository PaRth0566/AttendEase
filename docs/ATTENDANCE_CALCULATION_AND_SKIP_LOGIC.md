# AttendEase Attendance Calculation and Skip Logic: Technical Reference Manual

> **Document Classification:** Comprehensive Internal Technical Specification  
> **Target Audience:** Core Engine Developers, Maintainers, AI Pair Programmers  
> **Status:** Current Production Implementation (Verified from Code)  
> **Scope:** Attendance Data Models, Mathematical Formulas, Skip & Buffer Algorithms, Weekly Simulators, Isolation Boundaries, and UI Mapping.

---

## Table of Contents
1. [Complete Attendance System Overview](#1-complete-attendance-system-overview)
2. [Attendance Data Model](#2-attendance-data-model)
3. [Overall Attendance Calculation](#3-overall-attendance-calculation)
4. [Per-Subject Attendance Calculation](#4-per-subject-attendance-calculation)
5. [Overall Attendance Criteria](#5-overall-attendance-criteria)
6. [Per-Subject Attendance Criteria](#6-per-subject-attendance-criteria)
7. ["Days You Can Skip" vs "Lectures You Can Skip"](#7-days-you-can-skip-vs-lectures-you-can-skip)
8. [This-Week Skip Logic (The Weekly Simulator)](#8-this-week-skip-logic-the-weekly-simulator)
9. [Per-Subject Status / "What Should I Do?"](#9-per-subject-status--what-should-i-do)
10. [Criteria Dependency Matrix](#10-criteria-dependency-matrix)
11. [Safe to Skip Logic (Exhaustive Architectural Search)](#11-safe-to-skip-logic-exhaustive-architectural-search)
12. [Projection / Future Attendance Modeling](#12-projection--future-attendance-modeling)
13. [Timetable Dependency & Schedule Inference](#13-timetable-dependency--schedule-inference)
14. [Calendar Dependency & Heatmap Architecture](#14-calendar-dependency--heatmap-architecture)
15. [Degree College vs. Junior College Isolation](#15-degree-college-vs-junior-college-isolation)
16. [PDF Import & Report Sync Pipeline](#16-pdf-import--report-sync-pipeline)
17. [Database & Service Call Flow](#17-database--service-call-flow)
18. [Exact Mathematical Formulas Index](#18-exact-mathematical-formulas-index)
19. [Edge Cases & Boundary Handlers](#19-edge-cases--boundary-handlers)
20. [Rounding, Precision & Floating-Point Thresholds](#20-rounding-precision--floating-point-thresholds)
21. [UI to Logic Direct Mapping](#21-ui-to-logic-direct-mapping)
22. [Automated Test Suite Coverage & Verification Gaps](#22-automated-test-suite-coverage--verification-gaps)
23. [Source Code Inventory](#23-source-code-inventory)
24. [Fact vs. Inference Verification Log](#24-fact-vs-inference-verification-log)
25. [Final Executive Summary](#25-final-executive-summary)

---

## 1. Complete Attendance System Overview

AttendEase is a specialized college attendance tracking and projection mobile application built with Flutter, backed by a local-first SQLite embedded database (`attend_ease.db`) with bi-directional cloud synchronization to Google Cloud Firestore.

```
[Official College SAP PDF] ───> [LocalPdfParser]
                                        │
                                        ▼
[Manual In-App Markings]  ───> [AttendanceDao] <─── [CloudSyncService (Firestore)]
                                        │
                                        ▼
                              [CalculationUtils]
                                 ├── calculatePercentage()
                                 ├── computeSkipPlan()
                                 └── computeWeekSkipPlan()
                                        │
                                        ▼
                  ┌─────────────────────┼─────────────────────┐
                  ▼                     ▼                     ▼
          [DashboardScreen]     [CalendarScreen]     [ReportScreen]
```

### 1.1 Sources of Attendance Data
Attendance data enters the AttendEase calculation pipeline through four distinct ingress channels:
1. **SAP Portal Attendance PDF Reports:** The primary ingestion channel. Users export an official tabular attendance report from their college portal (typically SAP / SVKM / NMIMS / Mithibai / DJ Sanghvi portals) and upload it into the application.
2. **Manual In-App Markings:** Users can interactively mark individual lecture slots on the `CalendarScreen` (or Subject History on `SubjectDetailScreen`) as Present (`P`), Absent (`A`), or Not Updated (`NU`), or perform whole-day bulk markings.
3. **Seed Timetable Placeholders:** When a user configures subjects without an active timetable, synthetic seed slots (`day_of_week = 0`) are created in SQLite to allow attendance records to link via foreign keys.
4. **Cloud Restore/Sync:** When logging in on a new device, `CloudSyncService` pulls persisted attendance records and subject metadata from Firebase Firestore down into the local SQLite database.

### 1.2 Storage Architecture
All operational attendance calculations query SQLite tables directly via Data Access Objects (DAOs):
- `attendance_records`: Physical storage of every marked, unmarked, or cancelled lecture event.
- `subjects`: Metadata for academic courses, including semester/term affiliation and per-subject attendance target percentages.
- `timetable`: Scheduled weekly slots associating subjects with weekdays, times, and classrooms.
- `imported_report_dates`: High-water-mark tracking of distinct calendar dates covered by an uploaded PDF report.
- `SharedPreferences`: Key-value storage for user profile criteria, active semester/term selection, and academic start/end bounds.

### 1.3 Representation of Lectures & Attendance Statuses
Every lecture event evaluated by the calculation engine is represented by an integer status code or a 1-to-2 character string enum in SQLite:
- **`P` (Present / Attended):** The user was present. Increments attended count by 1 and conducted count by 1.
- **`A` (Absent):** The user was absent. Increments conducted count by 1. Attended count remains unchanged.
- **`NC` (Not Conducted / Cancelled):** The lecture was officially scheduled on the timetable or syllabus but was not held (professor absent, college event, holiday, or cancelled). **Excluded from both attended and conducted counts.** Never penalizes attendance percentage.
- **`NU` (Not Updated / Pending):** A lecture slot exists on the timetable or report, but attendance status has not yet been marked or confirmed. **Excluded from historical attendance calculations** (`WHERE a.status IN ('P', 'A')`), but accounted for in daily calendars and forward-looking weekly skip projections.
- **`AG` / `Attendance Granted`:** Normalized during PDF ingestion directly into `P`.

### 1.4 Cancellations, Replacements & Holidays
- **Cancelled Lectures:** Explicitly mapped to `NC`. During PDF import, `reconcileNotConductedLectures()` scans existing records; if a previously recorded slot is marked Not Conducted in the latest report, it is reconciled to `NC`.
- **Replacement / Extra Lectures:** When a professor takes an extra class on another weekday or replaces another subject's slot, the PDF parser registers the subject under that date. To handle multiple lectures of the same subject on the same day without primary key collision, AttendEase appends an occurrence suffix: `YYYY-MM-DD`, `YYYY-MM-DD_2`, `YYYY-MM-DD_3`.
- **Holidays & Sundays:** AttendEase treats Sundays as non-instructional days. Sundays never host inferred recurring lectures and trigger rollover in weekly skip planning. One-off holidays declared ad-hoc do not remove scheduled slots unless explicitly recorded as `NC` or deleted.

### 1.5 Responsible Core Classes and Files
| Module / Responsibility | File Path | Key Classes / Functions |
| :--- | :--- | :--- |
| **Mathematical Formulas & Projections** | `lib/utils/calculation_utils.dart` | `calculatePercentage`, `computeSkipPlan`, `computeWeekSkipPlan`, `_inferWeeklySchedule` |
| **Database Access & Aggregations** | `lib/database/attendance_dao.dart` | `getAttendanceStats`, `getAttendanceStatsForDateRange`, `getDaySchedule`, `reconcileNotConductedLectures` |
| **Database Schema & Constraints** | `lib/database/db_helper.dart` | `DatabaseHelper.onCreate`, table definitions, foreign keys |
| **PDF Parsing & Status Normalization** | `lib/services/local_pdf_parser.dart` | `LocalPdfParser.parseAttendancePdf`, `inferWeeklyTimetable` |
| **PDF Ingestion & Reconciliation** | `lib/services/pdf_attendance_import_service.dart` | `PdfAttendanceImportService.importPdfData` |
| **Cloud Sync & Data Pipeline** | `lib/services/attendance_report_sync_service.dart` | `AttendanceReportSyncService.syncFromPdf` |
| **Dashboard Presentation & Insights** | `lib/screens/dashboard/dashboard_screen.dart` | `_loadDashboardData`, `_getPredictiveInsight`, `_SubjectCard` |
| **Subject Analytics & Skip Dates** | `lib/screens/report/subject_detail_screen.dart` | `_loadHistory`, `_calculateSkippableDates`, `SubjectDetailScreen` |
| **Formal Report & PDF Export** | `lib/screens/report/report_screen.dart`<br>`lib/services/attendance_report_pdf.dart` | `_generateReport`, `ReportSubjectRow.lecturesToSpare`, `ReportSubjectRow.lecturesToAttend` |
| **Calendar Heatmap & Day Marking** | `lib/screens/calendar/calender_screen.dart` | `_fetchMonthData`, `_loadForDate`, `_markWholeDay`, `planDayMark` |

---

## 2. Attendance Data Model

AttendEase manages attendance across four SQLite tables defined in [`lib/database/db_helper.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/database/db_helper.dart).

```
 ┌───────────────────────────┐         ┌───────────────────────────┐
 │         subjects          │         │   imported_report_dates   │
 ├───────────────────────────┤         ├───────────────────────────┤
 │ id (PK INTEGER)           │         │ id (PK INTEGER)           │
 │ name (TEXT)               │         │ report_date (TEXT UNIQUE) │
 │ code (TEXT)               │         │ semester (INTEGER)        │
 │ semester (INTEGER)        │         │ imported_at (TEXT)        │
 │ required_percent (REAL)   │         └───────────────────────────┘
 │ created_at (TEXT)         │
 └─────────────┬─────────────┘
               │ 1
               │
               │ N
 ┌─────────────▼─────────────┐
 │         timetable         │
 ├───────────────────────────┤
 │ id (PK INTEGER)           │
 │ subject_id (FK INTEGER)   │
 │ day_of_week (INTEGER 0-6) │
 │ start_time (TEXT)         │
 │ end_time (TEXT)           │
 │ room (TEXT)               │
 │ is_active (INTEGER 0/1)   │
 └─────────────┬─────────────┘
               │ 1
               │
               │ N
 ┌─────────────▼─────────────┐
 │    attendance_records     │
 ├───────────────────────────┤
 │ id (PK INTEGER)           │
 │ timetable_id (FK INTEGER) │
 │ date (TEXT)               │ ◄── "YYYY-MM-DD" or "YYYY-MM-DD_2"
 │ status (TEXT)             │ ◄── CHECK (status IN ('P','A','NU','NC'))
 │ original_status (TEXT)    │ ◄── Original PDF baseline ('P','A','NU','NC')
 │ source (TEXT)             │ ◄── 'pdf', 'manual', 'sync'
 │ created_at (TEXT)         │
 │ updated_at (TEXT)         │
 └───────────────────────────┘
```

### 2.1 Table: `subjects`
Stores course information for each academic period.

- **FIELD:** `id`  
  **TYPE:** `INTEGER PRIMARY KEY AUTOINCREMENT`  
  **PURPOSE:** Unique database identifier for the course.  
  **EXAMPLE:** `4`  
  **USED BY:** `TimetableDao`, `AttendanceDao`, `SubjectDetailScreen`, `DashboardScreen`.  
  **IMPORTANT BEHAVIOR:** Cascades deletion to `timetable` and `attendance_records`.

- **FIELD:** `name`  
  **TYPE:** `TEXT NOT NULL`  
  **PURPOSE:** Full course title.  
  **EXAMPLE:** `"Operating Systems With Linux"`  
  **USED BY:** UI cards, PDF reports, duplicate matching.  
  **IMPORTANT BEHAVIOR:** Cleaned and matched case-insensitively during PDF imports.

- **FIELD:** `code`  
  **TYPE:** `TEXT`  
  **PURPOSE:** Course code (optional).  
  **EXAMPLE:** `"CS501"`  
  **USED BY:** Profile and subject management.

- **FIELD:** `semester`  
  **TYPE:** `INTEGER NOT NULL`  
  **PURPOSE:** Academic period partition key.  
  **EXAMPLE:** `5` (for Degree Semester 5), `11` (for Junior College FYJC), `12` (for Junior College SYJC).  
  **USED BY:** All queries filtering by active academic period (`WHERE s.semester = ?`).  
  **IMPORTANT BEHAVIOR:** Isolates Degree College semesters (1–8) from Junior College terms (11, 12).

- **FIELD:** `required_percent`  
  **TYPE:** `REAL NOT NULL DEFAULT 75.0`  
  **PURPOSE:** The specific attendance threshold required for this course.  
  **EXAMPLE:** `70.0`  
  **USED BY:** `computeSkipPlan()`, `computeWeekSkipPlan()`, `SubjectDetailScreen`, `_SubjectCard`.  
  **IMPORTANT BEHAVIOR:** Initialized from SharedPreferences `subject_required_attendance` (default `70.0`), but customizable per subject.

- **FIELD:** `created_at`  
  **TYPE:** `TEXT DEFAULT CURRENT_TIMESTAMP`  
  **PURPOSE:** Audit timestamp.

---

### 2.2 Table: `timetable`
Represents scheduled recurring lecture slots or synthetic seed slots.

- **FIELD:** `id`  
  **TYPE:** `INTEGER PRIMARY KEY AUTOINCREMENT`  
  **PURPOSE:** Unique identifier for a timetable slot.  
  **USED BY:** Foreign key in `attendance_records.timetable_id`.

- **FIELD:** `subject_id`  
  **TYPE:** `INTEGER NOT NULL`  
  **PURPOSE:** References `subjects(id)` with `ON DELETE CASCADE`.

- **FIELD:** `day_of_week`  
  **TYPE:** `INTEGER NOT NULL`  
  **PURPOSE:** Day of recurrence: `1` (Monday) to `6` (Saturday), `7` (Sunday).  
  **SPECIAL VALUE:** `0` denotes a **Seed Entry** created programmatically via `TimetableDao.ensureSeedEntry(subjectId)`. Seed entries provide a permanent `timetable_id` anchor so attendance records can exist even without a weekly schedule.

- **FIELD:** `start_time` / `end_time`  
  **TYPE:** `TEXT`  
  **EXAMPLE:** `"09:20 AM"`, `"10:20 AM"`

- **FIELD:** `room`  
  **TYPE:** `TEXT`  
  **EXAMPLE:** `"Lab 3"`, `"Room 402"`

- **FIELD:** `is_active`  
  **TYPE:** `INTEGER DEFAULT 1`  
  **PURPOSE:** Soft-delete or inactive flag.

---

### 2.3 Table: `attendance_records`
Physical log of every recorded lecture event.

- **FIELD:** `id`  
  **TYPE:** `INTEGER PRIMARY KEY AUTOINCREMENT`  
  **PURPOSE:** Primary key.

- **FIELD:** `timetable_id`  
  **TYPE:** `INTEGER NOT NULL`  
  **PURPOSE:** Foreign key linking to `timetable(id)` with `ON DELETE CASCADE`.

- **FIELD:** `date`  
  **TYPE:** `TEXT NOT NULL`  
  **PURPOSE:** Calendar date of the lecture.  
  **FORMAT:** Standard ISO `YYYY-MM-DD` (e.g. `"2026-07-20"`).  
  **OCCURRENCE SUFFIX:** For multiple lectures of the same subject on the same day: `"2026-07-20_2"`, `"2026-07-20_3"`.  
  **PSEUDO-DATE GUARD:** Synthetic padding records prefixed with `"pad_"` are rejected by `AttendanceDao.getAttendanceStats()` (`WHERE a.date NOT LIKE 'pad_%'`).

- **FIELD:** `status`  
  **TYPE:** `TEXT NOT NULL`  
  **CONSTRAINT:** `CHECK(status IN ('P', 'A', 'NU', 'NC'))`  
  **PURPOSE:** Current effective attendance status.

- **FIELD:** `original_status`  
  **TYPE:** `TEXT`  
  **PURPOSE:** Preserves baseline status from the official PDF import (`'P'`, `'A'`, `'NU'`, `'NC'`).  
  **IMPORTANT BEHAVIOR:** When a user toggles attendance manually on the Calendar or Subject screen, `original_status` enables the system to know whether reverting to `NU` is legally permitted (only if original baseline was `NU`).

- **FIELD:** `source`  
  **TYPE:** `TEXT DEFAULT 'manual'`  
  **PURPOSE:** Audit provenance (`'pdf'`, `'manual'`, `'sync'`).

- **FIELD:** `created_at` / `updated_at`  
  **TYPE:** `TEXT DEFAULT CURRENT_TIMESTAMP`

---

### 2.4 Table: `imported_report_dates`
Maintains a registry of calendar dates covered by imported PDF reports.

- **FIELD:** `report_date`  
  **TYPE:** `TEXT NOT NULL UNIQUE`  
  **PURPOSE:** Calendar date (`YYYY-MM-DD`) confirmed to be present in an uploaded SAP PDF.  
  **IMPORTANT BEHAVIOR:** Used by `CalendarScreen.getDaySchedule()` to distinguish between an unrecorded class day and a day not covered by the official report.

- **FIELD:** `semester`  
  **TYPE:** `INTEGER NOT NULL`  
  **PURPOSE:** Scopes the import coverage to the specific academic period.

- **FIELD:** `imported_at`  
  **TYPE:** `TEXT DEFAULT CURRENT_TIMESTAMP`

---

### 2.5 SharedPreferences Preference Keys
| Key | Type | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `overall_required_attendance` | `double` | `75.0` | Global overall attendance target percentage. |
| `subject_required_attendance` | `double` | `70.0` | Default threshold assigned to newly created subjects. |
| `college_type` | `String` | `'degree'` | Active college section: `'degree'` or `'junior'`. |
| `semester` | `int` | `1` | Active period numeric ID (`1..8` for Degree; `11` or `12` for Junior). |
| `term` | `String` | `null` | Active Junior College term string: `'FYJC'` or `'SYJC'`. |
| `semester_start_$sem` | `String` | `null` | Degree semester start date (`YYYY-MM-DD`). |
| `semester_end_$sem` | `String` | `null` | Degree semester end date (`YYYY-MM-DD`). |
| `junior_term_start_$term` | `String` | `null` | Junior College term start date (`YYYY-MM-DD`). |
| `junior_term_end_$term` | `String` | `null` | Junior College term end date (`YYYY-MM-DD`). |

---

## 3. Overall Attendance Calculation

### 3.1 The Canonical Mathematical Formula
Overall attendance in AttendEase is **not** an arithmetic average of subject percentages. It is a **macro lecture-count-weighted aggregate** across all subjects belonging to the active semester or term:

$$\text{Overall Attendance \%} = \begin{cases} 0.0 & \text{if } \sum_{i=1}^N \text{Total}_i = 0 \\ \left( \frac{\sum_{i=1}^N \text{Attended}_i}{\sum_{i=1}^N \text{Total}_i} \right) \times 100 & \text{if } \sum_{i=1}^N \text{Total}_i > 0 \end{cases}$$

Where:
- $\text{Attended}_i = \text{Count of records for subject } i \text{ with status } \mathbf{P}$
- $\text{Total}_i = \text{Count of records for subject } i \text{ with status } \mathbf{P} \text{ or } \mathbf{A}$
- $N = \text{Total number of subjects in the active semester/term}$

```
                  Total Attended Lectures (Σ P)
Overall %  =  ───────────────────────────────────────  ×  100
              Total Conducted Lectures (Σ P  +  Σ A)
```

### 3.2 SQL Implementation in `AttendanceDao`
From [`lib/database/attendance_dao.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/database/attendance_dao.dart#L18-L45):
```sql
SELECT 
  s.id as subject_id,
  s.name as subject_name,
  s.required_percent,
  COUNT(CASE WHEN a.status = 'P' THEN 1 END) as attended,
  COUNT(CASE WHEN a.status IN ('P', 'A') THEN 1 END) as total
FROM subjects s
JOIN timetable t ON s.id = t.subject_id
JOIN attendance_records a ON t.id = a.timetable_id
WHERE s.semester = ? AND a.date NOT LIKE 'pad_%'
GROUP BY s.id
```

### 3.3 Status Inclusions and Exclusions
- **Counted in Numerator ($\text{Attended}$):** `'P'` only.
- **Counted in Denominator ($\text{Conducted}$):** `'P'` and `'A'`.
- **Completely Excluded from Both Numerator & Denominator:**
  - `'NC'` (Not Conducted): Zero penalty. Does not exist in conducted count.
  - `'NU'` (Not Updated): Pending status. Excluded by SQL filter `status IN ('P', 'A')`.
  - `'pad_%'` (Padding dates): Excluded by SQL filter `a.date NOT LIKE 'pad_%'`.
  - Future timetable slots without attendance records: Excluded.

### 3.4 Numerical Verification Examples

#### Example 1: Standard Balanced Term
- Subject 1: $P = 18, A = 2, NC = 3$ (Conducted = 20)
- Subject 2: $P = 12, A = 4, NC = 1$ (Conducted = 16)
- Subject 3: $P = 30, A = 0, NC = 0$ (Conducted = 30)
- **Aggregates:**
  - $\sum P = 18 + 12 + 30 = 60$
  - $\sum (P + A) = 20 + 16 + 30 = 66$
  - $\text{NC} = 3 + 1 + 0 = 4$ (Ignored)
- **Calculation:**
  $$\text{Overall \%} = \frac{60}{66} \times 100 = 90.9090...\% \xrightarrow{\text{Dashboard (1 dec)}} \mathbf{90.9\%}$$

#### Example 2: Unequal Course Weights (Why Macro Weighting Matters)
- Course A (Heavy lab): $P = 40, A = 10 \implies 80.0\%$ (Conducted = 50)
- Course B (Light elective): $P = 5, A = 5 \implies 50.0\%$ (Conducted = 10)
- **Unweighted Subject Mean (Incorrect):** $(80.0 + 50.0) / 2 = 65.0\%$
- **Actual AttendEase Calculation (Confirmed from Code):**
  - $\sum P = 40 + 5 = 45$
  - $\sum \text{Conducted} = 50 + 10 = 60$
  - $\text{Overall \%} = \frac{45}{60} \times 100 = \mathbf{75.0\%}$

#### Example 3: Clean Start / All Cancelled (Zero Boundary)
- Course 1: $P = 0, A = 0, NC = 5, NU = 4$
- Course 2: $P = 0, A = 0, NC = 2, NU = 1$
- **Aggregates:**
  - $\sum P = 0$
  - $\sum \text{Conducted} = 0$
- **Calculation:**
  $$\sum \text{Conducted} == 0 \implies \mathbf{0.0\%}$$

---

## 4. Per-Subject Attendance Calculation

### 4.1 Subject Formula
For any single course $S$:

$$\text{Subject Attendance \%} = \begin{cases} 0.0 & \text{if } \text{Total} = 0 \\ \left( \frac{\text{Attended}}{\text{Total}} \right) \times 100 & \text{if } \text{Total} > 0 \end{cases}$$

Where:
- $\text{Attended} = \text{Count of records with } \text{status} = \mathbf{P}$
- $\text{Total} = \text{Count of records with } \text{status} \in \{\mathbf{P}, \mathbf{A}\}$

From [`lib/utils/calculation_utils.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/utils/calculation_utils.dart#L1-L4):
```dart
double calculatePercentage(int attended, int total) {
  if (total == 0) return 0.0;
  return (attended / total) * 100;
}
```

### 4.2 Handling of NU, NC, and Scope Filtering
In [`lib/screens/report/subject_detail_screen.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/screens/report/subject_detail_screen.dart#L138-L148):
```dart
int attendedCount = 0;
int totalCount = 0;
for (var record in records) {
  final status = record['status'];
  if (status == 'NU' || status == 'NC') continue;
  totalCount++;
  if (status == 'P') {
    attendedCount++;
  }
}
```
- **Boundaries:** Percentage cannot exceed $100.0\%$ or drop below $0.0\%$.
- **Custom Date Ranges:** In `ReportScreen`, if a custom date range is picked, the counts are restricted via SQL:
  `WHERE a.date >= ? AND a.date <= ?`.

---

## 5. Overall Attendance Criteria

### 5.1 Storage and Defaults
- **Storage Location:** `SharedPreferences`.
- **Key:** `'overall_required_attendance'`.
- **Data Type:** `double`.
- **System Default:** `75.0` (read as `prefs.getDouble('overall_required_attendance') ?? 75.0`).
- **Configurability:** Fully configurable by the user in `ProfileScreen` via numeric input and setup dialogs.

### 5.2 Scope & Usage Across Screens
- **Global Application:** The overall requirement is a global preference across the active profile. It does not automatically vary by semester number or term.
- **Used by Dashboard:**
  - Circular progress gauge: Ring turns `c.success` (green) if $\text{Overall \%} \ge \text{Target}$, else `c.danger` (red).
  - Target caption: Renders `"Target: 75.0%"`.
  - Predictive insight footer: Feeds into `_getPredictiveInsight(_totalAttendedOverall, _totalLecturesOverall, _requiredTarget)`.
  - Weekly skip plan: Enforces the overall ceiling during the Monday–Sunday simulation walk.
- **Used by Analytics & Reports:**
  - Evaluates overall health in `_ReportScreenState` and determines status banners in exported PDF reports.

---

## 6. Per-Subject Attendance Criteria

### 6.1 Architecture & Granularity
AttendEase features **independent per-subject attendance criteria**. Each course maintains its own explicit target percentage.

- **Storage Location:** SQLite column `subjects.required_percent` (`REAL NOT NULL DEFAULT 75.0`).
- **Default Assignment:** When a subject is added or imported from a PDF without an explicit threshold, it defaults to the value stored in `SharedPreferences` under `'subject_required_attendance'` (default `70.0`).
- **Independence:** A subject can fall below its required percentage while overall attendance remains well above threshold.

### 6.2 Code Proof of Independent Evaluation
From [`lib/utils/calculation_utils.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/utils/calculation_utils.dart#L371-L385):
```dart
int? firstBreach(List<int> lectures) {
  // 1. Check every individual subject against its OWN required_percent
  for (final sid in lectures) {
    final t = total[sid] ?? 0;
    if (t == 0) continue;
    final req = subjectRequired[sid] ?? overallRequired;
    if ((attended[sid] ?? 0) / t * 100 < req - 1e-9) return sid; // Subject breach
  }
  // 2. Check the MACRO overall percentage against overallRequired
  var a = 0, t = 0;
  total.forEach((sid, tt) {
    a += attended[sid] ?? 0;
    t += tt;
  });
  if (t != 0 && (a / t) * 100 < overallRequired - 1e-9) return -1; // Overall breach
  return null;
}
```

---

## 7. "Days You Can Skip" vs. "Lectures You Can Skip"

A critical distinction exists in AttendEase between **lecture-level skip buffers** and **calendar-day skip projections**.

### 7.1 Single-Subject Lecture Skip Buffer
The number of future lectures of course $S$ that can be missed consecutively while staying $\ge \text{requiredPercent}$ is:

$$\text{maxSkips} = \left\lfloor \frac{\text{Attended}}{\text{reqFrac}} - \text{Total} \right\rfloor \quad \text{where } \text{reqFrac} = \frac{\text{requiredPercent}}{100}$$

#### Derivation:
$$\frac{\text{Attended}}{\text{Total} + x} \ge \text{reqFrac} \implies \text{Total} + x \le \frac{\text{Attended}}{\text{reqFrac}} \implies x \le \frac{\text{Attended}}{\text{reqFrac}} - \text{Total}$$

- If $\text{Current \%} < \text{Required \%}$: $\text{maxSkips} = 0$.
- If $\text{maxSkips} \le 0$: User is on track, but cannot skip the immediate next lecture.

### 7.2 Converting Single-Subject Lectures into Calendar Dates
In `computeSkipPlan()`:
1. The subject's historical weekly footprint is derived from `attendance_records` (filtering for days with $\ge 2$ occurrences within the last 21 days of history).
2. The engine projects forward day-by-day from tomorrow (`today + 1 day`) up to a 70-day horizon.
3. When the cursor lands on an active weekday for this subject, it deducts that day's lecture count from `maxSkips` and records the calendar date in `SkipPlan.dates`.
4. If a day has 2 scheduled lectures and the budget is $\ge 2$, both are assigned to that calendar date: `countPerDate[date] = 2`.

---

## 8. This-Week Skip Logic (The Weekly Simulator)

The most advanced algorithm in AttendEase is `computeWeekSkipPlan()` located in [`lib/utils/calculation_utils.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/utils/calculation_utils.dart#L320-L487). It powers the Monday–Sunday interactive strip on the Dashboard.

```
       [Today: Wednesday]
Mon    Tue    Wed    Thu    Fri    Sat    Sun
[PAST] [PAST] [SETTLED] [SKIP] [UNSAFE] [SKIP] [NO CLASS]
                         │       │
                         │       └─ Breaks DBMS (drops to 68.2%)
                         └─ Safe to miss all 3 lectures
```

### 8.1 Step 1: Inferring Current Weekly Footprint (`_inferWeeklySchedule`)
Rather than relying on an idealized or stale timetable table, AttendEase reconstructs reality from actual attendance records:
- **Filtering:** Excludes `NC` records.
- **Recency Window:** A weekday is valid only if the subject was seen on that weekday within the last 21 days of that subject's latest recorded history (`recentCutoff = latest.subtract(Duration(days: 21))`).
- **Recurrence Threshold:** Must have $\ge 2$ distinct calendar dates on that weekday to filter out one-off replacement lectures.
- **Lecture Volume:** Lectures per day are derived from the most recent complete occurrence. Today is excluded from this sample if it is in progress to prevent undercounting multi-lecture slots.

### 8.2 Step 2: Week Bounds & Sunday Rollover
- **Week Start:** Monday of the current week (`today - (weekday - 1)`).
- **Sunday Rollover:** Because Sunday has no classes, on Sunday (`weekday == 7`), the simulator rolls over to the **coming week** (`isNextWeek = true`, `weekStart = today + 1 day`).

### 8.3 Step 3: Settling Today's In-Progress Lectures
Lectures already conducted today must not be double-counted as future skippable slots:
- `settledToday`: Counts records for today where `status IN ('P', 'A', 'NC')`.
- `NU` (Not Updated) does **not** settle a slot; it remains in play as an unaccounted conducted lecture.
- If all lectures today are settled, today is marked `SkipVerdict.settled`.

### 8.4 Step 4: The Cumulative Simulation Walk
The simulator iterates through every day $i \in \{0..6\}$ (Monday to Sunday):

1. **Past Days (`date < today`):**  
   Marked `SkipVerdict.past`. (Their real outcomes are already reflected in `subjectStats`).
2. **No Scheduled Classes:**  
   If no lectures are scheduled, marked `SkipVerdict.settled` (if settled lectures existed) or `SkipVerdict.noClasses`.
3. **Hypothetical Absence Simulation:**  
   For scheduled lectures on day $D$:
   - The simulator tentatively assumes the student is **absent for all lectures on that day**:
     $$\text{total}[sid] = \text{total}[sid] + 1 \quad \forall sid \in \text{lectures}$$
     $$\text{attended}[sid] \text{ remains unchanged}$$
   - **Breach Test (`firstBreach`):**
     - Checks each subject: Is $\frac{\text{attended}[sid]}{\text{total}[sid]} \times 100 < \text{subjectRequired}[sid] - 10^{-9}$?
     - Checks overall macro attendance: Is $\frac{\sum \text{attended}}{\sum \text{total}} \times 100 < \text{overallRequired} - 10^{-9}$?
   - **Branch A: No Breach Occurs:**
     - Day verdict is set to `SkipVerdict.skippable`.
     - **Cumulative Retention:** The increased `total` counts **remain in place** for all subsequent days evaluated in the week.
     - `consumedFutureDay` is set to `true`.
   - **Branch B: Breach Occurs:**
     - Day verdict is set to `SkipVerdict.unsafe`.
     - `blockingSubjectId` is set to the offending subject ID (or `null` if overall attendance caused the breach).
     - **Rollback:** The tentative absences for this day are reverted (`total.addAll(snapshot)`).
     - The simulator **continues evaluating subsequent days**.

---

## 9. Per-Subject Status / "What Should I Do?"

The decision matrix executed by `_getPredictiveInsight()` in [`lib/screens/dashboard/dashboard_screen.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/screens/dashboard/dashboard_screen.dart#L243-L286):

```
                               ┌─────────────────────────┐
                               │  Is Total Lectures == 0?│
                               └────────────┬────────────┘
                                            │
                             ┌──────────────┴──────────────┐
                            YES                            NO
                             │                             │
               ["No classes recorded yet."]   ┌────────────────────────────┐
                                              │Current % >= Required %?    │
                                              └─────────────┬──────────────┘
                                                            │
                             ┌──────────────────────────────┴──────────────────────────────┐
                            YES                                                            NO
                             │                                                             │
              ┌──────────────────────────────┐                              ┌──────────────────────────────┐
              │Skips = floor(P/reqFrac - T)  │                              │    Is Required % >= 100%?    │
              └──────────────┬───────────────┘                              └──────────────┬───────────────┘
                             │                                                             │
               ┌─────────────┴─────────────┐                                ┌──────────────┴──────────────┐
           Skips > 0                   Skips <= 0                          YES                            NO
               │                           │                                │                             │
    ["You can safely skip       ["On track, but you               ["100% target cannot          [Attends = ceil(...)]
     the next X lectures."]      cannot skip the next lecture."]   be recovered."]               ["Attend next X lectures
                                                                                                  to reach Y%."]
```

### 9.1 Exhaustive Status Specification
| Status String / Template | Condition | Mathematical Formula | UI Placement | Badge State |
| :--- | :--- | :--- | :--- | :--- |
| `"No classes recorded yet."` | $\text{Total} == 0$ | $T = 0$ | Dashboard Insight, Card Footer | Safe (Green) |
| `"You can safely skip the next X lecture(s)."` | $\text{Current \%} \ge \text{Req \%}$ and $\text{Skips} > 0$ | $\text{skips} = \left\lfloor \frac{P}{\text{reqFrac}} - T \right\rfloor$ | Dashboard Insight, Card Footer, Subject Detail | Safe (Green) |
| `"On track, but you cannot skip the next lecture."` | $\text{Current \%} \ge \text{Req \%}$ and $\text{Skips} \le 0$ | $\left\lfloor \frac{P}{\text{reqFrac}} - T \right\rfloor \le 0$ | Dashboard Insight, Card Footer | Safe (Green) |
| `"A 100% target cannot be recovered after a missed lecture."` | $\text{Current \%} < \text{Req \%}$ and $\text{Req \%} \ge 100$ | $\text{reqFrac} \ge 1.0$ | Dashboard Insight, Card Footer | Risk (Red) |
| `"Attend the next X lecture(s) to reach Y%."` | $\text{Current \%} < \text{Req \%}$ and $\text{Req \%} < 100$ | $\text{attends} = \left\lceil \frac{(\text{reqFrac} \times T) - P}{1 - \text{reqFrac}} \right\rceil$ | Dashboard Insight, Card Footer | Risk (Red) |

---

## 10. Criteria Dependency Matrix

| Feature / UI Component | Overall Attendance Criteria (`overall_required_attendance`) | Per-Subject Criteria (`subjects.required_percent`) | Both | Neither | Notes |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Dashboard Overall % Gauge** | **X** | | | | Color flips to green/red based on overall criteria. |
| **Dashboard Overall Insight Footer** | **X** | | | | Generates skips/attends for overall aggregate. |
| **Dashboard Week Skip Strip (`computeWeekSkipPlan`)** | | | **X** | | Must satisfy both: no subject drops and overall doesn't drop. |
| **Subject Card % Text & Bar** | | | | **X** | Displays pure mathematical $P/T \times 100$. |
| **Subject Card Safe / Risk Badge** | | **X** | | | Determined strictly by `percent >= subject.requiredPercent`. |
| **Subject Card Insight Footer** | | **X** | | | Uses `subject.requiredPercent`. |
| **Subject Detail Live Skip Box** | | **X** | | | Uses `computeSkipPlan()` with subject target. |
| **Calendar Month Heatmap Indicators** | | | | **X** | Driven purely by day's lecture outcomes (`all_p`, `all_a`, `mixed`). |
| **Analytics & Reports Overview Card** | **X** | | | | Compares aggregate against overall required target. |
| **Exported PDF Subject Rows (`ReportSubjectRow`)** | | **X** | | | Calculates `lecturesToSpare` and `lecturesToAttend` per subject. |
| **Exported PDF Headline Summary (`dominantTarget`)** | | **X** | | | Identifies most frequent subject target across courses. |

---

## 11. Safe to Skip Logic (Exhaustive Architectural Search)

AttendEase contains **three distinct implementations** of safe-to-skip calculations, intentionally tailored for their specific operational contexts:

### 11.1 Implementation A: Scalar Subject Buffer (`_getPredictiveInsight`)
- **Location:** `lib/screens/dashboard/dashboard_screen.dart:243`
- **Scope:** Immediate scalar recommendation for a single course or overall macro.
- **Formula:** `((attended / reqFrac) - total).floor()`
- **Output:** String recommendation + integer count. Does not calculate dates.

### 11.2 Implementation B: Calendar Forward Projection (`computeSkipPlan`)
- **Location:** `lib/utils/calculation_utils.dart:41`
- **Scope:** Subject Detail screen live projection.
- **Formula:** Same buffer math, plus 70-day forward calendar walk mapping lectures to concrete upcoming calendar dates (`SkipPlan.dates`, `countPerDate`).

### 11.3 Implementation C: Multi-Subject Weekly Simulator (`computeWeekSkipPlan`)
- **Location:** `lib/utils/calculation_utils.dart:320`
- **Scope:** Dashboard Monday–Sunday week strip.
- **Formula:** Multi-variable cumulative simulation enforcing simultaneous satisfaction of $N$ subject criteria and 1 overall criterion.

---

## 12. Projection / Future Attendance Modeling

When a student asks, *"What will my attendance be if I attend/miss the next $k$ lectures?"*, AttendEase uses the following deterministic models:

### 12.1 Attending Next $k$ Lectures Consecutively
$$\text{Projected \%} = \frac{\text{Attended} + k}{\text{Total} + k} \times 100$$
$$\lim_{k \to \infty} \left( \frac{\text{Attended} + k}{\text{Total} + k} \times 100 \right) = 100.0\%$$

### 12.2 Skipping Next $k$ Lectures Consecutively
$$\text{Projected \%} = \frac{\text{Attended}}{\text{Total} + k} \times 100$$

### 12.3 Recovery Equation (Lectures Required to Reach Target)
To find minimum integer $k$ such that $\frac{P + k}{T + k} \ge R$, where $R = \frac{\text{target}}{100}$:
$$P + k \ge R(T + k) \implies P + k \ge RT + Rk \implies k(1 - R) \ge RT - P \implies k \ge \frac{RT - P}{1 - R}$$
$$\mathbf{k = \left\lceil \frac{R \cdot \text{Total} - \text{Attended}}{1 - R} \right\rceil}$$

*Special Case:* If $R \ge 1.0$ ($100\%$) and $\text{Attended} < \text{Total}$, recovery is mathematically impossible because the denominator $(1 - R) \le 0$. The app explicitly traps this and returns: `"A 100% target cannot be recovered after a missed lecture."`

---

## 13. Timetable Dependency & Schedule Inference

### 13.1 Timetable as Structure vs. Historical Inference
AttendEase implements a dual timetable philosophy:
1. **Static Timetable (`timetable` table):** Used for manual schedule setup, day schedule layout on dates without reports, and providing seed slots (`day_of_week = 0`).
2. **Inferred Timetable (`_inferWeeklySchedule` & `LocalPdfParser.inferWeeklyTimetable`):** **Used for all skip calculations.** The engine does not assume the static timetable is up to date. Instead, it reads actual `attendance_records` to detect shifts in room, time, or weekday.

```
┌────────────────────────┐       ┌────────────────────────┐
│    Static Timetable    │       │   Attendance Records   │
│  (Manually configured) │       │   (Actual SAP History) │
└───────────┬────────────┘       └───────────┬────────────┘
            │                                │
            ▼                                ▼
  [Calendar Empty Days]           [_inferWeeklySchedule]
                                             │
                                             ▼
                                  [Weekly Skip Simulator]
```

### 13.2 Handling Mid-Semester Schedule Shifts
If a subject shifted from Monday 9:20 AM to Monday 11:20 AM, or moved from Friday to Wednesday mid-semester:
- The 21-day recency cutoff (`latest.subtract(Duration(days: 21))`) drops the old slot once 3 weeks have elapsed.
- It prevents phantom slots from corrupting the safe-to-skip projection.

---

## 14. Calendar Dependency & Heatmap Architecture

### 14.1 Heatmap State Generation
From [`lib/screens/calendar/calender_screen.dart`](file:///c:/Users/parth/AndroidStudioProjects/attend_ease/lib/screens/calendar/calender_screen.dart#L251-L292), each day of the month is assigned a status:

```
                                 ┌─────────────────────────┐
                                 │   Is date within sem?   │
                                 └────────────┬────────────┘
                                              │
                               ┌──────────────┴──────────────┐
                               NO                            YES
                               │                             │
                          ['outside']          ┌─────────────────────────────┐
                                               │      Is it a Sunday?        │
                                               └──────────────┬──────────────┘
                                                              │
                                               ┌──────────────┴──────────────┐
                                              YES                            NO
                                               │                             │
                                          ['holiday']          ┌─────────────────────────────┐
                                                               │       Is date > today?      │
                                                               └──────────────┬──────────────┘
                                                                              │
                                                               ┌──────────────┴──────────────┐
                                                              YES                            NO
                                                               │                             │
                                                          ['future']           ┌─────────────────────────────┐
                                                                               │    Are records present?     │
                                                                               └──────────────┬──────────────┘
                                                                                              │
                                                               ┌──────────────────────────────┴──────────────────────────────┐
                                                               NO                                                           YES
                                                               │                                                             │
                                                         ['no_record']                                                       │
                                                                               ┌─────────────────────────────────────────────┴─────────────────────────────────────────────┐
                                                                               │                                                                                           │
                                                                      All NU or NC?                                                                               Only P and A considered:
                                                                               │                                                                                           │
                                                                          ['all_nu']                                                 ┌─────────────────────────────┼─────────────────────────────┐
                                                                                                                                     │                             │                             │
                                                                                                                                All 'P'?                      All 'A'?                        Mixed
                                                                                                                                     │                             │                             │
                                                                                                                                 ['all_p']                     ['all_a']                      ['mixed']
```

---

## 15. Degree College vs. Junior College Isolation

AttendEase strictly isolates Degree College from Junior College across databases, preferences, and UI models.

```
                             [College Section Partition]
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
          [Degree College]                                [Junior College]
          ├── Semesters 1 to 8                            ├── Terms: FYJC and SYJC
          ├── semester = 1..8                             ├── Internal IDs: FYJC=11, SYJC=12
          ├── Keys: semester_start_$sem                   ├── Keys: junior_term_start_$term
          └── Label: "Semester X"                         └── Label: "FYJC" / "SYJC" (Term)
```

### 15.1 Storage Identification
- **Degree College:** `college_type = 'degree'`. Semesters are represented by integers `1` through `8`.
- **Junior College:** `college_type = 'junior'`. Semesters do not exist in Junior College; the academic period is called a **Term** (`'FYJC'` or `'SYJC'`).
- **Internal Storage Compatibility IDs:** In SQLite tables (`subjects.semester` and `imported_report_dates.semester`), numeric foreign IDs are required. The system maps:
  - $\mathbf{FYJC} \longleftrightarrow \mathbf{11}$
  - $\mathbf{SYJC} \longleftrightarrow \mathbf{12}$
  > [!IMPORTANT]
  > Numbers `11` and `12` are **internal storage keys only**, designed to prevent collisions with Degree Semesters 1 and 2. They are never shown to the user as semesters.

### 15.2 Date Bounds Isolation
- Degree College: `semester_start_1` ... `semester_end_8`
- Junior College: `junior_term_start_FYJC`, `junior_term_end_FYJC`, `junior_term_start_SYJC`, `junior_term_end_SYJC`

### 15.3 Query Isolation Proof
Every DAO query scopes subject and attendance data by the academic period ID:
`WHERE s.semester = ?` (passing `1..8` or `11..12`).  
Degree attendance can never bleed into Junior College data, and FYJC data can never bleed into SYJC.

---

## 16. PDF Import & Report Sync Pipeline

### 16.1 Autonomous Period Routing
When a user clicks "Sync Report" or uploads a PDF:
1. `LocalPdfParser.parseAttendancePdf()` scans the raw document text.
2. It detects the college section and period directly from the PDF header:
   - Matches `"FYJC"` $\implies$ `collegeType = 'junior'`, `term = 'FYJC'`, internal `semester = 11`.
   - Matches `"SYJC"` $\implies$ `collegeType = 'junior'`, `term = 'SYJC'`, internal `semester = 12`.
   - Matches `"Semester V"` or `"Sem 5"` $\implies$ `collegeType = 'degree'`, `semester = 5`.
3. **Strict Destination Routing:** The detected PDF identity **overrides** whatever UI tab or section the user currently has open. An FYJC PDF will always import into FYJC (ID 11), never into the currently viewed SYJC or Degree screen.

### 16.2 Upsert & NC Reconciliation
- `reconcileNotConductedLectures()`: Updates previously recorded slots to `NC` if the updated report marks them Not Conducted.
- `imported_report_dates`: New dates found in the PDF are registered to ensure Calendar knows they have SAP coverage.
- Records are inserted with `source = 'pdf'` and `original_status` populated.

---

## 17. Database & Service Call Flow

```
[User Marks Lecture / Uploads PDF]
                │
                ▼
      [UI Screen / Widget]
 (Calendar / Subject Detail / Sync Action)
                │
                ▼
      [Business Service Layer]
 (PdfAttendanceImportService / AttendanceReportSyncService)
                │
                ▼
      [AttendanceDao / SubjectDao]
 (Runs SQL Transactions on SQLite DB)
                │
                ▼
   [Local Database: attend_ease.db]
 (Updates attendance_records, subjects, imported_dates)
                │
                ▼
      [AppRefreshBus.refreshAll()]
 (Fires Reactive Broadcast to all mounted tabs)
                │
                ▼
     [CalculationUtils Engine]
 (Recalculates percentages, buffers, and weekly plans)
                │
                ▼
     [UI Component Repaint]
 (Dashboard ring, Insight footers, Week strip, Subject cards)
                │
                ▼
     [CloudSyncService (Async Background)]
 (Pushes dirty changes up to Firestore)
```

---

## 18. Exact Mathematical Formulas Index

### Formula 1: Overall Macro Attendance
$$\mathbf{\text{Overall \%} = \frac{\sum_{i=1}^N P_i}{\sum_{i=1}^N (P_i + A_i)} \times 100}$$
- **File:** `lib/screens/dashboard/dashboard_screen.dart`, `lib/screens/report/report_screen.dart`
- **Zero Case:** If $\sum (P + A) = 0 \implies 0.0\%$

### Formula 2: Subject Attendance
$$\mathbf{\text{Subject \%} = \frac{P}{P + A} \times 100}$$
- **File:** `lib/utils/calculation_utils.dart:calculatePercentage`
- **Zero Case:** If $P + A = 0 \implies 0.0\%$

### Formula 3: Maximum Safe Skips (Subject Buffer)
$$\mathbf{\text{maxSkips} = \left\lfloor \frac{P}{\left(\frac{R}{100}\right)} - (P + A) \right\rfloor}$$
- **File:** `lib/utils/calculation_utils.dart:computeSkipPlan`
- **Condition:** Valid only when $\frac{P}{P + A} \times 100 \ge R$.

### Formula 4: Required Lectures to Attend to Recover
$$\mathbf{\text{attends} = \left\lceil \frac{\left(\frac{R}{100}\right)(P + A) - P}{1 - \left(\frac{R}{100}\right)} \right\rceil}$$
- **File:** `lib/screens/dashboard/dashboard_screen.dart:_getPredictiveInsight`, `lib/services/attendance_report_pdf.dart:ReportSubjectRow`
- **Condition:** Valid only when $\frac{P}{P + A} \times 100 < R$ and $R < 100$.

---

## 19. Edge Cases & Boundary Handlers

| Edge Case | Code Behavior | Verification Status |
| :--- | :--- | :--- |
| **0 Total Conducted Lectures** | Returns `0.0%`. Displays `"No classes recorded yet."` | CONFIRMED FROM CODE |
| **100% Attendance Target & 1 Missed** | Recovery formula denominator becomes $0$. Trapped by `if (requiredPercent >= 100)`; displays `"A 100% target cannot be recovered after a missed lecture."` | CONFIRMED FROM CODE |
| **Attendance Exactly at Target** | $\text{Current \%} == \text{Req \%} \implies \text{skips} = 0$. Displays `"On track, but you cannot skip the next lecture."` | CONFIRMED FROM CODE |
| **Floating-Point Precision Tolerance** | Comparisons in simulator use `req - 1e-9` to prevent rounding errors (e.g. $74.999999999\%$ failing a $75.0\%$ target). | CONFIRMED FROM CODE |
| **Sunday Operations** | Week strip automatically rolls over to the coming week (`isNextWeek = true`). | CONFIRMED FROM CODE |
| **Double Lecture on Same Day** | Managed via `_2` suffix in dates. Settling one slot leaves the second in play for week simulation. | CONFIRMED FROM CODE |
| **NU Records** | Excluded from historical calculations, but counted as unrecorded slots in weekly projections. | CONFIRMED FROM CODE |

---

## 20. Rounding, Precision & Floating-Point Thresholds

1. **`floor()`:** Used exclusively for skip counts:
   `((attended / reqFrac) - total).floor()`. Ensures the app never over-promises skippable lectures.
2. **`ceil()`:** Used exclusively for recovery lecture counts:
   `(((reqFrac * total) - attended) / (1 - reqFrac)).ceil()`. Ensures the student attends enough classes to cross the threshold.
3. **`1e-9` Threshold:** In `firstBreach()`, comparison uses `(attended / t) * 100 < req - 1e-9`.
4. **Display Formatting:**
   - Dashboard Overall Gauge: `.toStringAsFixed(1)` (e.g. `"84.2%"`)
   - Subject Detail Header: `.toStringAsFixed(2)` (e.g. `"84.21%"`)
   - Report Screen: `.toStringAsFixed(1)` (e.g. `"84.2%"`)

---

## 21. UI to Logic Direct Mapping

```
┌───────────────────────────────────────┐
│              DASHBOARD                │
│                                       │
│  Overall Attendance (Sem 5)           │
│  [ 84.2% ]  Target: 75.0%             │ ◄─── DashboardScreen._currentOverall
│  ( O ) Ring Progress Indicator        │ ◄─── Animated progress: _currentOverall / 100
│                                       │
│  [ You can safely skip next 4 lecs. ] │ ◄─── _getPredictiveInsight(attended, total, 75.0)
├───────────────────────────────────────┤
│  WEEK SKIP STRIP                      │
│  MON   TUE   WED   THU   FRI   SAT    │ ◄─── computeWeekSkipPlan()
│  [P]   [S]   [U]   [S]   [-]   [S]    │ ◄─── SkipVerdict (past, skippable, unsafe, settled)
├───────────────────────────────────────┤
│  YOUR SUBJECTS                        │
│                                       │
│  Operating Systems With Linux   88.9% │ ◄─── stat['attended'] / stat['total'] * 100
│  [=========>       ] 16/18 lectures   │ ◄─── LinearProgressIndicator
│  Safe · You can safely skip 3 lecs.   │ ◄─── _SubjectCard.insight
└───────────────────────────────────────┘
```

---

## 22. Automated Test Suite Coverage & Verification Gaps

### 22.1 Existing Automated Tests
- `test/timetable_and_skip_test.dart`: Validates `computeSkipPlan()`, `computeWeekSkipPlan()`, `inferWeeklyTimetable()`, recency cutoffs, and cumulative week walks against a real 127-row SAP report.
- `test/junior_college_isolation_and_persistence_test.dart`: Validates isolation between FYJC (11), SYJC (12), and Degree semesters.
- `test/attendance_report_sync_routing_test.dart`: Validates that uploaded PDFs route to their intrinsic academic periods rather than the active UI tab.
- `test/not_conducted_visibility_test.dart`: Validates that `NC` records do not count toward attendance totals.
- `test/replacement_lecture_flow_test.dart`: Validates replacement lecture handling.

### 22.2 Coverage Gaps & Untested Scenarios
1. **Mid-semester target adjustments:** No unit test verifies dynamic re-calculation when a subject's `required_percent` is modified after records are stored.
2. **Multi-year leap day imports:** Handling of February 29 during custom date range selection in leap years.

---

## 23. Source Code Inventory

### 23.1 Engine Core & Calculations
- **`lib/utils/calculation_utils.dart`**
  - `calculatePercentage(int attended, int total)`: Pure division with 0-guard.
  - `computeSkipPlan(...)`: Computes single-subject skip buffer and 70-day dates.
  - `computeWeekSkipPlan(...)`: Simulates current week day-by-day.
  - `_inferWeeklySchedule(...)`: Extracts active schedule footprint from 21-day history.

### 23.2 Database Layer
- **`lib/database/db_helper.dart`**: SQLite database creation, schema definitions, constraints.
- **`lib/database/attendance_dao.dart`**: Queries `getAttendanceStats()`, `getAttendanceStatsForDateRange()`, `getDaySchedule()`, `reconcileNotConductedLectures()`.
- **`lib/database/subject_dao.dart`**: Course CRUD and semester filtering.
- **`lib/database/timetable_dao.dart`**: Timetable CRUD and seed entry generator.

### 23.3 Presentation Layer
- **`lib/screens/dashboard/dashboard_screen.dart`**: Dashboard display, overall gauge, week skip strip, predictive insight.
- **`lib/screens/calendar/calender_screen.dart`**: Month heatmap, daily schedule, bulk day marking (`planDayMark`), delete with undo.
- **`lib/screens/report/subject_detail_screen.dart`**: Subject history list, live skip calculator, range filtering.
- **`lib/screens/report/report_screen.dart`**: Term & custom date range reports.
- **`lib/services/attendance_report_pdf.dart`**: Exported PDF generator with `ReportSubjectRow`.

---

## 24. Fact vs. Inference Verification Log

| Topic / Finding | Status | Source Code Proof |
| :--- | :---: | :--- |
| Overall % is lecture-weighted macro | **CONFIRMED FROM CODE** | `attendance_dao.dart:36`, `report_screen.dart:298-304` |
| NC lectures do not penalize attendance | **CONFIRMED FROM CODE** | `attendance_dao.dart:28` (`status IN ('P','A')`) |
| Junior College uses internal IDs 11 & 12 | **CONFIRMED FROM CODE** | `report_screen.dart:86`, `basic_info_screen.dart` |
| Week skip simulator walks cumulatively | **CONFIRMED FROM CODE** | `calculation_utils.dart:464` (`consumedFutureDay`) |
| Recovery calculation uses `ceil()` | **CONFIRMED FROM CODE** | `dashboard_screen.dart:278`, `attendance_report_pdf.dart:48` |
| Skip calculation uses `floor()` | **CONFIRMED FROM CODE** | `calculation_utils.dart:58`, `dashboard_screen.dart:254` |
| Sunday triggers week rollover | **CONFIRMED FROM CODE** | `calculation_utils.dart:334` (`weekday == DateTime.sunday`) |
| Seed entries use `day_of_week = 0` | **CONFIRMED FROM CODE** | `timetable_dao.dart:ensureSeedEntry` |

---

## 25. Final Executive Summary

1. **How is overall attendance calculated?**  
   Directly as $\frac{\sum P}{\sum(P + A)} \times 100$ across all subjects for the active period. It is lecture-count weighted, not an average of subject percentages.
2. **How is per-subject attendance calculated?**  
   As $\frac{P}{P + A} \times 100$ for that course.
3. **What is the overall attendance criterion?**  
   A global user preference stored in `SharedPreferences` (`overall_required_attendance`), defaulting to `75.0%`.
4. **What is the per-subject attendance criterion?**  
   A per-course threshold stored in `subjects.required_percent`, defaulting to `70.0%`.
5. **What exactly determines how many lectures I can skip?**  
   $\lfloor \frac{\text{Attended}}{\text{reqFrac}} - \text{Total} \rfloor$.
6. **What exactly determines how many days I can skip?**  
   For a single subject: Mapping the lecture buffer forward onto recurring class days up to 70 days. For the week: The cumulative simulator evaluating whether absenting all classes on a day keeps all subjects and overall attendance above target.
7. **How does "this week" calculate skip/attendance information?**  
   Reconstructs the active weekly schedule from the last 21 days of attendance records, then simulates skipping each day from today through Saturday/Sunday.
8. **What determines the per-subject status?**  
   Whether current attendance is above or below `subject.requiredPercent`, calculating either safe skips (`floor`) or recovery lectures needed (`ceil`).
9. **Which parts depend on overall criteria?**  
   Dashboard overall gauge, overall insight card, and macro ceiling in week skip planning.
10. **Which parts depend on per-subject criteria?**  
    Subject cards, Subject Detail live skip box, individual subject checks in week skip planning, and PDF export rows.
11. **Which parts depend on both?**  
    The Dashboard Week Skip Strip (`computeWeekSkipPlan`).
12. **How does timetable data affect the calculations?**  
    The static timetable provides slot structure and day views, but skip projections dynamically infer the schedule from actual attendance records.
13. **How do NC/cancelled/replacement lectures affect them?**  
    `NC` is excluded from attended and conducted totals. Replacements are logged as actual records with occurrence suffixes (`_2`) and incorporated into the inferred schedule.
14. **How do PDF imports affect them?**  
    Parsed by `LocalPdfParser`, routed to the PDF's intrinsic academic period, reconciles `NC` rows, writes to SQLite, and triggers an app-wide refresh.
15. **How are Degree semesters isolated?**  
    By `subjects.semester` taking values `1..8` and semester-scoped preference keys.
16. **How are Junior FYJC/SYJC terms isolated?**  
    By `subjects.semester` taking internal IDs `11` (FYJC) and `12` (SYJC) and term-scoped preference keys.
17. **What are the most important formulas in the app?**  
    Macro attendance ($\sum P / \sum T$), Skip buffer ($\lfloor P/R - T \rfloor$), Recovery attendance ($\lceil (RT - P)/(1-R) \rceil$), and Week breach testing.
18. **What are the biggest edge cases?**  
    Zero total lectures, recovery with 100% target, floating-point rounding tolerance (`1e-9`), Sunday week rollover, and mid-semester timetable shifts.
19. **Which files/functions are the most important if we need to modify attendance logic later?**  
    `lib/utils/calculation_utils.dart` (`computeSkipPlan`, `computeWeekSkipPlan`), `lib/database/attendance_dao.dart` (`getAttendanceStats`), and `lib/screens/dashboard/dashboard_screen.dart` (`_getPredictiveInsight`).
20. **What should NOT be changed casually?**  
    The definition of conducted lectures ($P + A$), the exclusion of `NC`/`NU` from percentage totals, the internal IDs `11`/`12` for Junior College, the `1e-9` floating-point tolerance, and the cumulative retention mechanism in the weekly simulator.
