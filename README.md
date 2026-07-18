<div align="center">
  <h1>AttendEase</h1>
  <img src="assets/icon/app_icon2.png" alt="Attend Ease Logo" width="120" height="120" /><br /><br />
<a href="https://github.com/PaRth0566/AttendEase/releases/download/v1.0.3/AttendEase.apk"><img src="https://img.shields.io/badge/Download-APK-2D80EC?logo=android" width="226" ></a> &nbsp&nbsp&nbsp&nbsp
<a href="https://attendease-cbc6f.web.app"><img src="https://img.shields.io/badge/Open_Web-APP-ff9a00?logo=firebase&logoColor=FFCA28" width="230"></a><br><br>
<a href="https://github.com/neo999in/AttendEase-backend"><img src="https://img.shields.io/badge/Backend-Repository-339933?logo=nodedotjs" width="180" ></a><br>
</div>

---
### 📖 Description

<img src="assets/cover.png" alt="Attend Ease Cover" width="100%" />


**AttendEase** is an attendance management system designed to streamline how students track and analyze their academic presence. By leveraging the power of Google's Gemini, Attend Ease automates the tedious task of manual entry by extracting structured data directly from PDF attendance reports. It provides a premium, intuitive dashboard that offers deep insights, trend analysis, and predictive metrics to help users stay ahead of their attendance requirements.

> [!IMPORTANT]
> **Disclaimer**: AttendEase is an automated tool. We are not liable for any calculation inaccuracies or resulting consequences. Please verify your attendance with official college records.
>
> **Privacy Note**: AttendEase handles sensitive PDF data securely. The Node.js backend acts as a secure bridge, ensuring your AI processing remains private.


---

### 📸 Screenshots
<div align="center">
  <img src="assets/screenshots.png" alt="App Screenshots" width="100%" />
</div>
  
---

### ✨ Features
- 🤖 **AI-Powered PDF Ingestion**: Seamlessly extract attendance records from PDF documents using Gemini multimodal capabilities.
- 📄 **Local PDF Parser**: High-performance client-side PDF parsing to extract attendance data locally for rapid processing and offline support.
- 📊 **Intelligent Insights**: Dynamic analysis of attendance patterns with AI-driven predictions and actionable summaries.
- 📅 **Smart Calendar**: Integrated dashboard to visualize historical attendance and manage daily schedules efficiently.
- 🔔 **Target Monitoring**: Set attendance goals and receive smart notifications to ensure you never fall below required thresholds.
- 📱 **Cross-Platform Sync**: Truly unified experience across Android and Web with real-time Firebase Cloud Firestore synchronization.
- 🔐 **Secure Backend**: Dedicated Node.js proxy to handle AI requests safely, keeping your environment keys protected.
- 🎨 **Premium UI/UX**: A modern, card-based interface and dynamic progress indicators.

---

### 🛠 Requirements
Before you begin, ensure you have met the following requirements:
* **Flutter SDK**: `^3.10.7` or higher.
* **Dart SDK**: Compatible with the Flutter version.
* **Node.js**: `v16.0.0` or higher (for backend services).
* **IDE**: [Android Studio](https://developer.android.com/studio) or [VS Code](https://code.visualstudio.com/) with Flutter/Dart plugins.
* **Platform**: 
    - **Android**: SDK 21 (Android 5.0) or higher.
    - **Web**: Modern browser with JavaScript enabled.

---

### 🛠 Tech Stack
<a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-00CCFF?labelColor=333333&logo=Flutter&logoColor=00CCFF" height="30" width="106" align="left"></a>
<a href="https://dart.dev/"><img src="https://img.shields.io/badge/Dart-40C4FF?labelColor=333333&logo=Dart&logoColor=40C4FF" height="30" width="88" align="left"></a>
<a href="https://ai.google.dev/"><img src="https://img.shields.io/badge/Google_AI_Studio-8E75FF?labelColor=333333&logo=GoogleGemini&logoColor=8E75FF" height="30" width="190"></a>  
<a href="https://firebase.google.com/"><img src="https://img.shields.io/badge/Firebase-FFCA28?labelColor=333333&logo=Firebase&logoColor=FFCA28" height="30" width="120" align="left"></a>
<a href="https://nodejs.org/"><img src="https://img.shields.io/badge/Node.js-339933?labelColor=333333&logo=nodedotjs&logoColor=339933" height="30" width="112" align="left"></a>
<a href="https://www.sqlite.org/"><img src="https://img.shields.io/badge/SQLite-007FFF?labelColor=333333&logo=SQLite&logoColor=007FFF" height="30" width="103" align="left"></a>
<a href="https://render.com/"><img src="https://img.shields.io/badge/Render-7B2BF9?labelColor=333333&logo=render&logoColor=7B2BF9" height="30" width="109" ></a>

- **Key Packages**:
  - `syncfusion_flutter_pdf` (PDF Processing)
  - `table_calendar` (Calendar Integration)
  - `firebase_auth` & `google_sign_in` (Authentication)
  - `sqflite` (Local Persistence)
  - `flutter_local_notifications` (Push Notifications)

---

### 📂 Folder Structure
```text
AttendEase/
├── lib/               # Core Flutter application source files
│   ├── screens/       # Feature-specific UI components
│   ├── database/      # SQLite & Local DB management
│   ├── services/      # Firebase & API integration logic
│   └── router/        # GoRouter navigation configuration
├── backend/           # Node.js Express server for Gemini AI
└── assets/            # App icons, images, and static resources
```
---
### 📄 License

Released under the <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" height="20" align="center"></a>
