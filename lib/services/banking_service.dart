import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';

class BankingService {
  // Updated banking apps URLs with correct schemes
  static const Map<String, Map<String, String>> _bankingApps = {
    // België - Real URL schemes
    'kbc': {
      'scheme': 'kbc-mobile',
      'payment_scheme': 'kbcmobile',
      'check_scheme': 'kbc-mobile://',
      'package': 'com.kbc.mobile.android',
    },
    'ing': {
      'scheme': 'ing-smart',
      'payment_scheme': 'ing-smart',
      'check_scheme': 'ing-smart://',
      'package': 'com.ing.mobile',
    },
    'belfius': {
      'scheme': 'belfius-direct-mobile',
      'payment_scheme': 'belfius-direct-mobile',
      'check_scheme': 'belfius-direct-mobile://',
      'package': 'be.belfius.directmobile.android',
    },
    'argenta': {
      'scheme': 'argenta-banking',
      'payment_scheme': 'argenta-banking',
      'check_scheme': 'argenta-banking://',
      'package': 'be.argenta.bankieren',
    },

    // Nederland
    'abnamro': {
      'scheme': 'abnamro',
      'payment_scheme': 'abnamro',
      'check_scheme': 'abnamro://',
      'package': 'com.abnamro.nl.mobile.payments',
    },
    'rabobank': {
      'scheme': 'rabobank',
      'payment_scheme': 'rabobank',
      'check_scheme': 'rabobank://',
      'package': 'nl.rabomobiel',
    },

    // Payment services
    'payconiq': {
      'scheme': 'payconiq',
      'payment_scheme': 'payconiq',
      'check_scheme': 'payconiq://',
      'package': 'com.payconiq.payconiq',
    },
  };

  // IBAN validatie voor Europese landen
  static bool validateIBAN(String iban) {
    // Remove spaces and convert to uppercase
    iban = iban.replaceAll(' ', '').toUpperCase();

    // Check length (15-34 characters)
    if (iban.length < 15 || iban.length > 34) return false;

    // Check if starts with 2 letters (country code)
    if (!RegExp(r'^[A-Z]{2}').hasMatch(iban)) return false;

    // Basic IBAN mod-97 check
    try {
      // Move first 4 characters to end
      String rearranged = iban.substring(4) + iban.substring(0, 4);

      // Replace letters with numbers (A=10, B=11, etc.)
      String numeric = '';
      for (int i = 0; i < rearranged.length; i++) {
        String char = rearranged[i];
        if (RegExp(r'[A-Z]').hasMatch(char)) {
          numeric += (char.codeUnitAt(0) - 55).toString();
        } else {
          numeric += char;
        }
      }

      // Check mod 97
      BigInt number = BigInt.parse(numeric);
      return number % BigInt.from(97) == BigInt.one;
    } catch (e) {
      return false;
    }
  }

  // Format IBAN with spaces for display
  static String formatIBAN(String iban) {
    iban = iban.replaceAll(' ', '').toUpperCase();
    String formatted = '';
    for (int i = 0; i < iban.length; i += 4) {
      if (i + 4 < iban.length) {
        formatted += '${iban.substring(i, i + 4)} ';
      } else {
        formatted += iban.substring(i);
      }
    }
    return formatted.trim();
  }

  // Get country name from IBAN
  static String getCountryFromIBAN(String iban) {
    final countryCode = iban.substring(0, 2).toUpperCase();
    final countries = {
      'BE': 'België',
      'NL': 'Nederland',
      'DE': 'Duitsland',
      'FR': 'Frankrijk',
      'IT': 'Italië',
      'ES': 'Spanje',
      'AT': 'Oostenrijk',
      'LU': 'Luxemburg',
      'CH': 'Zwitserland',
      'GB': 'Verenigd Koninkrijk',
    };
    return countries[countryCode] ?? 'Onbekend land';
  }

  // Enhanced app detection with multiple methods
  static Future<List<String>> getInstalledBankingApps() async {
    List<String> installedApps = [];
    if (kDebugMode) {
      print('🔍 Checking for installed banking apps...');
    }

    for (String bank in _bankingApps.keys) {
      bool isInstalled = false;
      Map<String, String> appInfo = _bankingApps[bank]!;

      // Method 1: Try main scheme
      try {
        String checkUrl = appInfo['check_scheme']!;
        if (await canLaunchUrl(Uri.parse(checkUrl))) {
          if (kDebugMode) {
            print('✅ Found $bank via main scheme: $checkUrl');
          }
          isInstalled = true;
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ $bank main scheme failed: $e');
        }
      }

      // Method 2: Try alternative schemes
      if (!isInstalled) {
        List<String> alternativeSchemes = [
          '${appInfo['scheme']}://',
          '${appInfo['payment_scheme']}://',
          '${appInfo['scheme']}://open',
          '${appInfo['payment_scheme']}://payment',
        ];

        for (String altScheme in alternativeSchemes) {
          try {
            if (await canLaunchUrl(Uri.parse(altScheme))) {
              if (kDebugMode) {
                print('✅ Found $bank via alternative scheme: $altScheme');
              }
              isInstalled = true;
              break;
            }
          } catch (e) {
            // Continue to next scheme
          }
        }
      }

      if (isInstalled) {
        installedApps.add(bank);
      } else {
        if (kDebugMode) {
          print('❌ $bank not found');
        }
      }
    }

    if (kDebugMode) {
      print('📱 Total installed banking apps: ${installedApps.length}');
    }
    if (kDebugMode) {
      print('📱 Installed apps: $installedApps');
    }

    // For development/testing - uncomment to simulate apps
    // if (installedApps.isEmpty) {
    //   print('🧪 Development mode: simulating KBC installation');
    //   installedApps.add('kbc');
    // }

    return installedApps;
  }

  // Enhanced app opening with multiple URL attempts
  static Future<bool> openBankingApp({
    required String bankApp,
    required String recipientIBAN,
    required String recipientName,
    required double amount,
    required String description,
  }) async {
    if (!_bankingApps.containsKey(bankApp)) {
      if (kDebugMode) {
        print('❌ Unknown banking app: $bankApp');
      }
      return false;
    }

    Map<String, String> appInfo = _bankingApps[bankApp]!;
    String formattedAmount = amount.toStringAsFixed(2);
    String cleanIBAN = recipientIBAN.replaceAll(' ', '');

    // Try multiple URL formats for the banking app
    List<String> urlsToTry = [
      // Standard payment URL
      '${appInfo['payment_scheme']}://payment?iban=$cleanIBAN&amount=$formattedAmount&beneficiary=${Uri.encodeComponent(recipientName)}&description=${Uri.encodeComponent(description)}',

      // Alternative format 1
      '${appInfo['scheme']}://transfer?to=$cleanIBAN&amount=$formattedAmount&name=${Uri.encodeComponent(recipientName)}&memo=${Uri.encodeComponent(description)}',

      // Alternative format 2
      '${appInfo['scheme']}://pay?recipient=$cleanIBAN&amount=$formattedAmount',

      // Basic app opening
      '${appInfo['scheme']}://open',
      '${appInfo['scheme']}://',
    ];

    if (kDebugMode) {
      print('🚀 Attempting to open $bankApp...');
    }

    for (int i = 0; i < urlsToTry.length; i++) {
      String url = urlsToTry[i];
      if (kDebugMode) {
        print('🔗 Trying URL ${i + 1}: $url');
      }

      try {
        if (await canLaunchUrl(Uri.parse(url))) {
          bool launched = await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );

          if (launched) {
            if (kDebugMode) {
              print('✅ Successfully opened $bankApp with URL: $url');
            }
            return true;
          } else {
            if (kDebugMode) {
              print('❌ Failed to launch $bankApp with URL: $url');
            }
          }
        } else {
          if (kDebugMode) {
            print('❌ Cannot launch URL: $url');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error with URL $url: $e');
        }
      }
    }

    if (kDebugMode) {
      print('❌ Failed to open $bankApp with any URL');
    }
    return false;
  }

  // Updated banking method that uses Bancontact payment links
  static Future<bool> openBankingAppViaBancontact({
    required String recipientIBAN,
    required String recipientName,
    required double amount,
    required String description,
  }) async {
    try {
      if (kDebugMode) {
        print('🏦 Opening banking app via Bancontact...');
      }

      // Bancontact payment URL format
      String cleanIBAN = recipientIBAN.replaceAll(' ', '');
      String formattedAmount = amount.toStringAsFixed(2);
      String encodedDescription = Uri.encodeComponent(description);
      String encodedName = Uri.encodeComponent(recipientName);

      // Try multiple Bancontact URL formats
      List<String> bancontactUrls = [
        // Standard Bancontact payment URL
        'https://bancontact.be/pay?iban=$cleanIBAN&amount=$formattedAmount&beneficiary=$encodedName&description=$encodedDescription',

        // Alternative Bancontact format
        'bancontact://payment?iban=$cleanIBAN&amount=$formattedAmount&beneficiary=$encodedName&description=$encodedDescription',

        // SEPA payment link (universal)
        'sepa://payment?iban=$cleanIBAN&amount=$formattedAmount&name=$encodedName&memo=$encodedDescription',

        // European payment initiative format
        'epi://payment?iban=$cleanIBAN&amount=$formattedAmount&beneficiary=$encodedName&reference=$encodedDescription',

        // Belgium-specific payment URL
        'be-payment://transfer?to=$cleanIBAN&amount=$formattedAmount&name=$encodedName&memo=$encodedDescription',
      ];

      for (int i = 0; i < bancontactUrls.length; i++) {
        String url = bancontactUrls[i];
        if (kDebugMode) {
          print('🔗 Trying Bancontact URL ${i + 1}: $url');
        }

        try {
          Uri uri = Uri.parse(url);

          if (await canLaunchUrl(uri)) {
            if (kDebugMode) {
              print('✅ Can launch: $url');
            }

            bool launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );

            if (launched) {
              if (kDebugMode) {
                print('✅ Successfully opened banking selection via: $url');
              }
              return true;
            } else {
              if (kDebugMode) {
                print('❌ Failed to launch: $url');
              }
            }
          } else {
            if (kDebugMode) {
              print('❌ Cannot launch: $url');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error with URL $url: $e');
          }
          continue;
        }
      }

      if (kDebugMode) {
        print('❌ All Bancontact URLs failed');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in Bancontact payment: $e');
      }
      return false;
    }
  }

  // Updated method to try Bancontact first, then fallback to specific apps
  static Future<bool> openBankingAppSmart({
    required String recipientIBAN,
    required String recipientName,
    required double amount,
    required String description,
  }) async {
    if (kDebugMode) {
      print('🎯 Smart banking app opening...');
    }

    // Step 1: Try Bancontact payment link (shows all compatible apps)
    bool bancontactSuccess = await openBankingAppViaBancontact(
      recipientIBAN: recipientIBAN,
      recipientName: recipientName,
      amount: amount,
      description: description,
    );

    if (bancontactSuccess) {
      if (kDebugMode) {
        print('✅ Bancontact payment link opened successfully');
      }
      return true;
    }

    if (kDebugMode) {
      print('⚠️ Bancontact failed, trying specific banking apps...');
    }

    // Step 2: Fallback to specific banking app detection
    final installedApps = await getInstalledBankingApps();

    if (installedApps.isNotEmpty) {
      bool specificAppSuccess = await openBankingApp(
        bankApp: installedApps.first,
        recipientIBAN: recipientIBAN,
        recipientName: recipientName,
        amount: amount,
        description: description,
      );

      if (specificAppSuccess) {
        if (kDebugMode) {
          print('✅ Specific banking app opened successfully');
        }
        return true;
      }
    }

    if (kDebugMode) {
      print('❌ All banking options failed');
    }
    return false;
  }

  // Simplified method to check if banking payment is possible
  static Future<bool> canOpenBankingPayment() async {
    // Test if any banking payment method is available
    List<String> testUrls = [
      'https://bancontact.be',
      'bancontact://test',
      'sepa://test',
    ];

    for (String url in testUrls) {
      try {
        if (await canLaunchUrl(Uri.parse(url))) {
          return true;
        }
      } catch (e) {
        continue;
      }
    }

    // Also check if any specific banking apps are installed
    final installedApps = await getInstalledBankingApps();
    return installedApps.isNotEmpty;
  }

  // Fallback: open general banking URL or copy IBAN
  static Future<void> openGeneralBankingApp({
    required String recipientIBAN,
    required String recipientName,
    required double amount,
    required String description,
  }) async {
    if (kDebugMode) {
      print('🔄 Trying general banking fallback...');
    }

    // Try some general banking schemes
    final generalUrls = [
      'payconiq://payment?iban=${recipientIBAN.replaceAll(' ', '')}&amount=${amount.toStringAsFixed(2)}&description=${Uri.encodeComponent(description)}',
      'bancontact://payment?iban=${recipientIBAN.replaceAll(' ', '')}&amount=${amount.toStringAsFixed(2)}',
      'banking://transfer?iban=${recipientIBAN.replaceAll(' ', '')}&amount=${amount.toStringAsFixed(2)}',
    ];

    bool launched = false;
    for (String url in generalUrls) {
      try {
        if (kDebugMode) {
          print('🔗 Trying general URL: $url');
        }
        if (await canLaunchUrl(Uri.parse(url))) {
          launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (launched) {
            if (kDebugMode) {
              print('✅ Successfully opened general banking app');
            }
            break;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ General URL failed: $e');
        }
        continue;
      }
    }

    if (!launched) {
      if (kDebugMode) {
        print('❌ All general banking URLs failed, copying IBAN instead');
      }
      await Clipboard.setData(ClipboardData(text: recipientIBAN));
    }
  }

  // Show payment dialog with banking options
  static Future<void> showPaymentDialog({
    required BuildContext context,
    required UserModel recipient,
    required double amount,
    required String description,
  }) async {
    if (recipient.bankAccount == null || recipient.bankAccount!.isEmpty) {
      _showNoBankAccountDialog(context, recipient);
      return;
    }

    if (kDebugMode) {
      print('💳 Opening payment dialog for ${recipient.name}');
    }
    final installedApps = await getInstalledBankingApps();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentBottomSheet(
        recipient: recipient,
        amount: amount,
        description: description,
        installedBankingApps: installedApps,
      ),
    );
  }

  static void _showNoBankAccountDialog(BuildContext context, UserModel recipient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance, color: Colors.orange.shade500),
            const SizedBox(width: 8),
            const Text('Geen bankrekening'),
          ],
        ),
        content: Text(
          '${recipient.name} heeft nog geen bankrekening toegevoegd. Vraag hen om dit toe te voegen in hun profiel instellingen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// Updated PaymentBottomSheet with fixes
class PaymentBottomSheet extends StatelessWidget {
  final UserModel recipient;
  final double amount;
  final String description;
  final List<String> installedBankingApps;

  const PaymentBottomSheet({
    super.key,
    required this.recipient,
    required this.amount,
    required this.description,
    required this.installedBankingApps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // Limit height
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Betaal ${recipient.name}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment details
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Bedrag', '€${amount.toStringAsFixed(2)}', Icons.euro),
                        const Divider(height: 16),
                        _buildDetailRow('Naar', recipient.name, Icons.person),
                        const Divider(height: 16),
                        _buildDetailRow('IBAN', BankingService.formatIBAN(recipient.bankAccount!), Icons.account_balance),
                        const Divider(height: 16),
                        _buildDetailRow('Omschrijving', description, Icons.description),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Show different options based on what's available
                  if (installedBankingApps.isNotEmpty) ...[
                    const Text(
                      'Kies je bank app:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Installed banking apps
                    ...installedBankingApps.map((bank) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildBankOption(
                        context,
                        bank,
                        _getBankDisplayName(bank),
                        _getBankIcon(bank),
                        true,
                      ),
                    )),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                  ] else ...[
                    // No apps installed - show helpful message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.info, color: Colors.orange.shade600, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'Geen bank apps gevonden',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Installeer je bank app of gebruik de opties hieronder',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Always show these fallback options
                  const Text(
                    'Andere opties:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Copy IBAN option
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildBankOption(
                      context,
                      'copy',
                      'Kopieer IBAN nummer',
                      Icons.copy,
                      false,
                      subtitle: 'Voor handmatige overschrijving',
                    ),
                  ),

                  // Copy all details option
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildBankOption(
                      context,
                      'copy_all',
                      'Kopieer alle gegevens',
                      Icons.content_copy,
                      false,
                      subtitle: 'IBAN, bedrag en omschrijving',
                    ),
                  ),

                  // Open web banking option
                  _buildBankOption(
                    context,
                    'web_banking',
                    'Open internetbankieren',
                    Icons.web,
                    false,
                    subtitle: 'In browser',
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade600),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildBankOption(
      BuildContext context,
      String bankId,
      String bankName,
      IconData icon,
      bool isInstalled, {
        String? subtitle,
      }) {
    return Card(
      elevation: 0,
      color: isInstalled ? Colors.green.shade50 : Colors.grey.shade50,
      child: ListTile(
        leading: Icon(
          icon,
          color: isInstalled ? Colors.green.shade600 : Colors.grey.shade600,
        ),
        title: Text(
          bankName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : (isInstalled
            ? Text('Geïnstalleerd', style: TextStyle(color: Colors.green.shade600))
            : null),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          Navigator.pop(context);

          if (bankId == 'copy') {
            await Clipboard.setData(ClipboardData(text: recipient.bankAccount!));
            _showSnackBar(context, 'IBAN gekopieerd naar klembord', Colors.green);
          } else if (bankId == 'copy_all') {
            String allDetails = '''
Ontvanger: ${recipient.name}
IBAN: ${recipient.bankAccount!}
Bedrag: €${amount.toStringAsFixed(2)}
Omschrijving: $description
            '''.trim();

            await Clipboard.setData(ClipboardData(text: allDetails));
            _showSnackBar(context, 'Alle gegevens gekopieerd naar klembord', Colors.green);
          } else if (bankId == 'web_banking') {
            // Try to open common web banking URLs
            _showSnackBar(context, 'Open je bank website in de browser', Colors.blue);
          } else {
            // Try to open banking app
            bool success = await BankingService.openBankingApp(
              bankApp: bankId,
              recipientIBAN: recipient.bankAccount!,
              recipientName: recipient.name,
              amount: amount,
              description: description,
            );

            if (!success) {
              // Fallback to copying IBAN
              await Clipboard.setData(ClipboardData(text: recipient.bankAccount!));
              _showSnackBar(context, 'Kon bank app niet openen. IBAN gekopieerd.', Colors.orange);
            }
          }
        },
      ),
    );
  }

  // Helper method to show SnackBar at the top
  void _showSnackBar(BuildContext context, String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).size.height - 100),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getBankDisplayName(String bank) {
    final names = {
      'kbc': 'KBC Mobile',
      'ing': 'ING Banking',
      'belfius': 'Belfius Mobile',
      'argenta': 'Argenta Banking',
      'abnamro': 'ABN AMRO',
      'rabobank': 'Rabobank',
      'sns': 'SNS Bank',
      'sparkasse': 'Sparkasse',
      'commerzbank': 'Commerzbank',
      'payconiq': 'Payconiq',
      'bancontact': 'Bancontact',
    };
    return names[bank] ?? bank.toUpperCase();
  }

  IconData _getBankIcon(String bank) {
    final icons = {
      'kbc': Icons.account_balance,
      'ing': Icons.account_balance,
      'belfius': Icons.account_balance,
      'argenta': Icons.account_balance,
      'payconiq': Icons.payment,
      'bancontact': Icons.credit_card,
    };
    return icons[bank] ?? Icons.account_balance;
  }
}