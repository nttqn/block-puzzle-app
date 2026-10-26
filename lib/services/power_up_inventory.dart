import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_service.dart';

enum PowerUp { undo, hammer, shuffle }

extension PowerUpLabel on PowerUp {
  String get label => switch (this) {
        PowerUp.undo => 'Undo',
        PowerUp.hammer => 'Hammer',
        PowerUp.shuffle => 'Shuffle',
      };
}

/// Banked power-ups that carry over between games, on top of the engine's
/// one free use of each per game. Filled by the daily gift: one free
/// power-up per day, plus one more for watching a rewarded ad.
class PowerUpInventory extends ChangeNotifier {
  PowerUpInventory._();
  static final PowerUpInventory instance = PowerUpInventory._();

  static const _giftDateKey = 'gift_claim_date';
  static const _giftAdDateKey = 'gift_ad_date';

  final Map<PowerUp, int> _counts = {for (final p in PowerUp.values) p: 0};
  String? _giftDate;
  String? _giftAdDate;
  final Random _rng = Random();

  int count(PowerUp p) => _counts[p] ?? 0;

  bool get canClaimGift => _giftDate != todayKey();
  bool get canClaimAdBonus => _giftDate == todayKey() && _giftAdDate != todayKey();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final p in PowerUp.values) {
      _counts[p] = prefs.getInt('bank_${p.name}') ?? 0;
    }
    _giftDate = prefs.getString(_giftDateKey);
    _giftAdDate = prefs.getString(_giftAdDateKey);
    notifyListeners();
  }

  /// Spends one banked [p] if there is one. The in-memory count drops
  /// immediately so a quick double tap can't spend the same one twice.
  bool consume(PowerUp p) {
    if (count(p) <= 0) return false;
    _counts[p] = count(p) - 1;
    unawaited(_persistCount(p));
    notifyListeners();
    return true;
  }

  Future<PowerUp?> claimGift() async {
    if (!canClaimGift) return null;
    _giftDate = todayKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_giftDateKey, _giftDate!);
    return _grantRandom();
  }

  Future<PowerUp?> claimAdBonus() async {
    if (!canClaimAdBonus) return null;
    _giftAdDate = todayKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_giftAdDateKey, _giftAdDate!);
    return _grantRandom();
  }

  Future<PowerUp> _grantRandom() async {
    final p = PowerUp.values[_rng.nextInt(PowerUp.values.length)];
    _counts[p] = count(p) + 1;
    await _persistCount(p);
    notifyListeners();
    return p;
  }

  Future<void> _persistCount(PowerUp p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bank_${p.name}', count(p));
  }
}
