# Mobile RAG Flutter

A cross-platform mobile application for Retrieval-Augmented Generation (RAG) powered AI assistant. Build your personal knowledge base and chat with your documents using local storage and OpenAI-compatible APIs.

## Features

### 💬 Chat Interface
- Conversational AI assistant with streaming responses
- Support for multiple chat models (OpenAI-compatible)
- Conversation history management
- Export conversations to text files
- Attachment support for file analysis
- Custom prompt templates

### 📚 Knowledge Base Management
- Create and manage multiple knowledge bases
- Upload documents in various formats:
  - Text files (`.txt`, `.md`)
  - Spreadsheets (`.csv`, `.xls`, `.xlsx`)
  - Documents (`.doc`, `.docx`)
  - PDF files (`.pdf`)
- Configurable text chunking strategies:
  - Min/max chunk size
  - Chunk overlap
  - Custom separators
- Document chunk visualization and management
- Embedding model support for vector search

### 🔍 RAG Pipeline
- Real-time RAG flow visualization
- Query embedding for semantic search
- Configurable retrieval strategies:
  - Hybrid mode (chunks + documents)
  - Chunks only
  - Documents only
- Similarity threshold and Top-K configuration
- Evidence display with hit rate and similarity scores

### ⚙️ Settings & Configuration
- **Chat Models**: Configure OpenAI-compatible chat endpoints, API keys, and model IDs
- **Embedding Models**: Configure embedding endpoints and model IDs
- **Prompt Templates**: Create and manage custom system prompts
- **Retrieval Strategy**: Fine-tune search parameters and weights
- **Advanced Options**: Temperature, Top P, Max Tokens, penalties
- **Security**: Encrypted API key storage

### 🌍 Multi-Language Support
- English (en)
- Chinese Simplified (zh-CN)
- Automatic locale detection
- Switchable language preference

### 📱 Cross-Platform
- Android
- iOS
- Linux
- macOS
- Windows
- Web

## Tech Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Routing**: go_router
- **Database**: Drift (SQLite)
- **HTTP**: Dio
- **UI**: Material Design 3
- **Markdown**: flutter_markdown_plus
- **File Processing**: 
  - PDF: syncfusion_flutter_pdf
  - Excel: excel
  - CSV: csv
  - XML: xml
  - Archive: archive
- **Encryption**: encrypt

## Getting Started

### Prerequisites

- Flutter SDK 3.10.4 or higher
- Dart SDK 3.10.4 or higher
- An OpenAI-compatible API endpoint for chat and embeddings

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd mobile_rag_flutter
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
# For Android
flutter run

# For iOS
flutter run

# For Web
flutter run -d chrome

# For desktop platforms
flutter run -d linux
flutter run -d macos
flutter run -d windows
```

### Configuration

1. Open the app and navigate to **Settings**
2. Configure your **Chat Model**:
   - Base URL (e.g., `https://api.openai.com/v1`)
   - API Key (optional)
   - Add model IDs (e.g., `gpt-4`, `gpt-3.5-turbo`)
3. Configure your **Embedding Model**:
   - Base URL (e.g., `https://api.openai.com/v1`)
   - API Key (optional)
   - Add embedding model IDs (e.g., `text-embedding-3-small`)
4. Test connections to verify configuration

### Creating a Knowledge Base

1. Navigate to **Knowledge** tab
2. Tap **New knowledge base**
3. Enter name and description
4. Configure chunking settings (optional)
5. Upload documents
6. Select an embedding model
7. Wait for embedding to complete

### Chatting with Your Knowledge

1. Navigate to **Chat** tab
2. Toggle **Knowledge** to enable RAG
3. Select knowledge bases to search
4. Choose a chat model and prompt template
5. Ask questions about your documents
6. View evidence and RAG flow visualization

## Project Structure

```
lib/
├── app.dart                    # App configuration and routing
├── app_providers.dart          # Global providers
├── main.dart                   # Entry point
├── core/
│   ├── app_theme.dart         # Theme configuration
│   ├── i18n.dart              # Internationalization
│   └── locale_controller.dart # Locale management
├── data/
│   └── database/              # Drift database setup
├── domain/
│   └── models.dart           # Domain models
├── features/
│   ├── chat/                 # Chat feature
│   ├── knowledge/            # Knowledge base feature
│   └── settings/             # Settings feature
├── services/                 # Business logic services
│   ├── api_service.dart
│   ├── db_service.dart
│   ├── rag_service.dart
│   └── storage_service.dart
├── utils/                    # Utility functions
└── widgets/                  # Reusable widgets
```

## Development

### Code Generation

```bash
# Generate Drift database code
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running Tests

```bash
flutter test
```

### Building for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter team for the amazing framework
- OpenAI for the API standards
- All contributors and users of this project
