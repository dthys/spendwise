import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';

// Enhanced Category Detection System
class EnhancedCategoryDetector {
  // Massively expanded keyword database with comprehensive coverage
  static Map<String, List<String>> get _categoryKeywords => {
    'food': [
      // Beverages - EXPANDED
      'beer', 'bier', 'pils', 'lager', 'ale', 'weizen', 'witbier', 'trappist',
      'heineken', 'amstel', 'bavaria', 'brand', 'grolsch', 'jupiler', 'stella artois',
      'wine', 'wijn', 'vin', 'wein', 'champagne', 'prosecco', 'cava', 'rosé',
      'whisky', 'whiskey', 'vodka', 'gin', 'rum', 'cognac', 'brandy', 'liqueur',
      'cocktail', 'mojito', 'margarita', 'martini', 'bloody mary', 'cosmopolitan',
      'coffee', 'koffie', 'café', 'cappuccino', 'espresso', 'latte', 'americano',
      'tea', 'thee', 'thé', 'tee', 'chai', 'matcha', 'earl grey', 'green tea',
      'water', 'eau', 'wasser', 'sparkling', 'spa', 'evian', 'perrier',
      'juice', 'sap', 'jus', 'saft', 'orange juice', 'apple juice', 'smoothie',
      'soda', 'cola', 'pepsi', 'fanta', 'sprite', 'seven up', '7up', 'dr pepper',

      // Meals & Dining - EXPANDED
      'breakfast', 'ontbijt', 'petit déjeuner', 'frühstück', 'brunch',
      'lunch', 'déjeuner', 'mittagessen', 'dinner', 'diner', 'avondeten',
      'meal', 'maaltijd', 'repas', 'mahlzeit', 'snack', 'tussendoortje',
      'restaurant', 'cafe', 'bar', 'bistro', 'brasserie', 'pizzeria',
      'takeaway', 'afhaal', 'delivery', 'bezorging', 'drive thru', 'drive-through',

      // Food items - EXPANDED
      'pizza', 'burger', 'hamburger', 'cheeseburger', 'fries', 'frites', 'patat',
      'pasta', 'spaghetti', 'lasagna', 'risotto', 'gnocchi', 'carbonara',
      'steak', 'chicken', 'kip', 'poulet', 'hähnchen', 'fish', 'vis', 'poisson',
      'salad', 'salade', 'soup', 'soep', 'soupe', 'sandwich', 'panini', 'wrap',
      'sushi', 'ramen', 'pad thai', 'curry', 'tacos', 'burrito', 'quesadilla',
      'bread', 'brood', 'pain', 'brot', 'croissant', 'bagel', 'toast',
      'cheese', 'kaas', 'fromage', 'käse', 'gouda', 'cheddar', 'brie', 'camembert',

      // Supermarkets & Stores - MASSIVELY EXPANDED
      'supermarket', 'supermarkt', 'supermarché', 'grocery', 'groceries', 'boodschappen',

      // Dutch supermarkets
      'albert heijn', 'ah', 'jumbo', 'lidl', 'aldi', 'plus', 'coop', 'spar',
      'vomar', 'dirk', 'hoogvliet', 'picnic', 'nettorama', 'dekamarkt', 'ekoplaza',
      'marqt', 'fresh', 'deen', 'boon', 'emté', 'poiesz', 'mcd', 'jan linders',

      // Belgian supermarkets
      'colruyt', 'delhaize', 'carrefour', 'aldi', 'lidl', 'okay', 'spar',
      'proxy', 'louis delhaize', 'fresh market', 'bio planet', 'rob',

      // German supermarkets
      'rewe', 'edeka', 'netto', 'penny', 'real', 'kaufland', 'norma',
      'tegut', 'hit', 'globus', 'famila', 'combi', 'v-markt',

      // French supermarkets
      'leclerc', 'intermarché', 'super u', 'système u', 'casino', 'monoprix',
      'franprix', 'simply market', 'match', 'géant', 'hyper u',

      // International chains
      'walmart', 'target', 'whole foods', 'kroger', 'safeway', 'publix',
      'tesco', 'sainsburys', 'asda', 'morrisons', 'marks spencer', 'm&s',

      // Generic shop terms
      'shop', 'winkel', 'magasin', 'laden', 'store', 'market', 'markt',
      'minimarket', 'corner shop', 'convenience', 'deli', 'butcher', 'slager',
      'bakery', 'bakker', 'boulangerie', 'bäckerei', 'fishmonger', 'visboer',

      // Fast food chains - EXPANDED
      'mcdonalds', 'mcdonald\'s', 'burger king', 'kfc', 'subway', 'dominos',
      'pizza hut', 'taco bell', 'wendy\'s', 'five guys', 'chipotle',
      'starbucks', 'dunkin', 'tim hortons', 'costa coffee', 'nero',
      'vapiano', 'new york pizza', 'spare rib express', 'kentucky',

      // Delivery services
      'uber eats', 'deliveroo', 'thuisbezorgd', 'just eat', 'grubhub',
      'doordash', 'foodpanda', 'lieferando', 'takeaway.com',

      // Desserts & Sweets
      'dessert', 'ice cream', 'ijs', 'gelato', 'cake', 'taart', 'chocolate',
      'candy', 'snoep', 'cookies', 'koekjes', 'pastry', 'gebak', 'donut'
    ],

    'transport': [
      // Public Transport - EXPANDED
      'transport', 'vervoer', 'bus', 'tram', 'metro', 'train', 'trein',
      'subway', 'underground', 'tube', 'railway', 'spoorweg',

      // Transport companies & services
      'ns', 'deutsche bahn', 'sncf', 'trenitalia', 'renfe', 'pkp', 'sbb',
      'gvb', 'ret', 'htm', 'connexxion', 'arriva', 'keolis', 'qbuzz', 'syntus',
      'stib', 'mivb', 'de lijn', 'tec', 'eurostar', 'thalys', 'ice',

      // Tickets & Cards
      'ticket', 'kaartje', 'ov-chipkaart', 'oyster', 'navigo', 'bvg',
      'day pass', 'dagkaart', 'week pass', 'maandkaart', 'season ticket',

      // Rideshare & Taxi - EXPANDED
      'uber', 'lyft', 'bolt', 'free now', 'taxi', 'cab', 'chauffeur',
      'blablacar', 'car sharing', 'car2go', 'zipcar', 'greenwheels',

      // Fuel & Parking - EXPANDED
      'fuel', 'gas', 'petrol', 'benzine', 'diesel', 'lpg', 'electric charging',
      'shell', 'bp', 'esso', 'total', 'texaco', 'q8', 'tamoil', 'lukoil',
      'parking', 'parkeren', 'garage', 'meter', 'vignette', 'toll', 'tol',
      'q-park', 'apcoa', 'europark', 'parkline', 'easypark', 'yellowbrick',

      // Bike & Scooter
      'bike', 'fiets', 'bicycle', 'cycling', 'bike rental', 'ov-fiets',
      'swapfiets', 'donkey republic', 'mobike', 'lime', 'bird', 'tier',
      'scooter', 'vespa', 'moped', 'bromfiets', 'felyx', 'check', 'go sharing',

      // Car services
      'car wash', 'autowas', 'garage', 'mechanic', 'mot', 'apk', 'repair',
      'insurance', 'verzekering', 'registration', 'kenteken', 'road tax'
    ],

    'shopping': [
      // General shopping terms - EXPANDED
      'shopping', 'winkelen', 'purchase', 'buy', 'bought', 'gekocht', 'acheté',
      'store', 'shop', 'winkel', 'magasin', 'laden', 'boutique',
      'mall', 'shopping center', 'winkelcentrum', 'centre commercial',
      'outlet', 'factory outlet', 'discount', 'sale', 'uitverkoop',

      // Department stores - EXPANDED
      'department store', 'warenhuis', 'grand magasin', 'kaufhaus',
      'bijenkorf', 'v&d', 'galeries lafayette', 'printemps', 'harrods',
      'selfridges', 'john lewis', 'macy\'s', 'nordstrom', 'saks',
      'karstadt', 'galeria kaufhof', 'el corte inglés',

      // General retailers - MASSIVELY EXPANDED
      'hema', 'action', 'xenos', 'blokker', 'casa', 'ikea', 'primark',
      'tk maxx', 'tjx', 'ross', 'marshalls', 'century 21',

      // Electronics - EXPANDED
      'electronics', 'elektronica', 'tech', 'technology', 'gadget',
      'mediamarkt', 'saturn', 'best buy', 'circuit city', 'fry\'s',
      'currys', 'dixons', 'fnac', 'darty', 'boulanger',
      'coolblue', 'bol.com', 'amazon', 'ebay', 'aliexpress',
      'phone', 'laptop', 'computer', 'tablet', 'tv', 'camera',
      'apple', 'samsung', 'sony', 'lg', 'philips', 'panasonic',

      // Clothing - EXPANDED
      'clothes', 'clothing', 'kleding', 'vêtements', 'kleidung', 'fashion',
      'zara', 'h&m', 'uniqlo', 'gap', 'old navy', 'banana republic',
      'c&a', 'mango', 'bershka', 'pull bear', 'stradivarius',
      'nike', 'adidas', 'puma', 'under armour', 'reebok', 'converse',
      'shoes', 'schoenen', 'chaussures', 'schuhe', 'sneakers', 'boots',

      // Online shopping - EXPANDED
      'online', 'internet', 'web shop', 'webshop', 'e-commerce',
      'amazon', 'ebay', 'alibaba', 'zalando', 'asos', 'boohoo',
      'wehkamp', 'otto', 'about you', 'very', 'next', 'argos',
      'delivery', 'shipping', 'verzending', 'livraison', 'versand',

      // Books & Media
      'books', 'boeken', 'bookstore', 'boekhandel', 'library', 'bibliotheek',
      'waterstones', 'barnes noble', 'borders', 'chapters', 'fnac',
      'bol.com', 'amazon books', 'kindle', 'audible', 'kobo'
    ],

    'entertainment': [
      // Movies & Cinema - EXPANDED
      'cinema', 'bioscoop', 'movie', 'film', 'picture', 'flick',
      'pathé', 'vue', 'odeon', 'cineworld', 'showcase', 'regal',
      'amc', 'cinemark', 'imax', '3d', '4dx', 'dolby', 'premiere',
      'ticket', 'popcorn', 'nachos', 'screening', 'matinee',

      // Streaming & Digital
      'netflix', 'disney plus', 'amazon prime', 'hulu', 'hbo', 'spotify',
      'apple music', 'youtube premium', 'twitch', 'paramount plus',
      'videoland', 'npo start', 'rtl xl', 'kijk', 'discovery plus',

      // Music & Concerts - EXPANDED
      'concert', 'gig', 'show', 'performance', 'recital', 'symphony',
      'opera', 'musical', 'theater', 'theatre', 'ballet', 'dance',
      'festival', 'lowlands', 'pinkpop', 'coachella', 'glastonbury',
      'tomorrowland', 'ultra', 'burning man', 'lollapalooza',
      'venue', 'hall', 'arena', 'stadium', 'club', 'bar', 'pub',
      'ziggo dome', 'ahoy', 'heineken music hall', 'paradiso', 'melkweg',

      // Sports & Activities - EXPANDED
      'sport', 'sports', 'gym', 'fitness', 'workout', 'exercise',
      'basic fit', 'david lloyd', 'virgin active', 'la fitness',
      'planet fitness', '24 hour fitness', 'equinox', 'crossfit',
      'tennis', 'golf', 'football', 'soccer', 'basketball', 'baseball',
      'hockey', 'rugby', 'cricket', 'volleyball', 'badminton',
      'swimming', 'pool', 'spa', 'sauna', 'wellness', 'massage',

      // Gaming - EXPANDED
      'gaming', 'games', 'video games', 'console', 'pc gaming',
      'playstation', 'xbox', 'nintendo', 'steam', 'epic games',
      'game pass', 'ps plus', 'nintendo online', 'arcade',

      // Leisure Activities - EXPANDED
      'bowling', 'pool', 'billiards', 'darts', 'karaoke', 'quiz',
      'escape room', 'laser tag', 'paintball', 'go kart', 'mini golf',
      'amusement park', 'theme park', 'pretpark', 'efteling', 'walibi',
      'disneyland', 'six flags', 'cedar point', 'thorpe park', 'alton towers'
    ],

    'accommodation': [
      // Hotels - EXPANDED
      'hotel', 'motel', 'inn', 'lodge', 'resort', 'hostel', 'b&b',
      'bed and breakfast', 'pension', 'guesthouse', 'villa', 'chalet',

      // Hotel chains - EXPANDED
      'hilton', 'marriott', 'hyatt', 'sheraton', 'westin', 'radisson',
      'holiday inn', 'best western', 'ibis', 'novotel', 'mercure',
      'accor', 'intercontinental', 'doubletree', 'hampton inn',
      'courtyard', 'residence inn', 'extended stay', 'homewood suites',

      // Booking platforms - EXPANDED
      'booking.com', 'booking', 'expedia', 'hotels.com', 'agoda',
      'priceline', 'kayak', 'trivago', 'travelocity', 'orbitz',
      'airbnb', 'vrbo', 'homeaway', 'vacasa', 'turnkey',

      // Accommodation types
      'apartment', 'flat', 'studio', 'suite', 'room', 'cabin',
      'cottage', 'house', 'home', 'rental', 'vacation rental',
      'holiday home', 'timeshare', 'condo', 'penthouse',

      // Camping & Outdoors - EXPANDED
      'camping', 'campsite', 'campground', 'rv park', 'caravan',
      'motorhome', 'tent', 'glamping', 'yurt', 'cabin', 'lodge',
      'koa', 'hipcamp', 'recreation area', 'national park', 'state park'
    ],

    'bills': [
      // Utilities - EXPANDED
      'utility', 'utilities', 'bill', 'invoice', 'statement', 'payment',
      'electricity', 'power', 'electric', 'gas', 'water', 'sewer',
      'heating', 'cooling', 'hvac', 'trash', 'garbage', 'recycling',

      // Energy companies - EXPANDED
      'eneco', 'essent', 'vattenfall', 'greenchoice', 'budget energie',
      'energiedirect', 'frank energie', 'pure energie', 'oxxio', 'nuon',
      'edf', 'enel', 'iberdrola', 'endesa', 'eon', 'rwe', 'total energies',

      // Telecom - EXPANDED
      'phone', 'mobile', 'internet', 'wifi', 'broadband', 'cable',
      'fiber', 'landline', 'cellular', 'data', 'minutes', 'sms',
      'kpn', 'vodafone', 't-mobile', 'ziggo', 'odido', 'tele2',
      'verizon', 'at&t', 'sprint', 'tmobile', 'orange', 'bt', 'sky',

      // Insurance - EXPANDED
      'insurance', 'premium', 'policy', 'coverage', 'deductible',
      'health insurance', 'car insurance', 'home insurance', 'life insurance',
      'travel insurance', 'pet insurance', 'disability insurance',
      'achmea', 'aegon', 'allianz', 'axa', 'generali', 'zurich',

      // Banking & Finance - EXPANDED
      'bank', 'banking', 'account', 'fee', 'charge', 'interest',
      'loan', 'mortgage', 'credit card', 'overdraft', 'transfer',
      'ing', 'rabobank', 'abn amro', 'sns', 'bunq', 'revolut', 'n26',

      // Government & Taxes - EXPANDED
      'tax', 'taxes', 'irs', 'hmrc', 'belastingdienst', 'government',
      'council', 'municipality', 'city hall', 'dmv', 'license',
      'registration', 'permit', 'fine', 'penalty', 'court', 'legal',

      // Subscriptions - EXPANDED
      'subscription', 'membership', 'annual', 'monthly', 'quarterly',
      'recurring', 'auto-pay', 'direct debit', 'standing order'
    ],

    'healthcare': [
      // Medical professionals - EXPANDED
      'doctor', 'physician', 'gp', 'general practitioner', 'specialist',
      'surgeon', 'consultant', 'nurse', 'therapist', 'counselor',
      'psychiatrist', 'psychologist', 'dentist', 'orthodontist',
      'optometrist', 'ophthalmologist', 'dermatologist', 'cardiologist',

      // Medical facilities - EXPANDED
      'hospital', 'clinic', 'medical centre', 'health centre', 'surgery',
      'emergency room', 'er', 'urgent care', 'walk-in clinic',
      'pharmacy', 'drugstore', 'chemist', 'apotheek', 'pharmacie',

      // Treatments & Services - EXPANDED
      'appointment', 'consultation', 'checkup', 'examination', 'screening',
      'test', 'blood test', 'x-ray', 'scan', 'mri', 'ct scan', 'ultrasound',
      'vaccination', 'immunization', 'injection', 'shot', 'prescription',
      'medication', 'medicine', 'pills', 'tablets', 'drugs', 'treatment',

      // Specialized care - EXPANDED
      'physiotherapy', 'physical therapy', 'occupational therapy',
      'speech therapy', 'chiropractic', 'osteopath', 'acupuncture',
      'massage', 'reflexology', 'homeopathy', 'naturopath',

      // Mental health - EXPANDED
      'therapy', 'counseling', 'psychotherapy', 'psychology', 'psychiatry',
      'mental health', 'counselling', 'behavioral health', 'addiction',
      'rehab', 'rehabilitation', 'detox', 'aa', 'na', 'support group',

      // Medical supplies & equipment
      'medical equipment', 'wheelchair', 'crutches', 'walker', 'hearing aid',
      'glasses', 'contacts', 'prosthetic', 'bandage', 'brace', 'splint'
    ]
  };

  // Fuzzy matching threshold (0.0 to 1.0, where 1.0 is exact match)
  static const double _fuzzyThreshold = 0.75;

  // Calculate Levenshtein distance for fuzzy matching
  static int _levenshteinDistance(String s1, String s2) {
    if (s1.length < s2.length) {
      return _levenshteinDistance(s2, s1);
    }

    if (s2.isEmpty) {
      return s1.length;
    }

    List<int> previousRow = List.generate(s2.length + 1, (i) => i);

    for (int i = 0; i < s1.length; i++) {
      List<int> currentRow = [i + 1];

      for (int j = 0; j < s2.length; j++) {
        int insertions = previousRow[j + 1] + 1;
        int deletions = currentRow[j] + 1;
        int substitutions = previousRow[j] + (s1[i] != s2[j] ? 1 : 0);
        currentRow.add([insertions, deletions, substitutions].reduce((a, b) => a < b ? a : b));
      }

      previousRow = currentRow;
    }

    return previousRow.last;
  }

  // Calculate similarity ratio (0.0 to 1.0)
  static double _similarity(String s1, String s2) {
    int maxLength = [s1.length, s2.length].reduce((a, b) => a > b ? a : b);
    if (maxLength == 0) return 1.0;

    int distance = _levenshteinDistance(s1.toLowerCase(), s2.toLowerCase());
    return (maxLength - distance) / maxLength;
  }

  // Enhanced detection with multiple strategies
  static ExpenseCategory? detectCategory(String description, {Map<String, ExpenseCategory>? learnedKeywords}) {
    String text = description.toLowerCase().trim();
    if (text.length < 2) return null;

    List<String> words = text.split(RegExp(r'[\s\-_.,!?()]+'))
        .where((w) => w.length > 1)
        .toList();

    Set<String> wordSet = words.map((w) => w.toLowerCase()).toSet();

    // Strategy 1: Check learned keywords first (highest priority)
    if (learnedKeywords != null) {
      for (String keyword in learnedKeywords.keys) {
        // Exact match
        if (wordSet.contains(keyword.toLowerCase())) {
          return learnedKeywords[keyword];
        }

        // Fuzzy match for learned keywords
        for (String word in words) {
          if (_similarity(word, keyword) >= _fuzzyThreshold) {
            return learnedKeywords[keyword];
          }
        }
      }
    }

    // Strategy 2: Exact keyword matching with enhanced scoring
    Map<ExpenseCategory, double> categoryScores = {};
    Map<String, ExpenseCategory> categoryMap = {
      'food': ExpenseCategory.food,
      'transport': ExpenseCategory.transport,
      'entertainment': ExpenseCategory.entertainment,
      'shopping': ExpenseCategory.shopping,
      'accommodation': ExpenseCategory.accommodation,
      'bills': ExpenseCategory.bills,
      'healthcare': ExpenseCategory.healthcare,
    };

    for (String categoryKey in _categoryKeywords.keys) {
      ExpenseCategory? category = categoryMap[categoryKey];
      if (category == null) continue;

      List<String> keywords = _categoryKeywords[categoryKey] ?? [];
      double score = 0.0;

      for (String keyword in keywords) {
        String keywordLower = keyword.toLowerCase();

        // Exact word match (highest score)
        if (wordSet.contains(keywordLower)) {
          double baseScore = keyword.length > 6 ? 5.0 :
          keyword.length > 4 ? 3.0 : 2.0;

          // Bonus for position in text
          if (text.startsWith(keywordLower)) baseScore *= 1.5;
          if (text.contains(' $keywordLower ') || text.endsWith(' $keywordLower')) baseScore *= 1.2;

          score += baseScore;
        }

        // Fuzzy matching for typos and variations
        else {
          for (String word in words) {
            double similarity = _similarity(word, keywordLower);
            if (similarity >= _fuzzyThreshold) {
              score += similarity * (keyword.length > 4 ? 2.0 : 1.5);
            }
          }
        }

        // Partial matching for compound words and variations
        if (keywordLower.length > 4) {
          for (String word in words) {
            if (word.contains(keywordLower) || keywordLower.contains(word)) {
              double partialScore = (keywordLower.length > 6) ? 1.5 : 1.0;
              score += partialScore;
            }
          }
        }
      }

      if (score > 0) {
        categoryScores[category] = score;
      }
    }

    // Strategy 3: Contextual pattern matching
    _addContextualScores(text, words, categoryScores);

    // Find the category with the highest score
    if (categoryScores.isNotEmpty) {
      var sortedEntries = categoryScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Require a minimum confidence score
      if (sortedEntries.first.value >= 2.0) {
        return sortedEntries.first.key;
      }
    }

    return null;
  }

  // Add contextual scoring based on patterns and combinations
  static void _addContextualScores(String text, List<String> words, Map<ExpenseCategory, double> categoryScores) {
    // Food contexts
    if (_containsAny(text, ['lunch at', 'dinner at', 'breakfast at', 'drinks at', 'meal at'])) {
      categoryScores[ExpenseCategory.food] = (categoryScores[ExpenseCategory.food] ?? 0) + 2.0;
    }

    if (_containsAny(text, ['buy food', 'food shopping', 'grocery run', 'weekly shop'])) {
      categoryScores[ExpenseCategory.food] = (categoryScores[ExpenseCategory.food] ?? 0) + 2.0;
    }

    // Transport contexts
    if (_containsAny(text, ['trip to', 'travel to', 'journey to', 'ride to', 'drive to'])) {
      categoryScores[ExpenseCategory.transport] = (categoryScores[ExpenseCategory.transport] ?? 0) + 1.5;
    }

    if (_containsAny(text, ['fuel up', 'gas station', 'petrol station', 'fill up'])) {
      categoryScores[ExpenseCategory.transport] = (categoryScores[ExpenseCategory.transport] ?? 0) + 2.0;
    }

    // Entertainment contexts
    if (_containsAny(text, ['night out', 'fun at', 'entertainment', 'leisure', 'hobby'])) {
      categoryScores[ExpenseCategory.entertainment] = (categoryScores[ExpenseCategory.entertainment] ?? 0) + 1.5;
    }

    // Shopping contexts
    if (_containsAny(text, ['bought', 'purchased', 'shopping for', 'new', 'replacement'])) {
      categoryScores[ExpenseCategory.shopping] = (categoryScores[ExpenseCategory.shopping] ?? 0) + 1.0;
    }

    // Bills contexts
    if (_containsAny(text, ['monthly', 'annual', 'bill', 'payment', 'subscription', 'insurance'])) {
      categoryScores[ExpenseCategory.bills] = (categoryScores[ExpenseCategory.bills] ?? 0) + 1.5;
    }

    // Healthcare contexts
    if (_containsAny(text, ['checkup', 'appointment', 'visit to', 'treatment', 'medical'])) {
      categoryScores[ExpenseCategory.healthcare] = (categoryScores[ExpenseCategory.healthcare] ?? 0) + 1.5;
    }

    // Accommodation contexts
    if (_containsAny(text, ['stay at', 'night at', 'booking', 'reservation', 'check in'])) {
      categoryScores[ExpenseCategory.accommodation] = (categoryScores[ExpenseCategory.accommodation] ?? 0) + 1.5;
    }
  }

  static bool _containsAny(String text, List<String> phrases) {
    return phrases.any((phrase) => text.toLowerCase().contains(phrase.toLowerCase()));
  }

  // Extract meaningful keywords for learning (improved version)
  static List<String> extractLearningKeywords(String description) {
    String text = description.toLowerCase().trim();
    List<String> keywords = [];

    // Split and clean words
    List<String> words = text.split(RegExp(r'[\s\-_.,!?()]+'))
        .where((w) => w.length > 2)
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.isNotEmpty && !_isCommonWord(w))
        .toList();

    // Add meaningful individual words
    keywords.addAll(words);

    // Extract brand names and proper nouns (capitalized in original text)
    RegExp brandPattern = RegExp(r'\b[A-Z][a-zA-Z]+\b');
    Iterable<Match> matches = brandPattern.allMatches(description);
    for (Match match in matches) {
      String brand = match.group(0)!.toLowerCase();
      if (brand.length > 2 && !_isCommonWord(brand)) {
        keywords.add(brand);
      }
    }

    // Extract meaningful phrases (2-3 words)
    for (int i = 0; i < words.length - 1; i++) {
      String phrase = '${words[i]} ${words[i + 1]}';
      if (phrase.length > 6 && phrase.length < 25) {
        keywords.add(phrase);
      }
    }

    return keywords.toSet().toList(); // Remove duplicates
  }

  // Enhanced common word detection
  static bool _isCommonWord(String word) {
    const Set<String> commonWords = {
      // English
      'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
      'by', 'from', 'up', 'about', 'into', 'through', 'during', 'before',
      'after', 'above', 'below', 'between', 'among', 'this', 'that', 'these',
      'those', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him',
      'her', 'us', 'them', 'my', 'your', 'his',  'its', 'our', 'their',
      'a', 'an', 'some', 'any', 'many', 'much', 'few', 'little', 'all',
      'both', 'each', 'every', 'either', 'neither', 'one', 'two', 'first',
      'last', 'other', 'another', 'such', 'what', 'which', 'who', 'when',
      'where', 'why', 'how', 'than', 'so', 'very', 'too', 'quite', 'rather',
      'just', 'only', 'even', 'also', 'still', 'already', 'yet', 'again',
      'once', 'now', 'then', 'here', 'there', 'today', 'tomorrow', 'yesterday',
      'good', 'bad', 'new', 'old', 'big', 'small', 'long', 'short', 'high',
      'low', 'same', 'different', 'right', 'wrong', 'true', 'false', 'yes',
      'no', 'ok', 'okay',

      // Dutch
      'de', 'het', 'een', 'en', 'van', 'te', 'dat', 'die',
      'hij', 'zijn', 'op', 'aan', 'met', 'als', 'voor', 'had',
      'er', 'maar', 'om', 'hem', 'dan', 'zou',  'wat', 'mijn',
      'men', 'dit', 'zo', 'door', 'over', 'ze', 'zich', 'bij', 'ook',
      'tot', 'je', 'mij', 'uit', 'der', 'daar', 'haar', 'naar', 'heb',
      'hoe', 'heeft', 'nog', 'zal',  'zij', 'nu', 'ge', 'geen',
      'omdat', 'iets', 'worden', 'toch', 'al', 'waren', 'veel', 'meer',
      'doen', 'toen', 'moet', 'ben', 'zonder', 'kan', 'hun', 'dus',
      'alles', 'onder', 'ja', 'eens', 'hier', 'wie', 'mee',


      // German
      'und',  'den', 'von', 'zu', 'das', 'mit', 'sich',
      'des', 'auf', 'für', 'ist', 'im', 'dem', 'nicht', 'ein', 'eine',
       'auch', 'es',  'werden', 'aus',  'hat', 'dass',
      'sie', 'nach', 'wird', 'bei', 'noch',  'einem', 'über',
      'einen',  'zum', 'war', 'haben', 'nur', 'oder', 'aber',
      'vor', 'zur', 'bis', 'mehr', 'durch', 'man', 'sein', 'wurde',
      'sei',  'ich', 'du',  'wir', 'ihr',

      // French
      'le',  'et', 'à', 'un', 'il', 'être',  'avoir',
      'que', 'pour', 'dans', 'ce', 'son', 'une', 'sur', 'avec', 'ne',
      'se', 'pas', 'par', 'mais', 'au', 'vous', 'tout',
      'nous', 'comme',  'la', 'lui', 'faire', 'mon', 'qui', 'très',
      'où', 'quoi', 'comment', 'quand', 'pourquoi', 'oui', 'non', 'si',
    };

    return commonWords.contains(word.toLowerCase());
  }

  // Suggest categories based on partial matches
  static List<ExpenseCategory> suggestCategories(String description, {int maxSuggestions = 3}) {
    String text = description.toLowerCase().trim();
    if (text.length < 2) return [];

    Map<ExpenseCategory, double> categoryScores = {};
    Map<String, ExpenseCategory> categoryMap = {
      'food': ExpenseCategory.food,
      'transport': ExpenseCategory.transport,
      'entertainment': ExpenseCategory.entertainment,
      'shopping': ExpenseCategory.shopping,
      'accommodation': ExpenseCategory.accommodation,
      'bills': ExpenseCategory.bills,
      'healthcare': ExpenseCategory.healthcare,
    };

    List<String> words = text.split(RegExp(r'[\s\-_.,!?()]+'))
        .where((w) => w.length > 1)
        .toList();

    // Score all categories
    for (String categoryKey in _categoryKeywords.keys) {
      ExpenseCategory? category = categoryMap[categoryKey];
      if (category == null) continue;

      List<String> keywords = _categoryKeywords[categoryKey] ?? [];
      double score = 0.0;

      for (String keyword in keywords) {
        for (String word in words) {
          double similarity = _similarity(word, keyword.toLowerCase());
          if (similarity > 0.5) { // Lower threshold for suggestions
            score += similarity;
          }
        }
      }

      if (score > 0) {
        categoryScores[category] = score;
      }
    }

    // Return top suggestions
    var sortedEntries = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries
        .take(maxSuggestions)
        .map((e) => e.key)
        .toList();
  }
}

// Enhanced Learning System
class ExpenseLearningSystem {
  static Map<String, ExpenseCategory> _learnedKeywords = {};
  static Map<String, int> _keywordFrequency = {};
  static final Map<ExpenseCategory, Map<String, int>> _categoryPatterns = {};

  // Load learned patterns (implement with SharedPreferences in real app)
  static Future<void> loadLearnedPatterns() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? patterns = prefs.getString('learned_patterns');
    if (patterns != null) {
      Map<String, dynamic> data = jsonDecode(patterns);
      _learnedKeywords = Map<String, ExpenseCategory>.from(
          data['keywords']?.map((k, v) => MapEntry(k, ExpenseCategory.values[v])) ?? {}
      );
      _keywordFrequency = Map<String, int>.from(data['frequency'] ?? {});
    }
  }

  static Future<void> saveLearnedPatterns() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {
      'keywords': _learnedKeywords.map((k, v) => MapEntry(k, v.index)),
      'frequency': _keywordFrequency,
    };
    await prefs.setString('learned_patterns', jsonEncode(data));
  }

  // Learn from user's manual categorization
  static Future<void> learnFromExpense(String description, ExpenseCategory category, {bool userOverride = false}) async {
    if (category == ExpenseCategory.other) return;

    List<String> keywords = EnhancedCategoryDetector.extractLearningKeywords(description);

    for (String keyword in keywords) {
      // Check if this would conflict with existing patterns
      ExpenseCategory? detectedCategory = EnhancedCategoryDetector.detectCategory(keyword);

      // Only learn if:
      // 1. User explicitly overrode the detection, OR
      // 2. No automatic detection occurred, OR
      // 3. The keyword appears frequently with this category
      if (userOverride || detectedCategory == null || _shouldUpdateLearning(keyword, category)) {
        _learnedKeywords[keyword] = category;
        _keywordFrequency[keyword] = (_keywordFrequency[keyword] ?? 0) + 1;

        // Track patterns per category
        _categoryPatterns[category] ??= {};
        _categoryPatterns[category]![keyword] = (_categoryPatterns[category]![keyword] ?? 0) + 1;

        if (kDebugMode) {
          print('🧠 Learned: "$keyword" → ${category.displayName}');
        }
      }
    }

    await saveLearnedPatterns();
  }

  static bool _shouldUpdateLearning(String keyword, ExpenseCategory category) {
    // If we've seen this keyword 3+ times with this category, learn it
    int categoryCount = _categoryPatterns[category]?[keyword] ?? 0;
    int totalCount = _keywordFrequency[keyword] ?? 0;

    return categoryCount >= 2 || (totalCount > 0 && categoryCount / totalCount > 0.6);
  }

  // Get learned keywords for detection
  static Map<String, ExpenseCategory> getLearnedKeywords() {
    return Map.from(_learnedKeywords);
  }

  // Reset learning (for testing or user preference)
  static Future<void> resetLearning() async {
    _learnedKeywords.clear();
    _keywordFrequency.clear();
    _categoryPatterns.clear();
    await saveLearnedPatterns();
  }

  // Get learning statistics
  static Map<String, dynamic> getLearningStats() {
    // Fix the mostFrequentKeywords chain
    var sortedKeywords = _keywordFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var topKeywords = sortedKeywords
        .take(10)
        .map((e) => '${e.key} (${e.value}x)')
        .toList();

    return {
      'totalKeywords': _learnedKeywords.length,
      'keywordsByCategory': _categoryPatterns.map(
              (category, keywords) => MapEntry(category.displayName, keywords.length)
      ),
      'mostFrequentKeywords': topKeywords,
    };
  }
}

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final List<UserModel> members;

  const AddExpenseScreen({
    super.key,
    required this.group,
    required this.members,
  });

  @override
  _AddExpenseScreenState createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedPaidBy;
  List<String> _selectedSplitBetween = [];
  SplitType _splitType = SplitType.equal;
  ExpenseCategory _selectedCategory = ExpenseCategory.other;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _autoDetectedCategory = false; // Track if category was auto-detected

  // Custom split amounts - Map from userId to amount/percentage
  final Map<String, TextEditingController> _customControllers = {};
  final Map<String, double> _customSplits = {};

  // Add debouncing and optimize the detection method
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _selectedPaidBy = authService.currentUser?.uid;
    _selectedSplitBetween = widget.members.map((member) => member.id).toList();

    // Initialize controllers for each member
    for (UserModel member in widget.members) {
      _customControllers[member.id] = TextEditingController();
      _customSplits[member.id] = 0.0;
    }

    // Listen to amount changes to update equal split
    _amountController.addListener(_updateEqualSplit);

    // DEBOUNCED listening to description changes
    _descriptionController.addListener(_onDescriptionChanged);

    // Load learned patterns
    ExpenseLearningSystem.loadLearnedPatterns();
  }

  void _onDescriptionChanged() {
    // Cancel previous timer
    _detectionTimer?.cancel();

    // Start new timer - only detect after user stops typing for 300ms
    _detectionTimer = Timer(const Duration(milliseconds: 300), () {
      _detectCategory();
    });
  }

  void _detectCategory() {
    String description = _descriptionController.text.toLowerCase().trim();

    if (description.length < 3) return;

    // Use the enhanced detector with learned keywords
    ExpenseCategory? detectedCategory = EnhancedCategoryDetector.detectCategory(
        description,
        learnedKeywords: ExpenseLearningSystem.getLearnedKeywords()
    );

    if (detectedCategory != null && detectedCategory != _selectedCategory) {
      setState(() {
        _selectedCategory = detectedCategory;
        _autoDetectedCategory = true;
      });
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel(); // Cancel timer on dispose
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();

    // Dispose custom controllers
    for (TextEditingController controller in _customControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _updateEqualSplit() {
    if (_splitType == SplitType.equal && _selectedSplitBetween.isNotEmpty) {
      double totalAmount = double.tryParse(_amountController.text) ?? 0;
      double equalAmount = totalAmount / _selectedSplitBetween.length;

      for (String userId in _selectedSplitBetween) {
        _customControllers[userId]?.text = equalAmount.toStringAsFixed(2);
        _customSplits[userId] = equalAmount;
      }

      // Clear amounts for non-selected members
      for (String userId in widget.members.map((m) => m.id)) {
        if (!_selectedSplitBetween.contains(userId)) {
          _customControllers[userId]?.text = '0.00';
          _customSplits[userId] = 0.0;
        }
      }
    }
  }

  void _onSplitTypeChanged(SplitType? newType) {
    setState(() {
      _splitType = newType!;

      // Clear all custom splits when changing type
      for (String userId in widget.members.map((m) => m.id)) {
        _customControllers[userId]?.text = '';
        _customSplits[userId] = 0.0;
      }

      if (_splitType == SplitType.equal) {
        _updateEqualSplit();
      } else if (_splitType == SplitType.percentage) {
        // Initialize with equal percentages
        double equalPercentage = 100.0 / _selectedSplitBetween.length;
        for (String userId in _selectedSplitBetween) {
          _customControllers[userId]?.text = equalPercentage.toStringAsFixed(1);
          _customSplits[userId] = equalPercentage;
        }
      }
    });
  }

  void _onCustomValueChanged(String userId, String value) {
    double amount = double.tryParse(value) ?? 0.0;
    _customSplits[userId] = amount;

    // Update selected split between based on who has values > 0
    setState(() {
      _selectedSplitBetween = _customSplits.entries
          .where((entry) => entry.value > 0)
          .map((entry) => entry.key)
          .toList();
    });
  }

  double _getTotalSplitAmount() {
    if (_splitType == SplitType.percentage) {
      return _customSplits.values.fold(0.0, (sum, percentage) => sum + percentage);
    } else {
      return _customSplits.values.fold(0.0, (sum, amount) => sum + amount);
    }
  }

  double _getRemainingAmount() {
    if (_splitType == SplitType.percentage) {
      return 100.0 - _getTotalSplitAmount();
    } else {
      double totalExpense = double.tryParse(_amountController.text) ?? 0;
      return totalExpense - _getTotalSplitAmount();
    }
  }

  bool _isValidSplit() {
    if (_splitType == SplitType.percentage) {
      double totalPercentage = _getTotalSplitAmount();
      return (100.0 - totalPercentage).abs() < 0.1; // Allow small rounding
    } else {
      double totalExpense = double.tryParse(_amountController.text) ?? 0;
      double totalSplit = _getTotalSplitAmount();
      return (totalExpense - totalSplit).abs() < 0.01;
    }
  }


  String _getSplitSuffix() {
    switch (_splitType) {
      case SplitType.equal:
      case SplitType.exact:
        return widget.group.currency;
      case SplitType.percentage:
        return '%';
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaidBy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select who paid')),
      );
      return;
    }
    if (_selectedSplitBetween.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select who to split between')),
      );
      return;
    }
    if (!_isValidSplit()) {
      String message = _splitType == SplitType.percentage
          ? 'Percentages must add up to 100%'
          : 'Split amounts must equal the total expense amount';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) return;

      // ENHANCED LEARNING LOGIC: Learn from this expense
      await _learnFromExpense(_descriptionController.text.trim(), _selectedCategory);

      // Prepare custom splits
      Map<String, double> customSplits = {};
      if (_splitType != SplitType.equal) {
        customSplits = Map.fromEntries(
            _customSplits.entries.where((e) => e.value > 0)
        );
      }

      final expense = ExpenseModel(
        id: '', // Will be set by Firebase
        groupId: widget.group.id,
        description: _descriptionController.text.trim(),
        amount: double.parse(_amountController.text),
        paidBy: _selectedPaidBy!,
        splitBetween: _selectedSplitBetween,
        customSplits: customSplits,
        splitType: _splitType,
        category: _selectedCategory,
        date: _selectedDate,
        createdAt: DateTime.now(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (kDebugMode) {
        print('🧪 Creating expense...');
      }

      // Create the expense with currentUserId parameter for notifications
      String expenseId = await _databaseService.createExpense(
        expense,
        currentUserId: currentUser.uid,  // Pass current user ID for notifications
      );

      if (kDebugMode) {
        print('✅ Expense created with ID: $expenseId and notifications sent');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💰 Expense added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _addExpense: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add expense: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _learnFromExpense(String description, ExpenseCategory category) async {
    bool wasAutoDetected = _autoDetectedCategory;

    await ExpenseLearningSystem.learnFromExpense(
        description,
        category,
        userOverride: !wasAutoDetected  // Learn more aggressively if user manually set category
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Add Expense'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced info banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: theme.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Categories learn from your keywords and get smarter over time.',
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Description *',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: 'e.g., beer, shop, colruyt, mcdonalds, uber...',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.description, color: theme.primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: '0.00',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.euro, color: theme.primaryColor),
                  prefix: Text(
                    '${widget.group.currency} ',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Enhanced Category with detection indicator
              DropdownButtonFormField<ExpenseCategory>(
                value: _selectedCategory,
                style: TextStyle(color: colorScheme.onSurface),
                dropdownColor: theme.cardColor,
                decoration: InputDecoration(
                  labelText: _autoDetectedCategory ? 'Category (Auto-detected)' : 'Category',
                  labelStyle: TextStyle(
                      color: _autoDetectedCategory ? Colors.green : colorScheme.onSurface.withOpacity(0.7)
                  ),
                  prefixIcon: Stack(
                    children: [
                      Icon(Icons.category, color: theme.primaryColor),
                      if (_autoDetectedCategory)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                items: ExpenseCategory.values.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text('${category.emoji} ${category.displayName}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                    _autoDetectedCategory = false; // User manually changed
                  });
                },
              ),

              const SizedBox(height: 16),

              // Date
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surface,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: theme.primaryColor),
                      const SizedBox(width: 12),
                      Text(
                        'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_drop_down, color: colorScheme.onSurface.withOpacity(0.6)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Who Paid
              Text(
                'Who Paid?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.members.map((member) {
                return RadioListTile<String>(
                  title: Text(
                    member.name,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    member.email,
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  value: member.id,
                  groupValue: _selectedPaidBy,
                  activeColor: theme.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _selectedPaidBy = value;
                    });
                  },
                );
              }),

              const SizedBox(height: 24),

              // Split Type Selection
              Text(
                'How to Split?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              // Split type chips
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Equal'),
                    selected: _splitType == SplitType.equal,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.equal),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.equal
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.equal
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Exact Amounts'),
                    selected: _splitType == SplitType.exact,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.exact),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.exact
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.exact
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Percentage'),
                    selected: _splitType == SplitType.percentage,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.percentage),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.percentage
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.percentage
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Split Between with Custom Amounts
              Text(
                'Split Between',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),

              // Show total and remaining amount for non-equal splits
              if (_splitType != SplitType.equal) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isValidSplit() ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isValidSplit() ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total ${_splitType == SplitType.percentage ? "Percentage" : "Split"}:',
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            _splitType == SplitType.percentage
                                ? '${_getTotalSplitAmount().toStringAsFixed(1)}%'
                                : '${widget.group.currency} ${_getTotalSplitAmount().toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Remaining:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            _splitType == SplitType.percentage
                                ? '${_getRemainingAmount().toStringAsFixed(1)}%'
                                : '${widget.group.currency} ${_getRemainingAmount().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isValidSplit() ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              ...widget.members.map((member) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: theme.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        if (_splitType == SplitType.equal) ...[
                          Checkbox(
                            value: _selectedSplitBetween.contains(member.id),
                            activeColor: theme.primaryColor,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedSplitBetween.add(member.id);
                                } else {
                                  _selectedSplitBetween.remove(member.id);
                                }
                                _updateEqualSplit();
                              });
                            },
                          ),
                        ],
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                member.email,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _customControllers[member.id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            enabled: _splitType != SplitType.equal,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: _getSplitSuffix(),
                              labelStyle: const TextStyle(fontSize: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              filled: true,
                              fillColor: _splitType != SplitType.equal
                                  ? colorScheme.surface
                                  : colorScheme.surface.withOpacity(0.5),
                            ),
                            onChanged: (value) => _onCustomValueChanged(member.id, value),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Notes (Optional)
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: 'Any additional details...',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.note, color: theme.primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
              ),

              const SizedBox(height: 32),

              // Add Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                      : const Text(
                    'Add Expense',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // Debug info (remove in production)
              if (_autoDetectedCategory) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🤖 Auto-detected: ${_selectedCategory.displayName}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}