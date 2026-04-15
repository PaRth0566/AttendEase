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
// Only extracts: student metadata, subject names, and accurate subject stats.
// Timetable is built manually in-app; no attendanceRecords needed here.
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

    // Two-phase extraction: accurate summary counts + dated records for calendar.
    const prompt = `
You are a precise attendance data extractor. Accuracy is critical — a student's academic standing depends on this.

I have attached a college attendance PDF report. It contains rows with: Date, Subject, and a status column marked as one of:
- "P" = Present (student attended)
- "A" = Absent (student did NOT attend)

STEP-BY-STEP INSTRUCTIONS:
1. Extract metadata: student full name, semester, program (course), academic year.
2. Identify every unique subject name in the report.
3. For EACH subject, count EVERY row:
   - Count "P" entries → "attended"
   - Count "A" entries → add to total but NOT attended
   - SKIP "Cancelled" entries entirely
   - "total" = P + A (no Cancelled)
4. Verify: attended + absent = total for each subject.
5. Extract EVERY non-cancelled row as an attendance record with its date.

Return ONLY a JSON object matching this exact schema:
{
  "studentName": "Full Name",
  "course": "B.Tech Computer Science",
  "year": "2025-2026",
  "semester": "Semester III",
  "subjects": ["Subject 1", "Subject 2"],
  "subjectStats": {
    "Subject 1": { "attended": 10, "total": 12 },
    "Subject 2": { "attended": 8, "total": 10 }
  },
  "attendanceRecords": [
    { "date": "2025-01-20", "subject": "Subject 1", "status": "P" },
    { "date": "2025-01-21", "subject": "Subject 2", "status": "A" }
  ]
}

RULES:
- "attended" in subjectStats must NEVER be greater than "total".
- "total" must NEVER include Cancelled classes.
- "attendanceRecords" must use date format "YYYY-MM-DD" EXACTLY (e.g., "2025-01-05", always pad single digits with zero).
- If a metadata field is not found, use an empty string "".
- Do NOT guess or approximate. Extract exactly what is in the PDF.
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

    // Ensure subjects array exists and is deduplicated
    if (!Array.isArray(dataObj.subjects)) {
      dataObj.subjects = dataObj.subjectStats ? Object.keys(dataObj.subjectStats) : [];
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
