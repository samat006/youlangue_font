// lib/pub/ad_manager.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdManager {
  static final AdManager _instance = AdManager._internal();
  factory AdManager() => _instance;
  AdManager._internal();

  // ✅ IDS DE TEST (remplacer en production)
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-4910351400774530/8992792297'; // Test
    } else if (Platform.isIOS) {
      return 'ca-app-pub-4910351400774530/7347526370'; // Test
    }
    return '';
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-4910351400774530/2889406614'; // Test
    } else if (Platform.isIOS) {
      return 'ca-app-pub-4910351400774530/1930698104'; // Test
    }
    return '';
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-4910351400774530/3740465612'; // Test
    } else if (Platform.isIOS) {
      return 'ca-app-pub-4910351400774530/4529791343'; // Test
    }
    return '';
  }

  // ÉTAT
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  
  DateTime? _lastInterstitialTime;
  final Duration _interstitialInterval = const Duration(minutes: 2); // ✅ 2-3 min
  
  bool _isInterstitialReady = false;
  bool _isRewardedReady = false;

  // GETTERS
  bool get isInterstitialReady => _isInterstitialReady;
  bool get isRewardedReady => _isRewardedReady;

  // ═══════════════════════════════════════════════════
  // INTERSTITIAL AD (toutes les 2-3 min)
  // ═══════════════════════════════════════════════════
  
  Future<void> loadInterstitialAd() async {
    if (_isInterstitialReady) {
      print('⚠️ Interstitial déjà chargé');
      return;
    }

    await InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(
        nonPersonalizedAds: true, // ✅ NON PERSONNALISÉ
      ),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          print('✅ Interstitial chargé');
          _interstitialAd = ad;
          _isInterstitialReady = true;

          // Callback quand fermé
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              print('🚪 Interstitial fermé');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
              
              // Recharger pour la prochaine fois
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              print('❌ Erreur affichage: $error');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
            },
          );
        },
        onAdFailedToLoad: (error) {
          print('❌ Erreur chargement interstitial: $error');
          _isInterstitialReady = false;
        },
      ),
    );
  }

  Future<void> showInterstitialAd() async {
    // ✅ VÉRIFIER DÉLAI (2-3 min)
    if (_lastInterstitialTime != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastInterstitialTime!);
      if (timeSinceLastAd < _interstitialInterval) {
        print('⏱️ Interstitial trop récent (${timeSinceLastAd.inSeconds}s/${_interstitialInterval.inSeconds}s)');
        return;
      }
    }

    if (!_isInterstitialReady || _interstitialAd == null) {
      print('⚠️ Interstitial pas prêt');
      loadInterstitialAd(); // Charger pour la prochaine fois
      return;
    }

    try {
      await _interstitialAd!.show();
      _lastInterstitialTime = DateTime.now();
      print('📺 Interstitial affiché');
    } catch (e) {
      print('❌ Erreur show interstitial: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // REWARDED AD (à la demande)
  // ═══════════════════════════════════════════════════
  
  Future<void> loadRewardedAd() async {
    if (_isRewardedReady) {
      print('⚠️ Rewarded déjà chargé');
      return;
    }

    await RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(
        nonPersonalizedAds: true, // ✅ NON PERSONNALISÉ
      ),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          print('✅ Rewarded chargé');
          _rewardedAd = ad;
          _isRewardedReady = true;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              print('🚪 Rewarded fermé');
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
              
              // Recharger pour la prochaine fois
              loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              print('❌ Erreur affichage: $error');
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
            },
          );
        },
        onAdFailedToLoad: (error) {
          print('❌ Erreur chargement rewarded: $error');
          _isRewardedReady = false;
        },
      ),
    );
  }

  Future<bool> showRewardedAd() async {
    if (!_isRewardedReady || _rewardedAd == null) {
      print('⚠️ Rewarded pas prêt');
      return false;
    }

    bool rewardEarned = false;

    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          print('🎁 Récompense gagnée: ${reward.amount} ${reward.type}');
          rewardEarned = true;
        },
      );
      print('📺 Rewarded affiché');
    } catch (e) {
      print('❌ Erreur show rewarded: $e');
    }

    return rewardEarned;
  }

  // ═══════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════
  
  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}