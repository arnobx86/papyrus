import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheService {
  static const String _productsKey = 'cached_products';
  static const String _salesKey = 'cached_sales';
  static const String _purchasesKey = 'cached_purchases';
  static const String _transactionsKey = 'cached_transactions';
  static const String _partiesKey = 'cached_parties';
  static const String _ledgerKey = 'cached_ledger';
  static const String _summaryKey = 'cached_summary';

  static Future<void> saveParties(List<dynamic> parties) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_partiesKey, jsonEncode(parties));
  }

  static Future<List<dynamic>> getParties() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_partiesKey);
    return data != null ? jsonDecode(data) as List : [];
  }

  static Future<void> saveLedger(List<dynamic> ledger) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ledgerKey, jsonEncode(ledger));
  }

  static Future<List<dynamic>> getLedger() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_ledgerKey);
    return data != null ? jsonDecode(data) as List : [];
  }


  static Future<void> saveProducts(List<dynamic> products) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_productsKey, jsonEncode(products));
  }

  static Future<List<dynamic>> getProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_productsKey);
    return data != null ? jsonDecode(data) as List : [];
  }

  static Future<void> saveSummary(Map<String, dynamic> summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_summaryKey, jsonEncode(summary));
  }

  static Future<Map<String, dynamic>> getSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_summaryKey);
    return data != null ? jsonDecode(data) as Map<String, dynamic> : {};
  }

  static Future<void> saveSales(List<dynamic> sales) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_salesKey, jsonEncode(sales));
  }

  static Future<List<dynamic>> getSales() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_salesKey);
    return data != null ? jsonDecode(data) as List : [];
  }

  static Future<void> savePurchases(List<dynamic> purchases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_purchasesKey, jsonEncode(purchases));
  }

  static Future<List<dynamic>> getPurchases() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_purchasesKey);
    return data != null ? jsonDecode(data) as List : [];
  }

  static Future<void> saveTransactions(List<dynamic> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_transactionsKey, jsonEncode(transactions));
  }

  static Future<List<dynamic>> getTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_transactionsKey);
    return data != null ? jsonDecode(data) as List : [];
  }
}
