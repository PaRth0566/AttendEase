import express from 'express';
import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import multer from 'multer';
import rateLimit from 'express-rate-limit';
import { fileTypeFromBuffer } from 'file-type';
import admin from 'firebase-admin';

dotenv.config();

const app = express();

admin.initializeApp({ credential: admin.credential.applicationDefault() });

const corsOptions = {
  origin: ['https://attendease-cbc6f.web.app', 'http://localhost:3000'],
  methods: ['GET', 'POST'],
};
app.use(cors(corsOptions));
app.use(express.json());

async function requireAuth(req, res, next) {
  const authorization = req.header('authorization') ?? '';
  const match = authorization.match(/^Bearer (.+)$/i);
  if (!match) {
    return res.status(401).json({ error: 'Authentication required.' });
  }
  try {
    req.user = await admin.auth().verifyIdToken(match[1], true);
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid or expired authentication token.' });
  }
}

const analysisLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5, // 5 requests per IP per minute
  message: { error: 'Too many requests. Please wait.' },
  standardHeaders: true,
  legacyHeaders: false,
});

const healthLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
});

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
app.get('/api/health', healthLimiter, (req, res) => {
  res.json({ status: 'ok' });
});

// ── Attendance Analysis Endpoint (Web) ────────────────────────────────────────
app.post('/api/analyze-attendance', analysisLimiter, requireAuth, (req, res, next) => {
  upload.single('report')(req, res, function (err) {
    if (err) {
      console.error("Multer Error:", err);
      return res.status(400).json({ success: false, error: 'File Upload Error.' });
    }
    next();
  });
}, async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No PDF file provided under the "report" field.' });
    }

    const detected = await fileTypeFromBuffer(req.file.buffer);
    if (!detected || detected.mime !== 'application/pdf') {
      return res.status(400).json({ success: false, error: 'Invalid file format. Only real PDFs accepted.' });
    }
    if (req.file.buffer.slice(0, 4).toString() !== '%PDF') {
      return res.status(400).json({ success: false, error: 'Invalid PDF header.' });
    }

    console.log(`Received authenticated PDF upload (${req.file.size} bytes)`);

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
        mimeType: 'application/pdf',
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


// ── Global Error Handler ──────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error("Critical Server Error:", err);
  res.status(500).json({ success: false, error: 'An internal error occurred.' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
