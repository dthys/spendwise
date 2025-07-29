import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/banking_service.dart';

class BankAccountDialog {

  static Future<String?> showAddBankAccountDialog(
      BuildContext context, {
        String? currentIBAN,
      }) async {
    final _ibanController = TextEditingController(text: currentIBAN ?? '');
    final _formKey = GlobalKey<FormState>();
    bool _isValidating = false;
    String? _validationResult;

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.account_balance, color: Colors.blue.shade500),
              SizedBox(width: 8),
              Expanded( // This fixes the overflow
                child: Text(
                  currentIBAN == null ? 'Bankrekening toevoegen' : 'Bankrekening wijzigen',
                  overflow: TextOverflow.ellipsis, // Handle very long text gracefully
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voer je IBAN rekeningnummer in om directe betalingen mogelijk te maken.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _ibanController,
                      decoration: InputDecoration(
                        labelText: 'IBAN Rekeningnummer',
                        hintText: 'BE68 5390 0754 7034',
                        prefixIcon: Icon(Icons.account_balance),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        helperText: 'Formaat: BE68 5390 0754 7034',
                      ),
                      inputFormatters: [
                        UpperCaseTextFormatter(), // Apply uppercase first
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\s]')), // Then filter
                        IBANFormatter(), // Finally format with spaces
                      ],
                      onChanged: (value) {
                        setState(() {
                          _validationResult = null;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Voer een IBAN nummer in';
                        }

                        String cleanIBAN = value.replaceAll(' ', '');
                        if (cleanIBAN.length < 15) {
                          return 'IBAN is te kort';
                        }

                        if (!BankingService.validateIBAN(cleanIBAN)) {
                          return 'Ongeldig IBAN nummer';
                        }

                        return null;
                      },
                    ),

                    SizedBox(height: 16),

                    // Validation result
                    if (_validationResult != null)
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _validationResult!.startsWith('✅')
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _validationResult!.startsWith('✅')
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _validationResult!.startsWith('✅')
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: _validationResult!.startsWith('✅')
                                  ? Colors.green.shade600
                                  : Colors.red.shade600,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _validationResult!,
                                style: TextStyle(
                                  color: _validationResult!.startsWith('✅')
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(height: 16),

                    // Validate button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isValidating ? null : () async {
                          String iban = _ibanController.text.replaceAll(' ', '');
                          if (iban.length >= 15) {
                            setState(() {
                              _isValidating = true;
                            });

                            await Future.delayed(Duration(milliseconds: 500)); // Simulate validation

                            if (BankingService.validateIBAN(iban)) {
                              String country = BankingService.getCountryFromIBAN(iban);
                              setState(() {
                                _validationResult = '✅ Geldig IBAN nummer uit $country';
                                _isValidating = false;
                              });
                            } else {
                              setState(() {
                                _validationResult = '❌ Ongeldig IBAN nummer';
                                _isValidating = false;
                              });
                            }
                          }
                        },
                        icon: _isValidating
                            ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : Icon(Icons.verified),
                        label: Text(_isValidating ? 'Valideren...' : 'Valideer IBAN'),
                      ),
                    ),

                    SizedBox(height: 16),

                    // Info box
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Je IBAN wordt veilig opgeslagen en alleen gebruikt voor betalingen binnen je groepen.',
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
              child: Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  String cleanIBAN = _ibanController.text.replaceAll(' ', '');
                  Navigator.pop(context, cleanIBAN);
                }
              },
              child: Text('Opslaan'),
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
        formatted += text.substring(i, i + 4) + ' ';
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