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

// A quick health endpoint to wake up Render instances safely.
app.get('/api/health', (req, res) => {
  res.json({ status: 'awake', timestamp: new Date() });
});

// -------------------- Attendance Analysis Endpoint --------------------
app.post('/api/analyze-attendance', (req, res, next) => {
  // Catch Multer errors gracefully so we don't crash and break CORS
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

    // Note: The user manually updated this to use gemini-2.5-flash which is perfect.
    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${process.env.GEMINI_API_KEY}`,
      {
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              pdfPart
            ]
          }
        ],
        generationConfig: {
          responseMimeType: "application/json"
        }
      },
      {
        headers: { 'Content-Type': 'application/json' }
      }
    );

    const insights = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '{"subjects":[]}';

    res.json({ success: true, insights });
  } catch (err) {
    console.error("Attendance Analysis Error:", err.response?.data || err.message);
    res.status(500).json({ success: false, error: 'Failed to analyze attendance report. See backend logs.' });
  }
});

// -------------------- Setup Data Extraction Endpoint (Android) --------------------
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
You are a precise data extractor. I have attached a college attendance PDF report.
STEP-BY-STEP INSTRUCTIONS:
1. Extract metadata from the report header: student full name, program (course), academic year.
2. Determine the semester as a number if possible, or string.
3. Identify every unique subject name in the report.

DO NOT EXTRACT OR RETURN REPORT START DATE OR END DATE.

Return ONLY a JSON object matching exactly this schema:
{
  "studentName": "Full Name",
  "course": "B.Tech Computer Science",
  "year": "2025-2026",
  "semester": "Semester III",
  "subjects": [
    "Subject 1",
    "Subject 2"
  ]
}

RULES:
- If a metadata field is not found, use an empty string "".
- Provide ONLY the JSON. No markdown formatting.
`;

    const pdfPart = {
      inlineData: { mimeType: req.file.mimetype, data: req.file.buffer.toString("base64") }
    };

    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${process.env.GEMINI_API_KEY}`,
      {
        contents: [{ role: 'user', parts: [{ text: prompt }, pdfPart] }],
        generationConfig: { responseMimeType: "application/json" }
      },
      { headers: { 'Content-Type': 'application/json' } }
    );

    const data = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
    res.json({ success: true, data });
  } catch (err) {
    console.error("Extraction Error:", err.response?.data || err.message);
    res.status(500).json({ success: false, error: 'Failed to extract setup data.' });
  }
});

// Global Error Handler to guarantee JSON responses (ensures CORS works on crashes)
app.use((err, req, res, next) => {
  console.error("Critical Server Error:", err);
  res.status(500).json({ success: false, error: `Critical server error: ${err.message}` });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
