import 'package:flutter/foundation.dart';

// Gate for dev-only UI: HF token field, raw model IDs, file paths, dev screen.
// Release builds always see false. In debug, flip the trailing `&& true` to
// preview the production experience without a release build.
const bool devMode = kDebugMode && true;
