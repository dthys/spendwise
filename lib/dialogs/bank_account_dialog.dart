import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/banking_service.dart';

class BankAccountDialog {

  static Future<String?> showAddBankAccountDialog(
      BuildContext context, {
        String? currentIBAN,
      }) async {
    final ibanController = TextEditingController(text: currentIBAN ?? '');
    final formKey = GlobalKey<FormState>();
    bool isValidating = false;
    String? validationResult;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.account_balance, color: Colors.blue.shade500),
              const SizedBox(width: 8),
              Expanded( // This fixes the overflow
                child: Text(
                  currentIBAN == null ? 'Bank account' : 'Bank account',
                  overflow: TextOverflow.ellipsis, // Handle very long text gracefully
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fill in your bank account to make direct payments possible',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: ibanController,
                      decoration: InputDecoration(
                        labelText: 'IBAN',
                        hintText: 'BE68 5390 0754 7034',
                        prefixIcon: const Icon(Icons.account_balance),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        helperText: 'Format: BE68 5390 0754 7034',
                      ),
                      inputFormatters: [
                        UpperCaseTextFormatter(), // Apply uppercase first
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\s]')), // Then filter
                        IBANFormatter(), // Finally format with spaces
                      ],
                      onChanged: (value) {
                        setState(() {
                          validationResult = null;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Fill in an IBAN number';
                        }

                        String cleanIBAN = value.replaceAll(' ', '');
                        if (cleanIBAN.length < 15) {
                          return 'IBAN is too short';
                        }

                        if (!BankingService.validateIBAN(cleanIBAN)) {
                          return 'Invalid IBAN number';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Validation result
                    if (validationResult != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: validationResult!.startsWith('✅')
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: validationResult!.startsWith('✅')
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              validationResult!.startsWith('✅')
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: validationResult!.startsWith('✅')
                                  ? Colors.green.shade600
                                  : Colors.red.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                validationResult!,
                                style: TextStyle(
                                  color: validationResult!.startsWith('✅')
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Validate button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isValidating ? null : () async {
                          String iban = ibanController.text.replaceAll(' ', '');
                          if (iban.length >= 15) {
                            setState(() {
                              isValidating = true;
                            });

                            await Future.delayed(const Duration(milliseconds: 500)); // Simulate validation

                            if (BankingService.validateIBAN(iban)) {
                              String country = BankingService.getCountryFromIBAN(iban);
                              setState(() {
                                validationResult = '✅ Geldig IBAN nummer uit $country';
                                isValidating = false;
                              });
                            } else {
                              setState(() {
                                validationResult = '❌ Ongeldig IBAN nummer';
                                isValidating = false;
                              });
                            }
                          }
                        },
                        icon: isValidating
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.verified),
                        label: Text(isValidating ? 'Validating...' : 'Validate IBAN'),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your IBAN is stored securely and only used for payments within your groups.',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  String cleanIBAN = ibanController.text.replaceAll(' ', '');
                  Navigator.pop(context, cleanIBAN);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom formatter voor IBAN
class IBANFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    String text = newValue.text.replaceAll(' ', '');

    // Add spaces every 4 characters
    String formatted = '';
    for (int i = 0; i < text.length; i += 4) {
      if (i + 4 < text.length) {
        formatted += '${text.substring(i, i + 4)} ';
      } else {
        formatted += text.substring(i);
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Uppercase formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}