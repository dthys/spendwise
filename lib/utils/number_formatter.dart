import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class NumberFormatter {
  // EU locale formatter (uses comma for decimal separator)
  static final NumberFormat _euCurrencyFormat = NumberFormat.currency(
    locale: 'nl_NL', // Dutch locale for EU formatting
    symbol: '€',
    decimalDigits: 2,
  );

  static final NumberFormat _euDecimalFormat = NumberFormat.decimalPattern('nl_NL');

  static final NumberFormat _euPercentageFormat = NumberFormat.percentPattern('nl_NL');

  /// Format currency amount for display (e.g., "€ 12,34")
  static String formatCurrency(double amount, {String? currencySymbol}) {
    if (currencySymbol != null && currencySymbol != '€') {
      // For non-Euro currencies, create custom formatter
      final customFormat = NumberFormat.currency(
        locale: 'nl_NL',
        symbol: currencySymbol,
        decimalDigits: 2,
      );
      return customFormat.format(amount);
    }
    return _euCurrencyFormat.format(amount);
  }

  /// Format decimal number for display (e.g., "12,34")
  static String formatDecimal(double number, {int? decimalPlaces}) {
    if (decimalPlaces != null) {
      final customFormat = NumberFormat.decimalPattern('nl_NL');
      customFormat.minimumFractionDigits = decimalPlaces;
      customFormat.maximumFractionDigits = decimalPlaces;
      return customFormat.format(number);
    }
    return _euDecimalFormat.format(number);
  }

  /// Format percentage for display (e.g., "12,5%")
  static String formatPercentage(double percentage) {
    return _euPercentageFormat.format(percentage / 100);
  }

  /// Parse EU formatted string to double (handles comma as decimal separator)
  static double? parseEuNumber(String input) {
    if (input.trim().isEmpty) return null;

    try {
      // Remove currency symbols and spaces
      String cleaned = input
          .replaceAll(RegExp(r'[€$£¥]'), '')
          .replaceAll(' ', '')
          .trim();

      // Handle EU format: replace comma with dot for parsing
      if (cleaned.contains(',') && !cleaned.contains('.')) {
        // Simple case: only comma (e.g., "12,34")
        cleaned = cleaned.replaceAll(',', '.');
      } else if (cleaned.contains('.') && cleaned.contains(',')) {
        // Complex case: both dot and comma (e.g., "1.234,56")
        // In EU format, dot is thousands separator, comma is decimal
        List<String> parts = cleaned.split(',');
        if (parts.length == 2) {
          String integerPart = parts[0].replaceAll('.', '');
          String decimalPart = parts[1];
          cleaned = '$integerPart.$decimalPart';
        }
      }

      return double.parse(cleaned);
    } catch (e) {
      return null;
    }
  }

  /// Create TextInputFormatter for EU number input
  static TextInputFormatter createEuNumberInputFormatter({bool allowDecimals = true}) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.isEmpty) return newValue;

      // Allow only digits, comma (for decimal), and dot (for thousands in display)
      final RegExp regex = allowDecimals
          ? RegExp(r'^[0-9]*,?[0-9]*$')
          : RegExp(r'^[0-9]*$');

      if (regex.hasMatch(newValue.text)) {
        return newValue;
      }

      return oldValue;
    });
  }
}