# AttendEase Backend 🚀

This is a secure Node.js proxy server designed to handle sensitive AI processing for the **Attend Ease** application. It acts as a bridge between the Flutter frontend and Google Gemini.

## 🛠 Features
- 🔒 **Secure API Proxy**: Keeps Gemini API keys hidden from the client side.
- 🤖 **AI PDF Ingestion**: Processes attendance reports using Google's multimodal Gemini models.
- 🔄 **Smart Fallback**: Automatically switches between multiple Gemini models if one is overloaded.
- 🚀 **Fast & Lightweight**: Built with Express.js for rapid response times.

## 🚀 Getting Started

### 1. Install Dependencies
```bash
npm install
```


### 3. Run the Server
```bash
# Development mode
npm run dev

# Production mode
npm start
```

## 📡 API Endpoints

### `POST /api/analyze-attendance`
Extracts structured attendance data from a PDF report.
- **Body**: `multipart/form-data`
- **Field**: `report` (PDF file)
- **Response**: JSON object containing student metadata and subject-wise counts.

