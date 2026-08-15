import 'package:flutter/services.dart';

/// Keeps a text field to a whole percentage: digits only, 0–100.
///
/// Both rules are enforced as the user types rather than at submit time, so an
/// invalid value can never appear in the field at all — a rejected keystroke
/// leaves the text and the caret exactly as they were.
///
/// `FilteringTextInputFormatter.digitsOnly` alone is not enough: it accepts
/// "999", and on web a paste or a physical keyboard can deliver characters that
/// `TextInputType.number` (a soft-keyboard *hint*, not a constraint) never
/// filters.
///
/// This lives outside the web screen so it can be unit-tested — that file
/// imports `dart:js_interop`, which does not compile on the VM test runner.
class PercentInputFormatter extends TextInputFormatter {
  const PercentInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Empty is allowed while typing — the field is mid-edit, not invalid, and
    // a user backspacing to retype would otherwise be stuck on the last
    // character. Callers fall back to a default when parsing.
    if (text.isEmpty) return newValue;

    // Any non-digit (including '-', '.', 'e' and pasted letters) is rejected.
    if (!RegExp(r'^\d+$').hasMatch(text)) return oldValue;

    // Reject rather than clamp: silently rewriting "1000" to "100" as the user
    // types a longer number is more surprising than the keystroke not landing.
    final value = int.tryParse(text);
    if (value == null || value > 100) return oldValue;

    return newValue;
  }
}
