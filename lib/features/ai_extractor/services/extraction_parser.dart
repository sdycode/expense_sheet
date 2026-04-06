import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ai_extraction_result.dart';

/// Parses raw LLM output into [AIExtractionResult] objects.
class ExtractionParser {
  /// Parse the raw string returned by the LLM into a list of results.
  ///
  /// Handles common issues:
  /// - Strips markdown code fences (```json ... ```)
  /// - Handles extra text before/after the JSON array
  /// - Skips individual malformed entries without failing entirely
  static List<AIExtractionResult> parse(String rawOutput) {
    final cleaned = _stripMarkdown(rawOutput);
    final jsonStr = _extractJsonArray(cleaned);

    if (jsonStr == null || jsonStr.isEmpty) {
      debugPrint('ExtractionParser: No JSON array found in output');
      return [];
    }

    try {
      final decoded = json.decode(jsonStr);
      if (decoded is! List) {
        debugPrint('ExtractionParser: Decoded value is not a list');
        return [];
      }

      final results = <AIExtractionResult>[];
      for (int i = 0; i < decoded.length; i++) {
        try {
          if (decoded[i] is Map<String, dynamic>) {
            results.add(AIExtractionResult.fromJson(decoded[i]));
          } else {
            debugPrint('ExtractionParser: Skipping non-map entry at index $i');
          }
        } catch (e) {
          debugPrint('ExtractionParser: Skipping malformed entry $i: $e');
        }
      }
      return results;
    } catch (e) {
      debugPrint('ExtractionParser: JSON decode error: $e');
      return [];
    }
  }

  /// Strip markdown code fences if present.
  static String _stripMarkdown(String input) {
    String s = input.trim();

    // Remove ```json ... ``` or ``` ... ```
    final fencePattern = RegExp(
      r'```(?:json)?\s*\n?(.*?)\n?\s*```',
      dotAll: true,
    );
    final match = fencePattern.firstMatch(s);
    if (match != null) {
      s = match.group(1)?.trim() ?? s;
    }

    return s;
  }

  /// Find the first JSON array in the string (between `[` and the matching `]`).
  static String? _extractJsonArray(String input) {
    final startIdx = input.indexOf('[');
    if (startIdx == -1) return null;

    int depth = 0;
    for (int i = startIdx; i < input.length; i++) {
      if (input[i] == '[') {
        depth++;
      } else if (input[i] == ']') {
        depth--;
        if (depth == 0) {
          return input.substring(startIdx, i + 1);
        }
      }
    }

    // If we didn't find a matching bracket, try with what we have.
    return input.substring(startIdx);
  }
}
