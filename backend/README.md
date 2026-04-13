# AttendEase AI Backend

This is the secure Node.js backend designed to handle PDF ingestion for the AttendEase Flutter Web Application. It uses Google's natively multimodal `gemini-1.5-pro` model to extract attendance data and insights from PDF reports directly.

## Why a Backend?
If you put your Google Gemini API key directly into your Flutter Web app, it will be exposed to anyone who visits your website through the browser inspector. This backend safely proxies the request, meaning your keys are kept secret while the frontend just talks to this server.

## Getting Started Locally

1. Install dependencies:
   ```bash
   npm install
   ```

2. Duplicate the `.env.example` file and rename it to `.env`.
3. Paste your actual Gemini API key inside the new `.env` file. Do NOT commit the `.env` file to Github.
4. Start the development server:
   ```bash
   npm run dev
   ```
5. Your server is now running on `http://localhost:3000`.

## Hosting

You can deploy this folder directly to any Node hosting provider (e.g. Render, Railway, DigitalOcean App Platform). 
Make sure to go into your hosting dashboard's settings and inject `GEMINI_API_KEY` into their Environment Variables section!
