# AGENTS.md

## Project Overview

Flutter AI roleplay chat app (`flutter_chat_demo`). Offline-first, single-device. LLM calls via HTTP to self-configured base URL + API Key. Local storage only — no cloud, no contact uploads.

## Requirements

- Flutter SDK 3.136+, Dart 3.4+
- Android minSdk 26, Java 17

## Commands

```bash
# Pull dependencies
flutter pub get

# Debug run (device/emulator required)
flutter run

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Run tests
flutter test

# Analyze (lint)
flutter analyze
```

## Architecture

Single-feature app: `features/chat/`. Clean architecture layers:

- `lib/main.dart`, `app.dart` — entry point
- `lib/features/chat/domain/providers/chat_provider.dart` — core state machine (~2500 lines). This is the main file to understand or modify.
- `lib/features/chat/domain/services/` — heartbeat, input formatter
- `lib/features/chat/data/models/` — `contact.dart` (with eventGraph), `message.dart`
- `lib/features/chat/data/repositories/chat_repository.dart`
- `lib/features/chat/data/datasources/chat_local_storage.dart` — SharedPreferences
- `lib/features/chat/presentation/pages/chat_page.dart` — main chat UI
- `lib/features/chat/presentation/widgets/` — contact sidebar, contact editor dialog
- `lib/core/utils/structured_input_prompt_composer.dart` — prompt assembly
- `lib/core/utils/structured_output_regex_parser.dart` — JSON extraction from LLM
- `lib/core/utils/chinese_tokenizer_service.dart` — jieba Chinese tokenizer
- `lib/infrastructure/services/ai_service.dart` — LLM HTTP client
- `lib/infrastructure/services/opencode_service.dart` — opencode bridge

## Three Contact Types

| Type | category | Engine | Path |
|---|---|---|---|
| Character | `ContactCategory.contact` | LLM + structured memory | `sendMessage` → `AiService` → event graph |
| Story | `ContactCategory.story` | LLM + structured memory (different schema) | Same as contact, `_buildJsonFormat(isStory: true)` |
| Assistant | `ContactCategory.assistant` | opencode bridge | `_sendAssistantMessage` → `OpencodeService` |

## Data Storage

All in SharedPreferences (no database):

- `chat_contacts_v1` — contacts with eventGraph
- `chat_messages_v1` — message history
- `chat_settings_v1` — agent settings (API key, system prompt, base URL, model)
- `app_settings_v1` — app settings (20 items)
- `opencode_connection_v1` — opencode connection config

Android debug: `adb pull /data/data/<package>/shared_prefs/`

## Testing

Test files:
- `test/widget_test.dart` — smoke test for ChatPage
- `test/unit/` — unit tests for core utilities and models
- `test/integration/` — integration tests for UI pages

Run with `flutter test`. CI workflow at `.github/workflows/ci.yml`.

## Lint Config

`analysis_options.yaml` includes `flutter_lints/flutter.yaml`. `avoid_print: false` — print statements allowed for debugging.

## Known Gotchas

- opencode `POST /session/:id/message` is synchronous — long AI tasks (>300s) may timeout.
- SSH mode in `OpencodeService._executeViaSsh` is a placeholder; only HTTP is supported.
- `legacy events: EventLruBucket` is still written but prompt only reads `eventGraph`.

## Code Conventions

- No `opencode.json`, `.cursorrules`, or other instruction files exist.
- Chinese comments and UI text throughout.
- Print-based debugging is standard practice in this codebase.
- No code generation or build scripts beyond standard Flutter toolchain.
