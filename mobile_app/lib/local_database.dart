import "dart:convert";

import "package:path/path.dart" as path;
import "package:sqflite/sqflite.dart";

import "models.dart";

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      path.join(dbPath, "pos_mobile.db"),
      version: 2,
      onCreate: (db, version) async {
        await db.execute("""
          CREATE TABLE products (
            sku TEXT PRIMARY KEY,
            payload TEXT NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY,
            payload TEXT NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE offline_orders (
            local_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE receipts_cache (
            invoice_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE receipts_archive (
            invoice_id TEXT PRIMARY KEY,
            receipt_date TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        """);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("""
            CREATE TABLE IF NOT EXISTS receipts_archive (
              invoice_id TEXT PRIMARY KEY,
              receipt_date TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          """);
        }
      },
    );
    return _db!;
  }

  Future<void> cacheProducts(List<Product> products) async {
    final db = await database;
    final batch = db.batch();
    batch.delete("products");
    for (final product in products) {
      batch.insert(
        "products",
        {
          "sku": product.sku,
          "payload": json.encode(product.toJson()),
        },
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Product>> loadProducts() async {
    final db = await database;
    final rows = await db.query("products", orderBy: "sku ASC");
    return rows
        .map((row) => Product.fromJson(
            json.decode(row["payload"] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> cacheCustomers(List<Customer> customers) async {
    final db = await database;
    final batch = db.batch();
    batch.delete("customers");
    for (final customer in customers) {
      batch.insert(
        "customers",
        {
          "id": customer.id,
          "payload": json.encode(customer.toJson()),
        },
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Customer>> loadCustomers() async {
    final db = await database;
    final rows =
        await db.query("customers", orderBy: "name COLLATE NOCASE ASC");
    return rows
        .map((row) => Customer.fromJson(
            json.decode(row["payload"] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> cacheReceipts(List<Receipt> receipts) async {
    final db = await database;
    final batch = db.batch();
    batch.delete("receipts_cache");
    for (final receipt in receipts) {
      batch.insert(
        "receipts_cache",
        {
          "invoice_id": receipt.invoiceId,
          "payload": json.encode(receipt.toJson()),
        },
      );
      batch.insert(
        "receipts_archive",
        {
          "invoice_id": receipt.invoiceId,
          "receipt_date": _receiptDate(receipt.timestamp),
          "payload": json.encode(receipt.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await cleanupOldReceipts();
  }

  Future<List<Receipt>> loadReceipts() async {
    final db = await database;
    final rows = await db.query("receipts_cache", orderBy: "invoice_id DESC");
    return rows
        .map((row) => Receipt.fromJson(
            json.decode(row["payload"] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<List<Receipt>> loadWeeklyReceipts() async {
    final db = await database;
    await cleanupOldReceipts();
    final rows = await db.query("receipts_archive",
        orderBy: "receipt_date DESC, invoice_id DESC");
    return rows
        .map((row) => Receipt.fromJson(
            json.decode(row["payload"] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> cleanupOldReceipts() async {
    final db = await database;
    final threshold = DateTime.now().subtract(const Duration(days: 7));
    final cutoff =
        "${threshold.year.toString().padLeft(4, "0")}-${threshold.month.toString().padLeft(2, "0")}-${threshold.day.toString().padLeft(2, "0")}";
    await db.delete(
      "receipts_archive",
      where: "receipt_date < ?",
      whereArgs: [cutoff],
    );
  }

  Future<void> saveOfflineOrder(OfflineOrder order) async {
    final db = await database;
    await db.insert(
      "offline_orders",
      {
        "local_id": order.localId,
        "status": order.status,
        "created_at": order.createdAt,
        "payload": json.encode(order.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OfflineOrder>> loadOfflineOrders() async {
    final db = await database;
    final rows = await db.query("offline_orders", orderBy: "created_at DESC");
    return rows
        .map((row) => OfflineOrder.fromJson(
            json.decode(row["payload"] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateOfflineOrder(OfflineOrder order) async {
    final db = await database;
    await db.update(
      "offline_orders",
      {
        "status": order.status,
        "created_at": order.createdAt,
        "payload": json.encode(order.toJson()),
      },
      where: "local_id = ?",
      whereArgs: [order.localId],
    );
  }

  String _receiptDate(String timestamp) {
    if (timestamp.length >= 10) {
      return timestamp.substring(0, 10);
    }
    return timestamp;
  }
}
