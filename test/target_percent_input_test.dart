// Regression tests for the target percentage fields on the web upload screen.
//
// These cover input rules that previously let an impossible threshold reach the
// report. `TextInputType.number` only hints which soft keyboard to show — it
// does not constrain a physical keyboard or a paste — so before the formatter
// existed the fields accepted "abc", "-5", "7.5" and "999" as attendance
// targets.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/utils/percent_input_formatter.dart';

void main() {
  const formatter = PercentInputFormatter();

  /// Types [input] one character at a time, starting from [start].
  ///
  /// A formatter sees each keystroke as its own edit, so appending "9" to "10"
  /// is a different call than pasting "109" wholesale — typing is the case the
  /// user actually hits. Returns the text left in the field.
  String type(String input, {String start = ''}) {
    var value = TextEditingValue(
      text: start,
      selection: TextSelection.collapsed(offset: start.length),
    );
    for (final ch in input.split('')) {
      final next = TextEditingValue(
        text: value.text + ch,
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      );
      value = formatter.formatEditUpdate(value, next);
    }
    return value.text;
  }

  /// A single edit replacing the whole field, as a paste does.
  String paste(String text, {String start = '75'}) {
    final old = TextEditingValue(
      text: start,
      selection: TextSelection.collapsed(offset: start.length),
    );
    return formatter
        .formatEditUpdate(
          old,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        )
        .text;
  }

  group('typing', () {
    test('letters and symbols never register', () {
      expect(type('abc'), '');
      expect(type(r'!@#$%'), '');
      // A negative sign cannot start a value, so '-5' keeps only the digit.
      expect(type('-5'), '5');
    });

    test('a decimal point is rejected, digits around it survive', () {
      // '7', then '.' bounces, then '5' appends -> '75', never '7.5'.
      expect(type('7.5'), '75');
    });

    test('100 is allowed but anything above it is not', () {
      expect(type('100'), '100');
      // The trailing '1' would make 1001; it is dropped, leaving 100.
      expect(type('1001'), '100');
      // 101 exceeds the ceiling on the final keystroke, so it stays at 10.
      expect(type('101'), '10');
      // '9' then '99' are both in range; the third digit would make 999, so it
      // is the only keystroke rejected.
      expect(type('999'), '99');
    });

    test('ordinary values pass through unchanged', () {
      expect(type('75'), '75');
      expect(type('70'), '70');
      expect(type('0'), '0');
    });

    test('a digit appended to an existing value is bounded', () {
      // 75 -> 750 would be out of range, so the keystroke does not land.
      expect(type('0', start: '75'), '75');
      // 1 -> 10 is fine.
      expect(type('0', start: '1'), '10');
    });
  });

  group('pasting', () {
    test('an out-of-range or non-numeric paste leaves the field untouched', () {
      expect(paste('999'), '75');
      expect(paste('-20'), '75');
      expect(paste('80.5'), '75');
      expect(paste('abc'), '75');
      expect(paste('1e2'), '75');
    });

    test('an in-range paste replaces the value', () {
      expect(paste('90'), '90');
      expect(paste('100'), '100');
      expect(paste('0'), '0');
    });
  });

  test('the field may be emptied while editing', () {
    // Clearing must be allowed — a user backspacing to retype would otherwise
    // be stuck on the last character.
    expect(paste(''), '');
  });
}
