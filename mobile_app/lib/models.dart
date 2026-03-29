class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.user,
  });

  final String token;
  final UserSession user;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json["token"] as String? ?? "",
      user: UserSession.fromJson(
          json["user"] as Map<String, dynamic>? ?? const {}),
    );
  }
}

class UserSession {
  const UserSession({
    required this.username,
    required this.fullName,
    required this.role,
    required this.deviceId,
    required this.teamCode,
  });

  final String username;
  final String fullName;
  final String role;
  final String deviceId;
  final String teamCode;

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      username: json["username"] as String? ?? "",
      fullName: json["full_name"] as String? ?? "",
      role: json["role"] as String? ?? "",
      deviceId: json["device_id"] as String? ?? "",
      teamCode: json["team_code"] as String? ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "username": username,
      "full_name": fullName,
      "role": role,
      "device_id": deviceId,
      "team_code": teamCode,
    };
  }
}

class TeamTarget {
  const TeamTarget({
    required this.sku,
    required this.name,
    required this.quantity,
  });

  final String sku;
  final String name;
  final int quantity;

  factory TeamTarget.fromJson(Map<String, dynamic> json) {
    return TeamTarget(
      sku: json["sku"] as String? ?? "",
      name: json["name"] as String? ?? "",
      quantity: json["quantity"] as int? ?? 0,
    );
  }
}

class SalesTeamInfo {
  const SalesTeamInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.salesManName,
    required this.position,
    required this.phone,
    required this.township,
    required this.townships,
    required this.itemTargets,
  });

  final int id;
  final String code;
  final String name;
  final String salesManName;
  final String position;
  final String phone;
  final String township;
  final List<String> townships;
  final List<TeamTarget> itemTargets;

  factory SalesTeamInfo.fromJson(Map<String, dynamic> json) {
    final townships = (json["townships"] as List<dynamic>? ?? const [])
        .map((item) => "$item")
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return SalesTeamInfo(
      id: json["id"] as int? ?? 0,
      code: json["code"] as String? ?? "",
      name: json["name"] as String? ?? "",
      salesManName: json["sales_man_name"] as String? ?? "",
      position: json["position"] as String? ?? "",
      phone: json["phone"] as String? ?? "",
      township: json["township"] as String? ?? "",
      townships: townships,
      itemTargets: (json["item_targets"] as List<dynamic>? ?? const [])
          .map((item) => TeamTarget.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Product {
  const Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.stock,
    required this.category,
    required this.priceTiers,
  });

  final String sku;
  final String name;
  final double price;
  final int stock;
  final String category;
  final List<PriceTier> priceTiers;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      sku: json["sku"] as String? ?? "",
      name: json["name"] as String? ?? "",
      price: (json["price"] as num? ?? 0).toDouble(),
      stock: json["stock"] as int? ?? 0,
      category: json["category"] as String? ?? "",
      priceTiers: (json["price_tiers"] as List<dynamic>? ?? const [])
          .map((item) => PriceTier.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "sku": sku,
      "name": name,
      "price": price,
      "stock": stock,
      "category": category,
      "price_tiers": priceTiers.map((tier) => tier.toJson()).toList(),
    };
  }
}

class PriceTier {
  const PriceTier({
    required this.minQty,
    required this.unitPrice,
  });

  final int minQty;
  final double unitPrice;

  factory PriceTier.fromJson(Map<String, dynamic> json) {
    return PriceTier(
      minQty: json["min_qty"] as int? ?? 1,
      unitPrice: (json["unit_price"] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "min_qty": minQty,
      "unit_price": unitPrice,
    };
  }
}

class CartItem {
  const CartItem({
    required this.sku,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String sku;
  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      sku: json["sku"] as String? ?? "",
      name: json["name"] as String? ?? "",
      quantity: json["quantity"] as int? ?? 0,
      unitPrice: (json["unit_price"] as num? ?? 0).toDouble(),
      lineTotal: (json["line_total"] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "sku": sku,
      "name": name,
      "quantity": quantity,
      "unit_price": unitPrice,
      "line_total": lineTotal,
    };
  }
}

class CartState {
  const CartState({
    required this.items,
    required this.total,
  });

  final List<CartItem> items;
  final double total;

  factory CartState.fromJson(Map<String, dynamic> json) {
    final items = (json["items"] as List<dynamic>? ?? const [])
        .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
        .toList();
    return CartState(
      items: items,
      total: (json["total"] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "items": items.map((item) => item.toJson()).toList(),
      "total": total,
    };
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.vehicleNo,
    required this.township,
    required this.address,
    required this.teamCode,
    required this.notes,
    required this.creditBalance,
    required this.routeOrder,
    required this.preferredVisitTime,
    required this.lastVisitAt,
    required this.lastLatitude,
    required this.lastLongitude,
  });

  final int id;
  final String name;
  final String phone;
  final String email;
  final String vehicleNo;
  final String township;
  final String address;
  final String teamCode;
  final String notes;
  final double creditBalance;
  final int routeOrder;
  final String preferredVisitTime;
  final String lastVisitAt;
  final double? lastLatitude;
  final double? lastLongitude;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json["id"] as int? ?? 0,
      name: json["name"] as String? ?? "",
      phone: json["phone"] as String? ?? "",
      email: json["email"] as String? ?? "",
      vehicleNo: json["vehicle_no"] as String? ?? "",
      township: json["township"] as String? ?? "",
      address: json["address"] as String? ?? "",
      teamCode: json["team_code"] as String? ?? "",
      notes: json["notes"] as String? ?? "",
      creditBalance: (json["credit_balance"] as num? ?? 0).toDouble(),
      routeOrder: json["route_order"] as int? ?? 0,
      preferredVisitTime: json["preferred_visit_time"] as String? ?? "",
      lastVisitAt: json["last_visit_at"] as String? ?? "",
      lastLatitude: (json["last_latitude"] as num?)?.toDouble(),
      lastLongitude: (json["last_longitude"] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "phone": phone,
      "email": email,
      "vehicle_no": vehicleNo,
      "township": township,
      "address": address,
      "team_code": teamCode,
      "notes": notes,
      "credit_balance": creditBalance,
      "route_order": routeOrder,
      "preferred_visit_time": preferredVisitTime,
      "last_visit_at": lastVisitAt,
      "last_latitude": lastLatitude,
      "last_longitude": lastLongitude,
    };
  }

  Customer copyWith({
    String? address,
    String? notes,
    double? creditBalance,
    int? routeOrder,
    String? preferredVisitTime,
    String? lastVisitAt,
    Object? lastLatitude = _sentinel,
    Object? lastLongitude = _sentinel,
  }) {
    return Customer(
      id: id,
      name: name,
      phone: phone,
      email: email,
      vehicleNo: vehicleNo,
      township: township,
      address: address ?? this.address,
      teamCode: teamCode,
      notes: notes ?? this.notes,
      creditBalance: creditBalance ?? this.creditBalance,
      routeOrder: routeOrder ?? this.routeOrder,
      preferredVisitTime: preferredVisitTime ?? this.preferredVisitTime,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      lastLatitude: identical(lastLatitude, _sentinel)
          ? this.lastLatitude
          : lastLatitude as double?,
      lastLongitude: identical(lastLongitude, _sentinel)
          ? this.lastLongitude
          : lastLongitude as double?,
    );
  }
}

class Receipt {
  const Receipt({
    required this.invoiceId,
    required this.timestamp,
    required this.cashier,
    required this.invoiceTotal,
    required this.grandTotal,
    required this.discount,
    required this.items,
    required this.location,
    required this.visitNote,
  });

  final String invoiceId;
  final String timestamp;
  final String cashier;
  final double invoiceTotal;
  final double grandTotal;
  final double discount;
  final List<ReceiptItem> items;
  final GeoSnapshot? location;
  final String visitNote;

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      invoiceId: json["invoice_id"] as String? ?? "",
      timestamp: json["timestamp"] as String? ?? "",
      cashier: json["cashier"] as String? ?? "",
      invoiceTotal:
          ((json["invoice_total"] ?? json["grand_total"]) as num? ?? 0)
              .toDouble(),
      grandTotal: (json["grand_total"] as num? ?? 0).toDouble(),
      discount: (json["discount"] as num? ?? 0).toDouble(),
      items: (json["items"] as List<dynamic>? ?? const [])
          .map((item) => ReceiptItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      location: json["location"] is Map<String, dynamic>
          ? GeoSnapshot.fromJson(json["location"] as Map<String, dynamic>)
          : null,
      visitNote: json["visit_note"] as String? ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "invoice_id": invoiceId,
      "timestamp": timestamp,
      "cashier": cashier,
      "invoice_total": invoiceTotal,
      "grand_total": grandTotal,
      "discount": discount,
      "items": items.map((item) => item.toJson()).toList(),
      "location": location?.toJson(),
      "visit_note": visitNote,
    };
  }
}

class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final String sku;
  final int quantity;
  final double lineTotal;

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      name: json["name"] as String? ?? "",
      sku: json["sku"] as String? ?? "",
      quantity: json["quantity"] as int? ?? 0,
      lineTotal: (json["line_total"] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "sku": sku,
      "quantity": quantity,
      "line_total": lineTotal,
    };
  }
}

class CheckoutResult {
  const CheckoutResult({
    required this.receipt,
  });

  final Receipt receipt;

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    return CheckoutResult(
      receipt: Receipt.fromJson(
          json["receipt"] as Map<String, dynamic>? ?? const {}),
    );
  }
}

class SyncStatusSummary {
  const SyncStatusSummary({
    required this.online,
    required this.serverTime,
    required this.note,
  });

  final bool online;
  final String serverTime;
  final String note;

  factory SyncStatusSummary.fromJson(Map<String, dynamic> json) {
    return SyncStatusSummary(
      online: json["online"] as bool? ?? false,
      serverTime: json["server_time"] as String? ?? "",
      note: json["note"] as String? ?? "",
    );
  }
}

class GeoSnapshot {
  const GeoSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final String capturedAt;

  factory GeoSnapshot.fromJson(Map<String, dynamic> json) {
    return GeoSnapshot(
      latitude: (json["latitude"] as num? ?? 0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0).toDouble(),
      accuracy: (json["accuracy"] as num? ?? 0).toDouble(),
      capturedAt: json["captured_at"] as String? ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "latitude": latitude,
      "longitude": longitude,
      "accuracy": accuracy,
      "captured_at": capturedAt,
    };
  }
}

class RouteStop {
  const RouteStop({
    required this.customerId,
    required this.customerName,
    required this.address,
    required this.phone,
    required this.sequence,
    required this.priorityReason,
    required this.creditBalance,
    required this.lastVisitAt,
  });

  final int customerId;
  final String customerName;
  final String address;
  final String phone;
  final int sequence;
  final String priorityReason;
  final double creditBalance;
  final String lastVisitAt;

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      customerId: json["customer_id"] as int? ?? 0,
      customerName: json["customer_name"] as String? ?? "",
      address: json["address"] as String? ?? "",
      phone: json["phone"] as String? ?? "",
      sequence: json["sequence"] as int? ?? 0,
      priorityReason: json["priority_reason"] as String? ?? "",
      creditBalance: (json["credit_balance"] as num? ?? 0).toDouble(),
      lastVisitAt: json["last_visit_at"] as String? ?? "",
    );
  }
}

class CustomerInsights {
  const CustomerInsights({
    required this.customerId,
    required this.creditBalance,
    required this.lastPurchaseAt,
    required this.favoriteItems,
    required this.recentReceipts,
    required this.totalSpent,
  });

  final int customerId;
  final double creditBalance;
  final String lastPurchaseAt;
  final List<String> favoriteItems;
  final List<Receipt> recentReceipts;
  final double totalSpent;

  factory CustomerInsights.fromJson(Map<String, dynamic> json) {
    return CustomerInsights(
      customerId: json["customer_id"] as int? ?? 0,
      creditBalance: (json["credit_balance"] as num? ?? 0).toDouble(),
      lastPurchaseAt: json["last_purchase_at"] as String? ?? "",
      favoriteItems: (json["favorite_items"] as List<dynamic>? ?? const [])
          .map((item) => "$item")
          .toList(),
      recentReceipts: (json["recent_receipts"] as List<dynamic>? ?? const [])
          .map((item) => Receipt.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalSpent: (json["total_spent"] as num? ?? 0).toDouble(),
    );
  }
}

class MobileSalesDashboard {
  const MobileSalesDashboard({
    required this.date,
    required this.todaySales,
    required this.dailyTarget,
    required this.completionPct,
    required this.estimatedCommission,
    required this.commissionRate,
    required this.promotions,
  });

  final String date;
  final double todaySales;
  final double dailyTarget;
  final double completionPct;
  final double estimatedCommission;
  final double commissionRate;
  final List<PromotionInfo> promotions;

  factory MobileSalesDashboard.fromJson(Map<String, dynamic> json) {
    return MobileSalesDashboard(
      date: json["date"] as String? ?? "",
      todaySales: (json["today_sales"] as num? ?? 0).toDouble(),
      dailyTarget: (json["daily_target"] as num? ?? 0).toDouble(),
      completionPct: (json["completion_pct"] as num? ?? 0).toDouble(),
      estimatedCommission:
          (json["estimated_commission"] as num? ?? 0).toDouble(),
      commissionRate: (json["commission_rate"] as num? ?? 0).toDouble(),
      promotions: (json["promotions"] as List<dynamic>? ?? const [])
          .map((item) => PromotionInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PromotionInfo {
  const PromotionInfo({
    required this.code,
    required this.description,
    required this.type,
    required this.value,
    required this.category,
  });

  final String code;
  final String description;
  final String type;
  final double value;
  final String category;

  factory PromotionInfo.fromJson(Map<String, dynamic> json) {
    return PromotionInfo(
      code: json["code"] as String? ?? "",
      description: json["description"] as String? ?? "",
      type: json["type"] as String? ?? "",
      value: (json["value"] as num? ?? 0).toDouble(),
      category: json["category"] as String? ?? "",
    );
  }
}

class OfflineOrder {
  const OfflineOrder({
    required this.localId,
    required this.customerId,
    required this.discountPct,
    required this.promoCode,
    required this.items,
    required this.payments,
    required this.status,
    required this.createdAt,
    required this.lastError,
    required this.syncedReceipt,
    required this.location,
    required this.visitNote,
  });

  final String localId;
  final int? customerId;
  final double discountPct;
  final String promoCode;
  final List<CartItem> items;
  final List<Map<String, Object>> payments;
  final String status;
  final String createdAt;
  final String lastError;
  final Receipt? syncedReceipt;
  final GeoSnapshot? location;
  final String visitNote;

  bool get isSynced => status == "synced";
  bool get isPending => status == "pending";

  double get total => items.fold(0, (sum, item) => sum + item.lineTotal);

  factory OfflineOrder.fromJson(Map<String, dynamic> json) {
    return OfflineOrder(
      localId: json["local_id"] as String? ?? "",
      customerId: json["customer_id"] as int?,
      discountPct: (json["discount_pct"] as num? ?? 0).toDouble(),
      promoCode: json["promo_code"] as String? ?? "",
      items: (json["items"] as List<dynamic>? ?? const [])
          .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      payments: (json["payments"] as List<dynamic>? ?? const [])
          .map(
            (item) => Map<String, Object>.from(
              (item as Map)
                  .map((key, value) => MapEntry("$key", value as Object)),
            ),
          )
          .toList(),
      status: json["status"] as String? ?? "pending",
      createdAt: json["created_at"] as String? ?? "",
      lastError: json["last_error"] as String? ?? "",
      syncedReceipt: json["synced_receipt"] is Map<String, dynamic>
          ? Receipt.fromJson(json["synced_receipt"] as Map<String, dynamic>)
          : null,
      location: json["location"] is Map<String, dynamic>
          ? GeoSnapshot.fromJson(json["location"] as Map<String, dynamic>)
          : null,
      visitNote: json["visit_note"] as String? ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "local_id": localId,
      "customer_id": customerId,
      "discount_pct": discountPct,
      "promo_code": promoCode,
      "items": items.map((item) => item.toJson()).toList(),
      "payments": payments,
      "status": status,
      "created_at": createdAt,
      "last_error": lastError,
      "synced_receipt": syncedReceipt?.toJson(),
      "location": location?.toJson(),
      "visit_note": visitNote,
    };
  }

  OfflineOrder copyWith({
    String? localId,
    Object? customerId = _sentinel,
    double? discountPct,
    String? promoCode,
    List<CartItem>? items,
    List<Map<String, Object>>? payments,
    String? status,
    String? createdAt,
    String? lastError,
    Object? syncedReceipt = _sentinel,
    Object? location = _sentinel,
    String? visitNote,
  }) {
    return OfflineOrder(
      localId: localId ?? this.localId,
      customerId: identical(customerId, _sentinel)
          ? this.customerId
          : customerId as int?,
      discountPct: discountPct ?? this.discountPct,
      promoCode: promoCode ?? this.promoCode,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastError: lastError ?? this.lastError,
      syncedReceipt: identical(syncedReceipt, _sentinel)
          ? this.syncedReceipt
          : syncedReceipt as Receipt?,
      location: identical(location, _sentinel)
          ? this.location
          : location as GeoSnapshot?,
      visitNote: visitNote ?? this.visitNote,
    );
  }
}

const Object _sentinel = Object();
