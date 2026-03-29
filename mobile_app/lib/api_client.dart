import "dart:convert";
import "dart:async";
import "dart:io";

import "package:http/http.dart" as http;

import "models.dart";

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RequestTimeoutException implements Exception {
  const RequestTimeoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PosApiClient {
  PosApiClient({
    required this.baseUrl,
    required this.deviceId,
    this.token = "",
  });

  final String baseUrl;
  final String deviceId;
  String token;

  Uri _uri(String path) {
    final root = baseUrl.endsWith("/")
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse("$root$path");
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    return {
      "Content-Type": "application/json",
      "X-Device-ID": deviceId,
      if (token.isNotEmpty) "Authorization": "Bearer $token",
      ...?extra,
    };
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    final body = response.body.isEmpty ? "{}" : response.body;
    final jsonBody = json.decode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(jsonBody["error"] as String? ?? "Request failed");
    }
    return jsonBody;
  }

  Future<LoginResponse> login({
    required String username,
    required String password,
    String otpCode = "",
  }) async {
    final response = await _safeRequest(
      () => http.post(
        _uri("/api/login"),
        headers: _headers(),
        body: json.encode({
          "username": username,
          "password": password,
          "otp_code": otpCode,
        }),
      ),
    );
    final data = await _decode(response);
    final result = LoginResponse.fromJson(data);
    token = result.token;
    return result;
  }

  Future<List<Product>> fetchProducts() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/products"), headers: _headers()));
    final data = await _decode(response);
    return (data["products"] as List<dynamic>? ?? const [])
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CartState> fetchCart() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/cart"), headers: _headers()));
    final data = await _decode(response);
    return CartState.fromJson(data);
  }

  Future<List<Customer>> fetchCustomers() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/customers"), headers: _headers()));
    final data = await _decode(response);
    return (data["customers"] as List<dynamic>? ?? const [])
        .map((item) => Customer.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SalesTeamInfo>> fetchTeams() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/teams"), headers: _headers()));
    final data = await _decode(response);
    return (data["teams"] as List<dynamic>? ?? const [])
        .map((item) => SalesTeamInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Receipt>> fetchReceipts() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/receipts?limit=8"), headers: _headers()));
    final data = await _decode(response);
    return (data["receipts"] as List<dynamic>? ?? const [])
        .map((item) => Receipt.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> fetchPaymentOptions() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/payment-options"), headers: _headers()));
    final data = await _decode(response);
    return (data["payment_options"] as List<dynamic>? ?? const [])
        .map((item) => "$item")
        .toList();
  }

  Future<List<RouteStop>> fetchRoutePlan({required String teamCode}) async {
    final response = await _safeRequest(
      () => http.get(_uri("/api/route-plan?team_code=$teamCode"),
          headers: _headers()),
    );
    final data = await _decode(response);
    return (data["stops"] as List<dynamic>? ?? const [])
        .map((item) => RouteStop.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CustomerInsights> fetchCustomerInsights(
      {required int customerId}) async {
    final response = await _safeRequest(
      () => http.get(_uri("/api/customers/$customerId/insights"),
          headers: _headers()),
    );
    final data = await _decode(response);
    return CustomerInsights.fromJson(
        data["insights"] as Map<String, dynamic>? ?? const {});
  }

  Future<MobileSalesDashboard> fetchMobileDashboard() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/mobile/dashboard"), headers: _headers()));
    final data = await _decode(response);
    return MobileSalesDashboard.fromJson(
        data["dashboard"] as Map<String, dynamic>? ?? const {});
  }

  Future<SyncStatusSummary> fetchSyncStatus() async {
    final response = await _safeRequest(
        () => http.get(_uri("/api/sync/status"), headers: _headers()));
    final data = await _decode(response);
    return SyncStatusSummary.fromJson(data);
  }

  Future<void> addToCart({
    required String sku,
    required int qty,
  }) async {
    final response = await _safeRequest(
      () => http.post(
        _uri("/api/cart/add"),
        headers: _headers(),
        body: json.encode({"sku": sku, "qty": qty}),
      ),
    );
    await _decode(response);
  }

  Future<Customer> createCustomer({
    required String name,
    required String phone,
    String email = "",
    String vehicleNo = "",
    String township = "",
    String address = "",
  }) async {
    final response = await _safeRequest(
      () => http.post(
        _uri("/api/customers"),
        headers: _headers(),
        body: json.encode({
          "name": name,
          "phone": phone,
          "email": email,
          "vehicle_no": vehicleNo,
          "township": township,
          "address": address,
        }),
      ),
    );
    final data = await _decode(response);
    return Customer.fromJson(
        data["customer"] as Map<String, dynamic>? ?? const {});
  }

  Future<Customer> updateCustomer({
    required int customerId,
    required Map<String, Object?> payload,
  }) async {
    final response = await _safeRequest(
      () => http.patch(
        _uri("/api/customers/$customerId"),
        headers: _headers(),
        body: json.encode(payload),
      ),
    );
    final data = await _decode(response);
    return Customer.fromJson(
        data["customer"] as Map<String, dynamic>? ?? const {});
  }

  Future<CheckoutResult> checkout({
    required double discountPct,
    required String promoCode,
    required List<Map<String, Object>> payments,
    required List<CartItem> items,
    required String clientOrderId,
    GeoSnapshot? location,
    String visitNote = "",
    int? customerId,
  }) async {
    final response = await _safeRequest(
      () => http.post(
        _uri("/api/checkout"),
        headers: _headers({"Idempotency-Key": clientOrderId}),
        body: json.encode({
          "discount_pct": discountPct,
          "promo_code": promoCode,
          "payments": payments,
          "customer_id": customerId,
          "client_order_id": clientOrderId,
          "items": items.map((item) => item.toJson()).toList(),
          "location": location?.toJson(),
          "visit_note": visitNote,
        }),
      ),
    );
    final data = await _decode(response);
    return CheckoutResult.fromJson(data);
  }

  Future<http.Response> _safeRequest(
      Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw const RequestTimeoutException("Server response timed out");
    } on SocketException catch (error) {
      throw NetworkException(error.message);
    } on HttpException catch (error) {
      throw NetworkException(error.message);
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    }
  }
}
