import 'package:flutter/material.dart';
import '../constants/ai_categories.dart';
import '../models/ai_extraction_result.dart';

/// Card showing a single extracted transaction with editable fields.
class ExtractedCard extends StatelessWidget {
  final AIExtractionResult result;
  final int index;
  final VoidCallback onToggle;
  final VoidCallback onChanged;

  const ExtractedCard({
    super.key,
    required this.result,
    required this.index,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimmed = !result.isSelected;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dimmed ? 0.50 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: index + toggle ──
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Switch.adaptive(
                    value: result.isSelected,
                    onChanged: (_) => onToggle(),
                  ),
                ],
              ),

              const Divider(height: 14),

              // ── Label ──
              _EditableField(
                label: 'Label',
                initialValue: result.label,
                onChanged: (v) {
                  result.label = v;
                  onChanged();
                },
              ),

              const SizedBox(height: 8),

              // ── Amount + Category row ──
              Row(
                children: [
                  Expanded(
                    child: _EditableField(
                      label: 'Amount',
                      initialValue: result.price,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        result.price = v;
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: kAICategories.contains(result.category)
                          ? result.category
                          : 'Other',
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      isExpanded: true,
                      items: kAICategories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          result.category = v;
                          onChanged();
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Date ──
              _DateField(
                label: 'Date',
                value: result.expenseDate,
                onChanged: (v) {
                  result.expenseDate = v;
                  onChanged();
                },
              ),

              const SizedBox(height: 8),

              // ── Note ──
              _EditableField(
                label: 'Note',
                initialValue: result.note,
                onChanged: (v) {
                  result.note = v;
                  onChanged();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

class _EditableField extends StatelessWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final TextInputType keyboardType;

  const _EditableField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      onChanged: onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value; // yyyy-MM-dd
  final ValueChanged<String> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        DateTime initial;
        try {
          initial = DateTime.parse(value);
        } catch (_) {
          initial = DateTime.now();
        }

        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) {
          final formatted =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          onChanged(formatted);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
