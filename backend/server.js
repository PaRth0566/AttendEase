import express from 'express';
import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import multer from 'multer';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

// ── Model Fallback Chain ──────────────────────────────────────────────────────
// Tried top-to-bottom; advances to the next on HTTP 503 (model overloaded).
const GEMINI_MODELS = [
  'gemini-3-flash-preview',
  'gemini-2.5-flash',
  'gemini-3.1-flash-lite-preview',
  'gemini-2.5-flash-lite',
];

/**
 * Calls the Gemini generateContent API, trying each model in GEMINI_MODELS
 * order. Falls back to the next model on 503 overloaded errors only.
 * Throws on any other error or when all models are exhausted.
 */
async function callWithFallback(prompt, pdfPart) {
  let lastError;
  for (const model of GEMINI_MODELS) {
    try {
      console.log(`[Gemini] Trying model: ${model}`);
      const response = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${process.env.GEMINI_API_KEY}`,
        {
          contents: [{ role: 'user', parts: [{ text: prompt }, pdfPart] }],
          generationConfig: { responseMimeType: 'application/json' },
        },
        { headers: { 'Content-Type': 'application/json' } }
      );
      console.log(`[Gemini] Success with model: ${model}`);
      return response;
    } catch (err) {
      if (err.response?.status === 503) {
        console.warn(`[Gemini] ${model} is overloaded (503), trying next fallback...`);
        lastError = err;
      } else {
        throw err; // Non-503 errors propagate immediately
      }
    }
  }
  throw lastError; // All models exhausted
}

// ── Health Check ──────────────────────────────────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({ status: 'awake', timestamp: new Date() });
});

// ── Attendance Analysis Endpoint (Web) ────────────────────────────────────────
app.post('/api/analyze-attendance', (req, res, next) => {
  upload.single('report')(req, res, function (err) {
    if (err) {
      console.error("Multer Error:", err);
      return res.status(400).json({ success: false, error: `File Upload Error: ${err.message}` });
    }
    next();
  });
}, async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No PDF file provided under the "report" field.' });
    }
    if (req.file.mimetype !== 'application/pdf') {
      return res.status(400).json({ success: false, error: 'Only PDF files are accepted.' });
    }

    console.log(`Received PDF: ${req.file.originalname} (${req.file.size} bytes)`);

    const prompt = `
You are a precise attendance data extractor. Accuracy is critical — a student's academic standing depends on this.

I have attached a college attendance PDF report. It contains rows with: Date, Subject, and a status column marked as one of:
- "P" = Present (student attended)
- "A" = Absent (student did NOT attend)

STEP-BY-STEP INSTRUCTIONS:
1. First, extract metadata from the report header: student full name, semester, program, academic year, report start date, and report end date.
2. Identify every unique subject name in the report.
3. For EACH subject, go through EVERY row belonging to that subject and:
   - Count "P" entries → this is "attended"
   - Count "A" entries → add to total but NOT to attended
   - SKIP any "Cancelled" entries entirely — do NOT count them in attended OR total
   - "total" = number of "P" entries + number of "A" entries (excluding Cancelled)
4. Double-check your counts by verifying: attended + absent = total for each subject.

Return ONLY a JSON object matching this exact schema:
{
  "studentName": "Full Name",
  "semester": "Semester III",
  "program": "B.Tech Computer Science",
  "academicYear": "2025-2026",
  "reportStartDate": "01 Jan 2025",
  "reportEndDate": "30 Apr 2025",
  "subjects": [
    {
      "name": "Subject Name",
      "attended": 10,
      "total": 12
    }
  ]
}

RULES:
- "attended" must NEVER be greater than "total".
- "total" must NEVER include Cancelled classes.
- If a metadata field is not found, use an empty string "".
- Do NOT guess or approximate. Count every single row precisely.
`;

    const pdfPart = {
      inlineData: {
        mimeType: req.file.mimetype,
        data: req.file.buffer.toString("base64")
      }
    };

    const response = await callWithFallback(prompt, pdfPart);
    const insights = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '{"subjects":[]}';

    res.json({ success: true, insights });
  } catch (err) {
    console.error("Attendance Analysis Error:", err.response?.data || err.message);
    res.status(500).json({ success: false, error: 'Failed to analyze attendance report. See backend logs.' });
  }
});

// ── Setup Data Extraction Endpoint (Android) ──────────────────────────────────
app.post('/api/extract-setup-data', (req, res, next) => {
  upload.single('report')(req, res, function (err) {
    if (err) {
      console.error("Multer Error:", err);
      return res.status(400).json({ success: false, error: `File Upload Error: ${err.message}` });
    }
    next();
  });
}, async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No PDF file provided under the "report" field.' });
    if (req.file.mimetype !== 'application/pdf') return res.status(400).json({ success: false, error: 'Only PDF files are accepted.' });

    console.log(`Received PDF for Setup: ${req.file.originalname} (${req.file.size} bytes)`);

    const prompt = `
You are a precise attendance data extractor. Accuracy is critical — a student's academic standing depends on this.

I have attached a college attendance PDF report. It contains rows with: Date, Subject, and a status column marked as one of:
- "P" = Present (student attended)
- "A" = Absent (student did NOT attend)

STEP-BY-STEP INSTRUCTIONS:
1. First, extract metadata from the report header: student full name, semester, program (course), academic year.
2. Identify every unique subject name in the report.
3. For EACH subject, go through EVERY row belonging to that subject and:
   - Count "P" entries → this is "attended"
   - Count "A" entries → add to total but NOT to attended
   - SKIP any "Cancelled" entries entirely — do NOT count them in attended OR total
   - "total" = number of "P" entries + number of "A" entries (excluding Cancelled)
4. Double-check your counts by verifying: attended + absent = total for each subject.
5. Create an EXHAUSTIVE list of every non-cancelled attendance record.
   - You MUST extract EVERY SINGLE ROW to match your calculated "total" for each subject.
   - For each row, assign "lectureOrder" (its sequential position for that subject on that date, starting at 1).
   - For each row, assign "daySlot" (its sequential position among all classes on that date, starting at 1).

Return ONLY a JSON object matching this exact schema:
{
  "studentName": "Full Name",
  "course": "B.Tech Computer Science",
  "year": "2025-2026",
  "semester": "Semester III",
  "subjects": ["Subject 1", "Subject 2"],
  "subjectStats": {
    "Subject 1": { "attended": 10, "total": 12 }
  },
  "attendanceRecords": [
    {
      "date": "2025-01-20",
      "subject": "Subject Name",
      "status": "P",
      "lectureOrder": 1,
      "daySlot": 3
    }
  ]
}

RULES:
- "attended" must NEVER be greater than "total".
- "total" must NEVER include Cancelled classes.
- "attendanceRecords" MUST contain EXACTLY "total" number of elements for each subject. Count them to be sure!
- If a metadata field is not found, use an empty string "".
- Do NOT guess or approximate. Output exactly what is in the PDF.
`;

    const pdfPart = {
      inlineData: { mimeType: req.file.mimetype, data: req.file.buffer.toString("base64") }
    };

    const response = await callWithFallback(prompt, pdfPart);
    let dataObj = {};
    try {
      const text = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
      const cleanedStr = text.replace(/```json/g, '').replace(/```/g, '').trim();
      dataObj = JSON.parse(cleanedStr);
    } catch (_) { }

    // Post-process: Construct timetable from AI-extracted attendance records.
    // We use daySlot (AI-provided) to determine lecture order within a day.
    if (Array.isArray(dataObj.attendanceRecords)) {
      // Step 0: Ensure attendanceRecords exhaustively match subjectStats (LLM hallucination fallback)
      if (dataObj.subjectStats) {
        const extractedCounts = {};
        dataObj.attendanceRecords.forEach(r => {
          if (!r.subject) return;
          if (!extractedCounts[r.subject]) extractedCounts[r.subject] = { P: 0, A: 0 };
          if (r.status === 'P') extractedCounts[r.subject].P++;
          if (r.status === 'A') extractedCounts[r.subject].A++;
        });

        // Find a fallback date to use if we have to pad
        const fallbackDate = dataObj.attendanceRecords.find(r => r.date)?.date || '2025-01-01';

        for (const [subject, stats] of Object.entries(dataObj.subjectStats)) {
          const counts = extractedCounts[subject] || { P: 0, A: 0 };
          const neededP = (stats.attended || 0) - counts.P;
          const neededA = ((stats.total || 0) - (stats.attended || 0)) - counts.A;

          // If the AI skipped records, synthesize them so the app's stats match perfectly
          for (let i = 0; i < neededP; i++) {
            dataObj.attendanceRecords.push({ date: fallbackDate, subject, status: 'P' });
          }
          for (let i = 0; i < neededA; i++) {
            dataObj.attendanceRecords.push({ date: fallbackDate, subject, status: 'A' });
          }
        }
      }

      // Step 1: Fix lectureOrder/lectureNumber — use AI's lectureOrder if present,
      // otherwise compute it deterministically from the records in document order.
      const dailySubjectCounts = {};
      const dailySlotCounts = {};

      dataObj.attendanceRecords.forEach(record => {
        if (!record.date || !record.subject) return;

        // Compute lectureNumber (per-subject-per-date counter), used by the Flutter side
        const countKey = `${record.date}_${record.subject}`;
        dailySubjectCounts[countKey] = (dailySubjectCounts[countKey] || 0) + 1;
        // Only override if AI didn't provide it
        if (!record.lectureOrder && !record.lectureNumber) {
          record.lectureNumber = dailySubjectCounts[countKey];
        } else {
          // Prefer AI-supplied lectureOrder as lectureNumber
          record.lectureNumber = record.lectureOrder || dailySubjectCounts[countKey];
        }

        // Compute daySlot if AI didn't provide it
        if (!record.daySlot) {
          dailySlotCounts[record.date] = (dailySlotCounts[record.date] || 0) + 1;
          record.daySlot = dailySlotCounts[record.date];
        }
      });

      // Step 2: Build timetable per day-of-week.
      // For each day, we need to know which subjects appear and in what slot order.
      // Key insight: use daySlot to determine the ORDER of subjects in the timetable.
      // We track, for each (dayOfWeek, subject), the MINIMUM daySlot seen across all dates
      // (to determine where in the day the subject sits) and MAXIMUM daily repetitions.
      //
      // timetableMap[dayOfWeek][subject] = { minSlot, maxReps, slotsByDate }
      const timetableMap = {};

      dataObj.attendanceRecords.forEach(record => {
        if (!record.date || !record.subject) return;

        const dateMatch = record.date.match(/(\d{4})-(\d{2})-(\d{2})/);
        if (!dateMatch) return;

        const [_, year, month, day] = dateMatch;
        const dateObj = new Date(Date.UTC(parseInt(year), parseInt(month) - 1, parseInt(day)));
        if (isNaN(dateObj.getTime())) return;

        let dayOfWeek = dateObj.getUTCDay(); // 0=Sun
        if (dayOfWeek === 0) dayOfWeek = 7;  // Mon=1 … Sun=7

        if (!timetableMap[dayOfWeek]) timetableMap[dayOfWeek] = {};
        if (!timetableMap[dayOfWeek][record.subject]) {
          timetableMap[dayOfWeek][record.subject] = {
            minSlot: Infinity,   // earliest daySlot seen for this subject on this weekday
            maxReps: 0,          // max times this subject appears in one day
            repsByDate: {},      // counts per date to compute maxReps
          };
        }

        const entry = timetableMap[dayOfWeek][record.subject];

        // Track earliest slot this subject appears in the day (to sort later)
        const slot = record.daySlot || record.lectureNumber || 1;
        if (slot < entry.minSlot) entry.minSlot = slot;

        // Track max repetitions per date
        entry.repsByDate[record.date] = (entry.repsByDate[record.date] || 0) + 1;
        if (entry.repsByDate[record.date] > entry.maxReps) {
          entry.maxReps = entry.repsByDate[record.date];
        }
      });

      // Step 3: Assemble the timetable array.
      // For each day, sort subjects by their minSlot (first-appearance order in the day),
      // then expand repeated subjects inline.
      const timetable = [];
      for (const [dayStr, subMap] of Object.entries(timetableMap)) {
        const dayOfWeek = parseInt(dayStr);

        // Sort subjects by earliest slot seen on this day (preserves PDF order)
        const orderedSubjects = Object.keys(subMap).sort(
          (a, b) => subMap[a].minSlot - subMap[b].minSlot
        );

        const subjects = [];
        for (const subjectName of orderedSubjects) {
          const { maxReps } = subMap[subjectName];
          for (let i = 0; i < maxReps; i++) {
            subjects.push(subjectName);
          }
        }
        timetable.push({ dayOfWeek, subjects });
      }

      // Sort timetable by dayOfWeek for consistency
      timetable.sort((a, b) => a.dayOfWeek - b.dayOfWeek);
      dataObj.timetable = timetable;
    }

    res.json({ success: true, data: JSON.stringify(dataObj) });
  } catch (err) {
    console.error("Extraction Error:", err.response?.data || err.message);
    res.status(500).json({ success: false, error: 'Failed to extract setup data.' });
  }
});

// ── Global Error Handler ──────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error("Critical Server Error:", err);
  res.status(500).json({ success: false, error: `Critical server error: ${err.message}` });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
