import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Coin package offered through the native stores.
///
/// `productId` must match the product configured in App Store Connect AND
/// Google Play Console exactly. `coins` is the amount granted on a verified
/// purchase. These are consumable products.
class CoinPackage {
  final String productId;
  final int coins;
  const CoinPackage(this.productId, this.coins);
}

/// Result of a purchase attempt, surfaced to the UI.
enum StorePurchaseResult { success, cancelled, pending, failed, unavailable }

/// StoreBillingService — wraps Apple IAP / Google Play Billing for buying
/// coins. This is feature-flagged (SettingsStore.getStoreBillingEnabled); the
/// existing wallet/deposit flow remains the fallback when the flag is off or
/// the store is unavailable.
///
/// Server-side receipt validation is mandatory before coins are credited —
/// the client never grants coins directly. Validation + crediting happens in
/// [ApiService.validateIapReceipt] against `iap_validate.php`.
class StoreBillingService {
  StoreBillingService._();
  static final StoreBillingService instance = StoreBillingService._();

  // Keep these IDs in sync with the store consoles.
  static const List<CoinPackage> coinPackages = [
    CoinPackage('coins_100', 100),
    CoinPackage('coins_500', 500),
    CoinPackage('coins_1000', 1000),
    CoinPackage('coins_5000', 5000),
  ];

  static Set<String> get _productIds =>
      coinPackages.map((p) => p.productId).toSet();

  final InAppPurchase _iap = InAppPurchase.instance;
  final ApiService _api = ApiService();

  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _initialized = false;

  /// Pending completers keyed by productId so [buyCoins] can await the async
  /// purchaseStream callback.
  final Map<String, Completer<StorePurchaseResult>> _pending = {};

  /// Call once at app start (only meaningful when the feature flag is on).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) => debugPrint('IAP stream error: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Load product details (price strings, titles) from the store.
  Future<List<ProductDetails>> loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(_productIds);
      return resp.productDetails;
    } catch (e) {
      debugPrint('IAP queryProductDetails failed: $e');
      return [];
    }
  }

  /// Begin a consumable purchase. Resolves after the store + backend
  /// validation complete (or fail). Coins are credited server-side.
  Future<StorePurchaseResult> buyCoins(ProductDetails product) async {
    await init();
    if (!await isAvailable()) return StorePurchaseResult.unavailable;

    // If a purchase for this product is already in flight, reuse it.
    final existing = _pending[product.id];
    if (existing != null && !existing.isCompleted) return existing.future;

    final completer = Completer<StorePurchaseResult>();
    _pending[product.id] = completer;

    try {
      final param = PurchaseParam(productDetails: product);
      // Coins are consumable (can be bought repeatedly).
      await _iap.buyConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('IAP buyConsumable failed: $e');
      _pending.remove(product.id);
      if (!completer.isCompleted) {
        completer.complete(StorePurchaseResult.failed);
      }
    }
    return completer.future;
  }

  int _coinsForProduct(String productId) {
    for (final p in coinPackages) {
      if (p.productId == productId) return p.coins;
    }
    return 0;
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final completer = _pending[purchase.productID];

      switch (purchase.status) {
        case PurchaseStatus.pending:
          completer?.complete(StorePurchaseResult.pending);
          _pending.remove(purchase.productID);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Verify the receipt with the backend BEFORE crediting coins.
          var ok = false;
          try {
            ok = await _api.validateIapReceipt(
              productId: purchase.productID,
              coins: _coinsForProduct(purchase.productID),
              source: purchase.verificationData.source,
              receipt: purchase.verificationData.serverVerificationData,
              transactionId: purchase.purchaseID ?? '',
            );
          } catch (e) {
            debugPrint('IAP backend validation failed: $e');
          }
          // Always finish the transaction so the store stops re-delivering it.
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          completer?.complete(
              ok ? StorePurchaseResult.success : StorePurchaseResult.failed);
          _pending.remove(purchase.productID);
          break;

        case PurchaseStatus.error:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          completer?.complete(StorePurchaseResult.failed);
          _pending.remove(purchase.productID);
          break;

        case PurchaseStatus.canceled:
          completer?.complete(StorePurchaseResult.cancelled);
          _pending.remove(purchase.productID);
          break;
      }
    }
  }
}
