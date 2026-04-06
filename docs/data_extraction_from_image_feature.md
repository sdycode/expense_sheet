You are working on an existing Flutter Android expense manager app that syncs with Google Sheets. Your task is to add a new AI-powered transaction extractor feature using a local LLM (moondream2 GGUF model).
CRITICAL RULE: Do NOT touch, modify, or refactor any existing files, screens, models, providers, or services. Only create new files in new dedicated folders.

Feature Overview
Add a new section/screen called "AI Extract" (or "Smart Import") that allows users to:

Pick the local moondream2 GGUF model files once (persisted)
Pick one or multiple payment screenshot images
Run AI extraction on those images
Review extracted transactions in the app's existing expense data format
Confirm and save them


Data Format
Every extracted transaction must conform to this exact model:
dart{
  "id": "",                          // leave empty, generated later
  "label": "Groceries",             // merchant name or description
  "price": "500",                   // amount as string, no currency symbol
  "category": "Food",               // from fixed category list below
  "note": "Weekly shopping",        // any extra context from image
  "expenseDate": "2026-04-05",      // date from transaction, format: yyyy-MM-dd
  "timestamp": "2026-04-05T18:19:26.000Z", // ISO8601
  "paidBy": "Shubham",             // leave as default user, configurable
  "isOneTimePurchase": false,       // default false
  "addedByEmail": "user@gmail.com", // from app's current logged in user
  "linkedHomeSpreadsheetId": ""     // leave empty
}

Fixed Category List
Use exactly these categories for classification:
dartconst List<String> kAICategories = [
  "Food",
  "Grocery & Essential",
  "Health & Wellness",
  "Transport",
  "Shopping",
  "Entertainment",
  "Utilities",
  "Education",
  "Travel",
  "Recharge & Bills",
  "Transfer",
  "Other",
];

Folder Structure
Create everything inside:
lib/
  features/
    ai_extractor/
      screens/
        ai_extractor_screen.dart       // main screen
        ai_model_setup_screen.dart     // one-time model file picker
        ai_results_screen.dart         // review extracted results
      widgets/
        image_picker_grid.dart         // multi image picker UI
        extracted_card.dart            // single transaction preview card
        model_status_bar.dart          // shows model loaded/not loaded
      services/
        llm_service.dart               // llama.cpp bridge + inference
        extraction_parser.dart         // parse LLM output → ExpenseModel
      models/
        ai_extraction_result.dart      // temporary model for extracted data
      providers/
        ai_extractor_provider.dart     // state management
      constants/
        ai_prompts.dart                // all prompts
        ai_categories.dart             // category list

Model Setup (One-Time)

On first use, show ai_model_setup_screen.dart
User picks 2 files:

Text model: moondream2-text-model-f16.gguf
Vision projector: moondream2-mmproj-f16.gguf


Save both paths using shared_preferences under keys:

ai_model_text_path
ai_model_mmproj_path


Show green checkmark once both are set
Allow re-picking from Settings


LLM Service (llm_service.dart)

Use flutter_llama_cpp or fllama package (whichever is available and supports multimodal/vision GGUF on Android)
Load model from saved paths
Accept: image file path + prompt string
Return: raw string response from model
Handle errors gracefully (model not loaded, inference failed, etc.)
Unload model when screen is disposed to free RAM


Default Extraction Prompt (ai_prompts.dart)
dartconst String kDefaultExtractionPrompt = """
You are a financial data extraction assistant. 
Analyze this payment/transaction screenshot carefully.

Extract ALL visible transactions and return ONLY a valid JSON array.
No explanation, no markdown, no code blocks. Just raw JSON array.

Each transaction object must have exactly these fields:
- label: merchant name or payment description (string)
- price: amount as number only, no currency symbols (string)
- category: one of [Food, Grocery & Essential, Health & Wellness, Transport, Shopping, Entertainment, Utilities, Education, Travel, Recharge & Bills, Transfer, Other]
- note: any additional context like payment app used, transaction ID snippet (string)
- expenseDate: date in yyyy-MM-dd format (string)
- expenseTime: time in HH:mm:ss format if visible, else "00:00:00" (string)

Rules:
- If multiple transactions visible, extract ALL of them
- If amount is unclear, put "0"
- If date is unclear, use today's date
- For UPI transfers to people (not merchants), use category "Transfer"
- For grocery apps like Zepto, Blinkit, use "Grocery & Essential"
- For medical/diagnostic payments, use "Health & Wellness"
- For transport like RedBus, Ola, Uber, use "Transport"
- Return [] if no transactions found

Example output:
[
  {
    "label": "Zepto",
    "price": "302",
    "category": "Grocery & Essential", 
    "note": "Quick commerce grocery delivery",
    "expenseDate": "2026-01-26",
    "expenseTime": "21:06:00"
  }
]
""";

Main Screen Flow (ai_extractor_screen.dart)
AI Extractor Screen
│
├── Top: ModelStatusBar (green = ready, red = not configured)
│
├── [+ Add Images] button → multi image picker (image_picker package)
│
├── Image grid showing selected images with remove option
│
├── Additional prompt TextField (optional, appended to default prompt)
│   placeholder: "e.g. Focus only on March transactions"
│
├── [Extract Transactions] button
│   → shows loading with per-image progress
│   → runs LLM on each image sequentially
│
└── On success → navigate to ai_results_screen.dart

Results Screen (ai_results_screen.dart)
Results Screen
│
├── List of ExtractedCards (one per transaction)
│   Each card shows:
│   - Label, Amount, Category (editable)
│   - Date (editable with date picker)
│   - Note (editable)
│   - Toggle: include/exclude this transaction
│
├── [Select All] / [Deselect All]
│
└── [Save Selected] button
    → converts to app's existing ExpenseModel format
    → calls existing save/add expense logic (read it, don't modify it)
    → shows success snackbar
    → pops back

Extraction Parser (extraction_parser.dart)

Take raw LLM string output
Strip any markdown if present (```json etc.)
Parse JSON array
Map each item to AIExtractionResult
Then convert AIExtractionResult → existing ExpenseModel (or equivalent)
Fill in: id = "", paidBy = currentUser, isOneTimePurchase = false, addedByEmail = currentUserEmail, linkedHomeSpreadsheetId = ""
Handle malformed JSON gracefully — skip bad entries, log error


State Management (ai_extractor_provider.dart)
Track these states:
dartenum AIExtractorStatus {
  idle,
  modelLoading,
  extracting,
  done,
  error,
}

class AIExtractorState {
  AIExtractorStatus status;
  List<File> selectedImages;
  List<AIExtractionResult> results;
  String? errorMessage;
  int currentImageIndex;      // for progress: "Processing 2 of 5"
  int totalImages;
}

Packages to Add
Add these to pubspec.yaml — do not remove any existing packages:
yaml# AI Extractor feature
fllama: ^latest          # or flutter_llama_cpp — check which supports Android vision GGUF
image_picker: ^latest    # if not already present
file_picker: ^latest     # for picking .gguf model files
shared_preferences: ^latest  # if not already present
path_provider: ^latest   # if not already present

Entry Point

Add a new route/navigation entry for AIExtractorScreen
Add a button or menu item in the existing app's navigation (home screen FAB, drawer, or bottom nav) that opens this screen
Do this by finding the navigation widget and only adding a new item, not modifying existing ones


Android Permissions
Add to AndroidManifest.xml (only add, don't change existing):
xml<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>

Important Constraints

Do NOT modify any existing expense model, provider, service, or screen
Do NOT change routing logic — only add new routes
Do NOT change theme or styling — match existing app theme by reading it
All new code is self-contained in lib/features/ai_extractor/
Read the existing expense save method and call it as-is from results screen
If image_picker or shared_preferences already exist in pubspec, don't duplicate