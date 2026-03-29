import "dart:convert";
import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;
import "package:printing/printing.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;

import "api_client.dart";
import "local_database.dart";
import "models.dart";

const List<_SalesTeam> _fallbackSalesTeams = [
  _SalesTeam(
      code: "THM",
      label: "Sale Team - 3 (THM)",
      township: "သထုံ",
      townships: ["သထုံ"]),
  _SalesTeam(
      code: "AHT",
      label: "Sale Team - 3 (AHT)",
      township: "အောင်သာယာ",
      townships: ["အောင်သာယာ"]),
  _SalesTeam(
      code: "YGN",
      label: "Sale Team - 1 (YGN)",
      township: "ရန်ကုန်",
      townships: ["ရန်ကုန်"]),
  _SalesTeam(
      code: "MLM",
      label: "Sale Team - 2 (MLM)",
      township: "မော်လမြိုင်",
      townships: ["မော်လမြိုင်"]),
];

const List<String> _defaultPaymentOptions = [
  "cash",
  "card",
  "mobile_wallet",
  "bank_transfer"
];

bool _isAuthFailureMessage(String message) {
  final normalized = message.trim().toLowerCase();
  return normalized == "invalid token" ||
      normalized == "missing bearer token" ||
      normalized == "device mismatch for active token";
}

String _formatKs(num amount) => "Ks ${amount.toStringAsFixed(0)}";

String _slipCustomerLabel(Customer? customer) {
  if (customer == null) return "-";
  if (customer.name.trim().isNotEmpty) return customer.name.trim();
  if (customer.phone.trim().isNotEmpty) return customer.phone.trim();
  return "-";
}

Future<Uint8List> _buildSlipPdf({
  required Receipt receipt,
  required Customer? customer,
}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  "Shwe Htoo Thit",
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text("Invoice ${receipt.invoiceId}")),
              pw.SizedBox(height: 20),
              pw.Text("Customer: ${_slipCustomerLabel(customer)}"),
              pw.Text("Cashier: ${receipt.cashier}"),
              pw.Text("Time: ${receipt.timestamp}"),
              if (customer?.address.trim().isNotEmpty ?? false)
                pw.Text("Address: ${customer!.address.trim()}"),
              if (receipt.location != null)
                pw.Text(
                  "GPS: ${receipt.location!.latitude.toStringAsFixed(5)}, ${receipt.location!.longitude.toStringAsFixed(5)}",
                ),
              if (receipt.visitNote.trim().isNotEmpty)
                pw.Text("Note: ${receipt.visitNote.trim()}"),
              pw.SizedBox(height: 18),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("Item", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("Total", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...receipt.items.map(
                    (item) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text("${item.name} (${item.sku})"),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text("${item.quantity}"),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(_formatKs(item.lineTotal)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text("Discount"), pw.Text(_formatKs(receipt.discount))],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text("Grand Total"), pw.Text(_formatKs(receipt.grandTotal))],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Invoice Total", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(_formatKs(receipt.invoiceTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  return pdf.save();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShweHtooThitMobileApp());
}

class ShweHtooThitMobileApp extends StatelessWidget {
  const ShweHtooThitMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "သူဌေးမင်း စားသုံးဆီ",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        fontFamily: "Noto Sans Myanmar",
        fontFamilyFallback: const [
          "Pyidaungsu",
          "Noto Sans Myanmar",
          "Roboto",
          "sans-serif"
        ],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF111827), height: 1.35),
          bodyMedium: TextStyle(color: Color(0xFF111827), height: 1.35),
          titleLarge:
              TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      ),
      home: const BootScreen(),
    );
  }
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  bool _loading = true;
  String _baseUrl = "";
  String _deviceId = "";
  String _token = "";
  String _selectedTeamCode = "";
  UserSession? _session;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl =
        prefs.getString("base_url") ?? "http://192.168.1.100:8000";
    final savedDeviceId = prefs.getString("device_id") ?? _randomDeviceId();
    final savedToken = prefs.getString("token") ?? "";
    final savedSelectedTeamCode = prefs.getString("selected_team_code") ?? "";
    final sessionJson = prefs.getString("session_json");

    UserSession? session;
    if (sessionJson != null && sessionJson.isNotEmpty) {
      session = UserSession.fromJson(
          json.decode(sessionJson) as Map<String, dynamic>);
    }
    await prefs.setString("device_id", savedDeviceId);

    if (!mounted) {
      return;
    }

    setState(() {
      _baseUrl = savedBaseUrl;
      _deviceId = savedDeviceId;
      _token = savedToken;
      _selectedTeamCode =
          session != null && session.teamCode.trim().isNotEmpty
              ? session.teamCode.trim().toUpperCase()
              : savedSelectedTeamCode;
      _session = session;
      _loading = false;
    });
  }

  String _randomDeviceId() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    final random = Random();
    final suffix =
        List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
    return "MOBILE-$suffix";
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token.isNotEmpty && _session != null) {
      return TeamSelectionScreen(
        baseUrl: _baseUrl,
        deviceId: _deviceId,
        token: _token,
        session: _session!,
        initialSelectedTeamCode: _selectedTeamCode,
      );
    }

    return LoginScreen(
      initialBaseUrl: _baseUrl,
      initialDeviceId: _deviceId,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.initialBaseUrl,
    required this.initialDeviceId,
    this.initialError = "",
  });

  final String initialBaseUrl;
  final String initialDeviceId;
  final String initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _deviceIdController;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _submitting = false;
  String _error = "";

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.initialBaseUrl);
    _deviceIdController = TextEditingController(text: widget.initialDeviceId);
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _deviceIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = "";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("base_url", _baseUrlController.text.trim());
      await prefs.setString(
          "device_id", _deviceIdController.text.trim().toUpperCase());

      final client = PosApiClient(
        baseUrl: _baseUrlController.text.trim(),
        deviceId: _deviceIdController.text.trim().toUpperCase(),
      );

      final login = await client.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        otpCode: _otpController.text.trim(),
      );

      await prefs.setString("token", login.token);
      await prefs.setString("session_json", json.encode(login.user.toJson()));
      final assignedTeamCode = login.user.teamCode.trim().toUpperCase();
      if (assignedTeamCode.isNotEmpty) {
        await prefs.setString("selected_team_code", assignedTeamCode);
      } else {
        await prefs.remove("selected_team_code");
      }

      if (!mounted) {
        return;
      }

      if (assignedTeamCode.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SalesHomeScreen(
              baseUrl: _baseUrlController.text.trim(),
              deviceId: _deviceIdController.text.trim().toUpperCase(),
              token: login.token,
              session: login.user,
              initialSelectedTeamCode: assignedTeamCode,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TeamSelectionScreen(
              baseUrl: _baseUrlController.text.trim(),
              deviceId: _deviceIdController.text.trim().toUpperCase(),
              token: login.token,
              session: login.user,
              initialSelectedTeamCode: "",
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF174F45),
                    Color(0xFF0F766E),
                    Color(0xFF2AA198)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Mobile Sales App",
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Sales staff can log in with the account created by admin and create invoices while visiting shops.",
                    style: TextStyle(color: Color(0xFFD7F8F2), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _CardBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Backend URL",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      hintText: "http://192.168.1.100:8000",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("Device ID",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _deviceIdController,
                    decoration: const InputDecoration(
                      hintText: "MOBILE-SALES-01",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text("Username",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    decoration:
                        const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "Admin created sales account",
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text("Password",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter account password",
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("OTP if required",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otpController,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : () => _submit(),
                      child: Text(
                          _submitting ? "Signing In..." : "Login From Phone"),
                    ),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_error,
                        style: const TextStyle(color: Color(0xFFB42318))),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    "Admin က Accounts tab ထဲမှာဖွင့်ပေးထားတဲ့ sales account နဲ့ဝင်ပါ။ Device restriction သတ်မှတ်ထားရင် authorized phone ကိုပဲ အသုံးပြုနိုင်ပါတယ်။",
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TeamSelectionScreen extends StatefulWidget {
  const TeamSelectionScreen({
    super.key,
    required this.baseUrl,
    required this.deviceId,
    required this.token,
    required this.session,
    required this.initialSelectedTeamCode,
  });

  final String baseUrl;
  final String deviceId;
  final String token;
  final UserSession session;
  final String initialSelectedTeamCode;

  @override
  State<TeamSelectionScreen> createState() => _TeamSelectionScreenState();
}

class _TeamSelectionScreenState extends State<TeamSelectionScreen> {
  late String _selectedTeamCode;
  late final PosApiClient _client;
  List<_SalesTeam> _teams = _fallbackSalesTeams;
  bool _loadingTeams = true;
  String _lockedTeamCode = "";

  @override
  void initState() {
    super.initState();
    _client = PosApiClient(
      baseUrl: widget.baseUrl,
      deviceId: widget.deviceId,
      token: widget.token,
    );
    _selectedTeamCode = _fallbackSalesTeams
            .any((team) => team.code == widget.initialSelectedTeamCode)
        ? widget.initialSelectedTeamCode
        : _fallbackSalesTeams.first.code;
    unawaited(_initializeTeamSelection());
  }

  Future<void> _initializeTeamSelection() async {
    final lockedTeamCode = widget.session.teamCode.trim().toUpperCase();
    if (mounted && lockedTeamCode.isNotEmpty) {
      setState(() {
        _lockedTeamCode = lockedTeamCode;
        _selectedTeamCode = lockedTeamCode;
      });
    }
    await _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await _client.fetchTeams();
      if (!mounted) {
        return;
      }
      final mappedTeams = teams
          .map((team) => _SalesTeam.fromServer(team))
          .where((team) => team.code.isNotEmpty)
          .toList();
      setState(() {
        _teams = mappedTeams.isEmpty ? _fallbackSalesTeams : mappedTeams;
        if (!_teams.any((team) => team.code == _selectedTeamCode)) {
          _selectedTeamCode = _teams.first.code;
        }
        if (_lockedTeamCode.isNotEmpty &&
            _teams.any((team) => team.code == _lockedTeamCode)) {
          _selectedTeamCode = _lockedTeamCode;
        }
        _loadingTeams = false;
      });
    } on ApiException catch (error) {
      if (_isAuthFailureMessage(error.message)) {
        await _redirectToLogin(error.message);
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _teams = _fallbackSalesTeams;
        _loadingTeams = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _teams = _fallbackSalesTeams;
        _loadingTeams = false;
      });
    }
  }

  Future<void> _redirectToLogin(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("session_json");
    await prefs.remove("selected_team_code");
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          initialBaseUrl: widget.baseUrl,
          initialDeviceId: widget.deviceId,
          initialError: "Session expired: $reason. Please sign in again.",
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("selected_team_code", _selectedTeamCode);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SalesHomeScreen(
          baseUrl: widget.baseUrl,
          deviceId: widget.deviceId,
          token: widget.token,
          session: widget.session,
          initialSelectedTeamCode: _selectedTeamCode,
        ),
      ),
    );
  }

  Future<void> _switchAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("session_json");
    await prefs.remove("selected_team_code");
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          initialBaseUrl: widget.baseUrl,
          initialDeviceId: widget.deviceId,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sale Team")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF174F45),
                    Color(0xFF0F766E),
                    Color(0xFF2AA198)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "အရောင်းအသင်းရွေးချယ်ပါ",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Admin က account ကို sale team တစ်ခုနဲ့ချိတ်ထားရင် ဒီနေရာမှာ auto lock ဖြစ်ပြီး သက်ဆိုင်ရာ data ပဲမြင်ရပါမယ်။",
                    style: TextStyle(color: Color(0xFFD7F8F2), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _CardBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Sale Team",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTeamCode,
                    decoration: const InputDecoration(
                      labelText: "Sale Team ရွေးပါ",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFFF9F4EA),
                    ),
                    items: _teams
                        .map(
                          (team) => DropdownMenuItem<String>(
                            value: team.code,
                            child: Text(team.label),
                          ),
                        )
                        .toList(),
                    onChanged: _lockedTeamCode.isNotEmpty
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedTeamCode = value);
                          },
                  ),
                  const SizedBox(height: 14),
                  if (_lockedTeamCode.isNotEmpty)
                    const Text(
                      "ဒီ account ကို admin က sale team တစ်ခုတည်းနဲ့ချိတ်ထားပါတယ်။ နောက်တစ်ယောက်ဝင်မယ်ဆို Switch Account ကိုနှိပ်ပါ။",
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  if (_lockedTeamCode.isNotEmpty)
                    const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _teams
                              .firstWhere(
                                  (team) => team.code == _selectedTeamCode)
                              .label,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _teams
                              .firstWhere(
                                  (team) => team.code == _selectedTeamCode)
                              .townshipLabel,
                          style: const TextStyle(color: Color(0xFF6B5E4A)),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingTeams) ...[
                    const SizedBox(height: 12),
                    const Text(
                      "Team data ကို server ကနေ update လုပ်နေပါတယ်...",
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _continue,
                child: Text(_lockedTeamCode.isNotEmpty ? "Open Team" : "Continue"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _switchAccount,
                child: const Text("Switch Account"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesHomeScreen extends StatefulWidget {
  const SalesHomeScreen({
    super.key,
    required this.baseUrl,
    required this.deviceId,
    required this.token,
    required this.session,
    required this.initialSelectedTeamCode,
  });

  final String baseUrl;
  final String deviceId;
  final String token;
  final UserSession session;
  final String initialSelectedTeamCode;

  @override
  State<SalesHomeScreen> createState() => _SalesHomeScreenState();
}

class _SalesHomeScreenState extends State<SalesHomeScreen> {
  late final PosApiClient _client;
  final LocalDatabase _db = LocalDatabase.instance;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController =
      TextEditingController(text: "0");
  final TextEditingController _promoController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _newCustomerNameController =
      TextEditingController();
  final TextEditingController _newCustomerPhoneController =
      TextEditingController();
  final TextEditingController _newCustomerAddressController =
      TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _startupBusy = true;
  String _message = "";
  String _error = "";

  bool get _isTeamLocked => widget.session.teamCode.trim().isNotEmpty;

  List<Product> _products = const [];
  List<Customer> _customers = const [];
  List<_SalesTeam> _availableTeams = _fallbackSalesTeams;
  List<Receipt> _receipts = const [];
  List<Receipt> _weeklyReceipts = const [];
  List<OfflineOrder> _offlineOrders = const [];
  List<RouteStop> _routeStops = const [];
  List<String> _paymentOptions = _defaultPaymentOptions;
  CartState _cart = const CartState(items: [], total: 0);
  List<_PaymentInput> _payments = [
    const _PaymentInput(method: "cash", amount: "")
  ];
  int? _selectedCustomerId;
  late String _selectedTeamCode;
  int _currentTab = 0;
  int _salesStage = 0;
  Receipt? _latestReceipt;
  CustomerInsights? _customerInsights;
  GeoSnapshot? _currentLocation;
  MobileSalesDashboard? _mobileDashboard;
  Timer? _syncTimer;
  bool _syncOnline = false;
  bool _syncingQueue = false;
  bool _speechReady = false;
  String _activeVoiceField = "";

  @override
  void initState() {
    super.initState();
    _selectedTeamCode = _fallbackSalesTeams
            .any((team) => team.code == widget.initialSelectedTeamCode)
        ? widget.initialSelectedTeamCode
        : _fallbackSalesTeams.first.code;
    _client = PosApiClient(
      baseUrl: widget.baseUrl,
      deviceId: widget.deviceId,
      token: widget.token,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    _discountController.dispose();
    _promoController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _newCustomerNameController.dispose();
    _newCustomerPhoneController.dispose();
    _newCustomerAddressController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = false;
        _startupBusy = true;
      });
    }
    unawaited(_initSpeech());
    unawaited(_safeWarmStart());
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _syncPendingOrders(showSuccessMessage: false);
    });
  }

  Future<void> _safeWarmStart() async {
    try {
      await _loadCachedData().timeout(const Duration(seconds: 2));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _error.isEmpty
              ? "Local cache ကိုဖွင့်ရာမှာ နှေးနေပါတယ်။ App shell ကိုအရင်ဖွင့်ထားပါတယ်။"
              : _error;
        });
      }
    }

    try {
      await _loadData().timeout(const Duration(seconds: 8));
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncOnline = false;
          _error = _error.isEmpty
              ? "Server response ကြာနေပါတယ်။ Local mode နဲ့အရင်သုံးနိုင်ပါတယ်။"
              : _error;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _startupBusy = false);
      }
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady =
          await _speech.initialize().timeout(const Duration(seconds: 2));
    } catch (_) {
      _speechReady = false;
    }
  }

  Future<void> _loadCachedData() async {
    final products = await _db.loadProducts();
    final customers = await _db.loadCustomers();
    final receipts = await _db.loadReceipts();
    final weeklyReceipts = await _db.loadWeeklyReceipts();
    final offlineOrders = await _db.loadOfflineOrders();
    if (!mounted) {
      return;
    }
    setState(() {
      _products = products;
      _customers = customers;
      _receipts = receipts;
      _weeklyReceipts = weeklyReceipts;
      _offlineOrders = offlineOrders;
      _routeStops = _buildOfflineRoutePlan(customers);
      if (products.isNotEmpty ||
          customers.isNotEmpty ||
          receipts.isNotEmpty ||
          weeklyReceipts.isNotEmpty) {
        _loading = false;
      }
    });
    if (_selectedCustomerId != null) {
      _loadCustomerInsights(useOffline: true);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _error = "";
      _startupBusy = true;
    });

    try {
      final results = await Future.wait([
        _client.fetchProducts(),
        _client.fetchCustomers(),
        _client.fetchTeams(),
        _client.fetchPaymentOptions(),
        _client.fetchSyncStatus(),
      ]);

      if (!mounted) {
        return;
      }

      final fetchedProducts = results[0] as List<Product>;
      final fetchedCustomers = results[1] as List<Customer>;
      final fetchedTeams = results[2] as List<SalesTeamInfo>;
      final paymentOptions = results[3] as List<String>;
      final syncStatus = results[4] as SyncStatusSummary;
      final availableTeams = fetchedTeams
          .map((team) => _SalesTeam.fromServer(team))
          .where((team) => team.code.isNotEmpty)
          .toList();
      await _db.cacheProducts(fetchedProducts);
      await _db.cacheCustomers(fetchedCustomers);
      final offlineOrders = await _db.loadOfflineOrders();
      setState(() {
        _products = fetchedProducts;
        _customers = fetchedCustomers;
        _availableTeams =
            availableTeams.isEmpty ? _fallbackSalesTeams : availableTeams;
        _offlineOrders = offlineOrders;
        _routeStops = _buildOfflineRoutePlan(fetchedCustomers);
        _paymentOptions = paymentOptions;
        _syncOnline = syncStatus.online;
        _loading = false;
        if (!_availableTeams.any((team) => team.code == _selectedTeamCode)) {
          _selectedTeamCode = _availableTeams.first.code;
        }
        _payments = _payments
            .map((item) => item.copyWith(
                  method: paymentOptions.contains(item.method)
                      ? item.method
                      : paymentOptions.firstOrNull ?? "cash",
                ))
            .toList();
      });
      unawaited(_loadDeferredData());
    } on RequestTimeoutException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncOnline = false;
        _loading = false;
      });
      _setFeedback(
          message: "App ကို local data နဲ့ဖွင့်ထားပါတယ်။ ${error.message}");
    } on NetworkException {
      final offlineOrders = await _db.loadOfflineOrders();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncOnline = false;
        _offlineOrders = offlineOrders;
        _routeStops = _buildOfflineRoutePlan(_customers);
        _loading = false;
      });
      await _loadCustomerInsights(useOffline: true);
      _setFeedback(
          message:
              "Offline mode: local products, customers, and vouchers are ready.");
    } on ApiException catch (error) {
      if (_isAuthFailureMessage(error.message)) {
        await _handleAuthFailure(error.message);
        return;
      }
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _startupBusy = false;
        });
      }
    }
  }

  Future<void> _loadDeferredData() async {
    try {
      final results = await Future.wait([
        _client.fetchReceipts(),
        _client.fetchRoutePlan(teamCode: _selectedTeamCode),
        _client.fetchMobileDashboard(),
      ]);
      final fetchedReceipts = results[0] as List<Receipt>;
      final routeStops = results[1] as List<RouteStop>;
      final mobileDashboard = results[2] as MobileSalesDashboard;
      await _db.cacheReceipts(fetchedReceipts);
      final weeklyReceipts = await _db.loadWeeklyReceipts();
      if (!mounted) {
        return;
      }
      setState(() {
        _receipts = fetchedReceipts;
        _weeklyReceipts = weeklyReceipts;
        _routeStops = routeStops;
        _mobileDashboard = mobileDashboard;
      });
      await _loadCustomerInsights(useOffline: false);
      await _syncPendingOrders(showSuccessMessage: false);
    } on RequestTimeoutException {
      if (_selectedCustomerId != null) {
        await _loadCustomerInsights(useOffline: true);
      }
    } on NetworkException {
      if (_selectedCustomerId != null) {
        await _loadCustomerInsights(useOffline: true);
      }
    } on ApiException catch (error) {
      if (_isAuthFailureMessage(error.message)) {
        await _handleAuthFailure(error.message);
        return;
      }
      if (mounted) {
        setState(() => _error = error.message);
      }
    }
  }

  Future<void> _handleAuthFailure(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("session_json");
    await prefs.remove("selected_team_code");
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          initialBaseUrl: widget.baseUrl,
          initialDeviceId: widget.deviceId,
          initialError: "Session expired: $reason. Please sign in again.",
        ),
      ),
      (_) => false,
    );
  }

  List<RouteStop> _buildOfflineRoutePlan(List<Customer> customers) {
    final teamCustomers = customers
        .where((customer) => customer.teamCode == _selectedTeamCode)
        .toList()
      ..sort((a, b) {
        final aOrder = a.routeOrder > 0 ? a.routeOrder : 9999;
        final bOrder = b.routeOrder > 0 ? b.routeOrder : 9999;
        final byOrder = aOrder.compareTo(bOrder);
        if (byOrder != 0) {
          return byOrder;
        }
        return (a.lastVisitAt.isEmpty ? "0000" : a.lastVisitAt)
            .compareTo(b.lastVisitAt.isEmpty ? "0000" : b.lastVisitAt);
      });
    return [
      for (var i = 0; i < teamCustomers.length; i++)
        RouteStop(
          customerId: teamCustomers[i].id,
          customerName: teamCustomers[i].name.isEmpty
              ? teamCustomers[i].phone
              : teamCustomers[i].name,
          address: teamCustomers[i].address,
          phone: teamCustomers[i].phone,
          sequence: i + 1,
          priorityReason: teamCustomers[i].creditBalance > 0
              ? "Credit collection due"
              : "Offline route order",
          creditBalance: teamCustomers[i].creditBalance,
          lastVisitAt: teamCustomers[i].lastVisitAt,
        ),
    ];
  }

  Future<void> _loadCustomerInsights({required bool useOffline}) async {
    if (_selectedCustomerId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _customerInsights = null;
        _addressController.clear();
        _notesController.clear();
      });
      return;
    }

    if (useOffline) {
      final insights = _buildOfflineInsights(_selectedCustomerId!);
      final customer = _selectedCustomer;
      if (!mounted) {
        return;
      }
      setState(() {
        _customerInsights = insights;
        _addressController.text = customer?.address ?? "";
        _notesController.text = customer?.notes ?? "";
      });
      return;
    }

    try {
      final insights =
          await _client.fetchCustomerInsights(customerId: _selectedCustomerId!);
      final customer = _selectedCustomer;
      if (!mounted) {
        return;
      }
      setState(() {
        _customerInsights = insights;
        _addressController.text = customer?.address ?? "";
        _notesController.text = customer?.notes ?? "";
      });
    } on NetworkException {
      await _loadCustomerInsights(useOffline: true);
    } on ApiException catch (error) {
      _setFeedback(error: error.message);
    }
  }

  CustomerInsights _buildOfflineInsights(int customerId) {
    final sales = _receipts
        .where((receipt) => _saleBelongsToCustomer(receipt, customerId))
        .toList();
    final itemTotals = <String, int>{};
    var totalSpent = 0.0;
    for (final receipt in sales) {
      totalSpent += receipt.invoiceTotal;
      for (final item in receipt.items) {
        itemTotals[item.name] = (itemTotals[item.name] ?? 0) + item.quantity;
      }
    }
    final favoriteItems = itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final customer = _customers.firstWhere(
      (item) => item.id == customerId,
      orElse: () => const Customer(
        id: 0,
        name: "",
        phone: "",
        email: "",
        vehicleNo: "",
        township: "",
        address: "",
        teamCode: "",
        notes: "",
        creditBalance: 0,
        routeOrder: 0,
        preferredVisitTime: "",
        lastVisitAt: "",
        lastLatitude: null,
        lastLongitude: null,
      ),
    );
    return CustomerInsights(
      customerId: customerId,
      creditBalance: customer.creditBalance,
      lastPurchaseAt: sales.isNotEmpty ? sales.first.timestamp : "",
      favoriteItems: favoriteItems.take(3).map((entry) => entry.key).toList(),
      recentReceipts: sales.take(5).toList(),
      totalSpent: totalSpent,
    );
  }

  bool _saleBelongsToCustomer(Receipt receipt, int customerId) {
    final order = _offlineOrders.firstWhere(
      (item) =>
          item.syncedReceipt?.invoiceId == receipt.invoiceId &&
          item.customerId == customerId,
      orElse: () => const OfflineOrder(
        localId: "",
        customerId: null,
        discountPct: 0,
        promoCode: "",
        items: [],
        payments: [],
        status: "",
        createdAt: "",
        lastError: "",
        syncedReceipt: null,
        location: null,
        visitNote: "",
      ),
    );
    return order.customerId == customerId;
  }

  Future<void> _selectCustomer(int? customerId) async {
    setState(() => _selectedCustomerId = customerId);
    await _loadCustomerInsights(useOffline: !_syncOnline);
  }

  void _setFeedback({String message = "", String error = ""}) {
    setState(() {
      _message = message;
      _error = error;
    });
    if (message.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF166534),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _rebuildCart() {
    final total =
        _cart.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    _cart = CartState(items: List<CartItem>.from(_cart.items), total: total);
  }

  double _unitPriceForQuantity(Product product, int qty) {
    var unitPrice = product.price;
    for (final tier in product.priceTiers) {
      if (qty >= tier.minQty) {
        unitPrice = tier.unitPrice;
      }
    }
    return unitPrice;
  }

  String _newOfflineId() {
    return "offline-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}";
  }

  OfflineOrder _buildOfflineOrder() {
    final payments = _payments
        .where((item) => item.amount.trim().isNotEmpty)
        .map((item) => {
              "method": item.method,
              "amount": double.tryParse(item.amount.trim()) ?? 0
            })
        .where((item) => (item["amount"] as double) > 0)
        .map((item) => Map<String, Object>.from(item))
        .toList();

    if (payments.isEmpty) {
      throw const ApiException("Enter at least one payment amount");
    }

    return OfflineOrder(
      localId: _newOfflineId(),
      customerId: _selectedCustomerId,
      discountPct: double.tryParse(_discountController.text.trim()) ?? 0,
      promoCode: _promoController.text.trim().toUpperCase(),
      items: List<CartItem>.from(_cart.items),
      payments: payments,
      status: "pending",
      createdAt: DateTime.now().toIso8601String(),
      lastError: "",
      syncedReceipt: null,
      location: _currentLocation,
      visitNote: _notesController.text.trim(),
    );
  }

  Future<void> _queueOfflineOrder(OfflineOrder order,
      {String reason = ""}) async {
    await _db
        .saveOfflineOrder(order.copyWith(lastError: reason, status: "pending"));
    final offlineOrders = await _db.loadOfflineOrders();
    if (!mounted) {
      return;
    }
    setState(() {
      _offlineOrders = offlineOrders;
      _latestReceipt = _offlineReceiptFromOrder(order);
      _cart = const CartState(items: [], total: 0);
      _discountController.text = "0";
      _promoController.clear();
      _payments = [
        _PaymentInput(method: _paymentOptions.firstOrNull ?? "cash", amount: "")
      ];
      _salesStage = 2;
      _syncOnline = false;
    });
  }

  Receipt _offlineReceiptFromOrder(OfflineOrder order) {
    return Receipt(
      invoiceId: "Pending",
      timestamp: order.createdAt,
      cashier: widget.session.username,
      invoiceTotal: order.total,
      grandTotal: order.total,
      discount: 0,
      items: order.items
          .map(
            (item) => ReceiptItem(
              name: item.name,
              sku: item.sku,
              quantity: item.quantity,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      location: order.location,
      visitNote: order.visitNote,
    );
  }

  Future<void> _captureLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const ApiException("Location service ပိတ်ထားပါတယ်");
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ApiException("Location permission မရရှိပါ");
      }
      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) {
        return;
      }
      setState(() {
        _currentLocation = GeoSnapshot(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          capturedAt: DateTime.now().toIso8601String(),
        );
      });
    } on ApiException catch (error) {
      _setFeedback(error: error.message);
    } catch (error) {
      _setFeedback(error: "GPS location မရပါ: $error");
    }
  }

  Future<void> _startVoiceInput(String field) async {
    if (!_speechReady) {
      _setFeedback(error: "Voice input မရပါသေးဘူး");
      return;
    }
    if (_speech.isListening && _activeVoiceField == field) {
      await _speech.stop();
      if (mounted) {
        setState(() => _activeVoiceField = "");
      }
      return;
    }
    setState(() => _activeVoiceField = field);
    await _speech.listen(
      localeId: "my_MM",
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (field == "address") {
          _addressController.text = text;
        } else {
          _notesController.text = text;
        }
        if (result.finalResult && mounted) {
          setState(() => _activeVoiceField = "");
        }
      },
    );
  }

  Future<void> _saveCustomerProfile() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      _setFeedback(error: "customer name ကို အရင်ရွေးပါ");
      return;
    }
    final updatedCustomer = customer.copyWith(
      address: _addressController.text.trim(),
      notes: _notesController.text.trim(),
      lastVisitAt: _currentLocation != null
          ? DateTime.now().toIso8601String()
          : customer.lastVisitAt,
      lastLatitude: _currentLocation?.latitude,
      lastLongitude: _currentLocation?.longitude,
    );
    try {
      if (_syncOnline) {
        final saved = await _client.updateCustomer(
          customerId: customer.id,
          payload: {
            "address": updatedCustomer.address,
            "notes": updatedCustomer.notes,
            "last_visit_at": updatedCustomer.lastVisitAt,
            "last_latitude": updatedCustomer.lastLatitude,
            "last_longitude": updatedCustomer.lastLongitude,
          },
        );
        final nextCustomers = _customers
            .map((item) => item.id == saved.id ? saved : item)
            .toList();
        await _db.cacheCustomers(nextCustomers);
        if (!mounted) {
          return;
        }
        setState(() {
          _customers = nextCustomers;
          _routeStops =
              _syncOnline ? _routeStops : _buildOfflineRoutePlan(nextCustomers);
        });
      } else {
        final nextCustomers = _customers
            .map((item) =>
                item.id == updatedCustomer.id ? updatedCustomer : item)
            .toList();
        await _db.cacheCustomers(nextCustomers);
        if (!mounted) {
          return;
        }
        setState(() {
          _customers = nextCustomers;
          _routeStops = _buildOfflineRoutePlan(nextCustomers);
        });
      }
      _setFeedback(message: "Customer address / notes updated");
    } on ApiException catch (error) {
      _setFeedback(error: error.message);
    } on NetworkException {
      final nextCustomers = _customers
          .map((item) => item.id == updatedCustomer.id ? updatedCustomer : item)
          .toList();
      await _db.cacheCustomers(nextCustomers);
      if (!mounted) {
        return;
      }
      setState(() {
        _customers = nextCustomers;
        _routeStops = _buildOfflineRoutePlan(nextCustomers);
        _syncOnline = false;
      });
      _setFeedback(
          message: "Customer note ကို phone ထဲမှာ update သိမ်းထားပါတယ်။");
    }
  }

  Future<void> _createCustomer({
    required String name,
    required String phone,
    required String township,
    required String address,
  }) async {
    if (!_syncOnline) {
      _setFeedback(error: "Customer create လုပ်ဖို့ online ဖြစ်နေဖို့လိုပါတယ်");
      return;
    }
    final created = await _client.createCustomer(
      name: name,
      phone: phone,
      township: township,
      address: address,
    );
    final nextCustomers = [..._customers, created];
    await _db.cacheCustomers(nextCustomers);
    if (!mounted) {
      return;
    }
    setState(() {
      _customers = nextCustomers;
      _selectedCustomerId = created.id;
      _routeStops = _buildOfflineRoutePlan(nextCustomers);
    });
    _addressController.text = created.address;
    _notesController.text = created.notes;
    _setFeedback(message: "Customer created successfully");
  }

  Future<void> _showCreateCustomerSheet() async {
    final townships = _selectedTeamTownships;
    if (townships.isEmpty) {
      _setFeedback(error: "ဒီ sale team အတွက် township မသတ်မှတ်ရသေးပါ");
      return;
    }
    _newCustomerNameController.clear();
    _newCustomerPhoneController.clear();
    _newCustomerAddressController.clear();
    var selectedTownship = townships.first;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create Customer",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newCustomerNameController,
                    decoration: const InputDecoration(
                      labelText: "Customer Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newCustomerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "Phone Number",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTownship,
                    decoration: const InputDecoration(
                      labelText: "Township",
                      border: OutlineInputBorder(),
                    ),
                    items: townships
                        .map(
                          (township) => DropdownMenuItem<String>(
                            value: township,
                            child: Text(township),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setSheetState(() => selectedTownship = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newCustomerAddressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Address",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text("Cancel"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final name = _newCustomerNameController.text.trim();
                            final phone =
                                _newCustomerPhoneController.text.trim();
                            if (name.isEmpty || phone.isEmpty) {
                              _setFeedback(
                                  error:
                                      "Customer name နဲ့ phone number ဖြည့်ပေးပါ");
                              return;
                            }
                            Navigator.of(sheetContext).pop();
                            try {
                              await _createCustomer(
                                name: name,
                                phone: phone,
                                township: selectedTownship,
                                address:
                                    _newCustomerAddressController.text.trim(),
                              );
                            } on ApiException catch (error) {
                              _setFeedback(error: error.message);
                            } catch (error) {
                              _setFeedback(error: error.toString());
                            }
                          },
                          child: const Text("Create"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncPendingOrders({required bool showSuccessMessage}) async {
    if (_syncingQueue) {
      return;
    }
    _syncingQueue = true;
    try {
      final orders = await _db.loadOfflineOrders();
      var syncedCount = 0;
      for (final order in orders.where((item) => !item.isSynced)) {
        try {
          final result = await _client.checkout(
            discountPct: order.discountPct,
            promoCode: order.promoCode,
            payments: order.payments,
            items: order.items,
            clientOrderId: order.localId,
            location: order.location,
            visitNote: order.visitNote,
            customerId: order.customerId,
          );
          await _db.updateOfflineOrder(
            order.copyWith(
              status: "synced",
              lastError: "",
              syncedReceipt: result.receipt,
            ),
          );
          syncedCount += 1;
        } on NetworkException catch (error) {
          await _db.updateOfflineOrder(
              order.copyWith(status: "pending", lastError: error.message));
          if (mounted) {
            setState(() => _syncOnline = false);
          }
          break;
        } on ApiException catch (error) {
          await _db.updateOfflineOrder(
              order.copyWith(status: "pending", lastError: error.message));
        }
      }

      final refreshedOrders = await _db.loadOfflineOrders();
      if (!mounted) {
        return;
      }
      setState(() {
        _offlineOrders = refreshedOrders;
        _syncOnline = true;
      });
      if (syncedCount > 0) {
        final mergedReceipts = <String, Receipt>{};
        for (final receipt in _receipts) {
          mergedReceipts[receipt.invoiceId] = receipt;
        }
        for (final receipt in refreshedOrders
            .where((item) => item.syncedReceipt != null)
            .map((item) => item.syncedReceipt!)
            .toList()) {
          mergedReceipts[receipt.invoiceId] = receipt;
        }
        await _db.cacheReceipts(mergedReceipts.values.toList());
        final weeklyReceipts = await _db.loadWeeklyReceipts();
        if (mounted) {
          setState(() {
            _receipts = mergedReceipts.values.toList();
            _weeklyReceipts = weeklyReceipts;
          });
        }
        if (showSuccessMessage) {
          _setFeedback(message: "Queued vouchers synced: $syncedCount");
        }
      }
    } on NetworkException {
      if (mounted) {
        setState(() => _syncOnline = false);
      }
    } finally {
      _syncingQueue = false;
    }
  }

  Future<void> _addToCart({required String sku, int qty = 1}) async {
    _setFeedback();
    setState(() => _submitting = true);
    try {
      final selectedSku = sku.trim().toUpperCase();
      final selectedQty = qty;
      final product = _products.firstWhere(
        (item) => item.sku == selectedSku,
        orElse: () => throw const ApiException("Product not found"),
      );
      final existingIndex =
          _cart.items.indexWhere((item) => item.sku == selectedSku);
      final existingQty =
          existingIndex >= 0 ? _cart.items[existingIndex].quantity : 0;
      if (product.stock < existingQty + selectedQty) {
        throw const ApiException("Insufficient stock in local database");
      }
      final totalQty = existingQty + selectedQty;
      final unitPrice = _unitPriceForQuantity(product, totalQty);
      final nextItem = CartItem(
        sku: product.sku,
        name: product.name,
        quantity: totalQty,
        unitPrice: unitPrice,
        lineTotal: unitPrice * totalQty,
      );
      setState(() {
        final nextItems = List<CartItem>.from(_cart.items);
        if (existingIndex >= 0) {
          nextItems[existingIndex] = nextItem;
        } else {
          nextItems.add(nextItem);
        }
        _cart = CartState(items: nextItems, total: 0);
        _rebuildCart();
      });
      _setFeedback(message: "Added $selectedSku x$selectedQty");
    } on ApiException catch (error) {
      _setFeedback(error: error.message);
    } catch (error) {
      _setFeedback(error: error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _checkout() async {
    _setFeedback();
    setState(() => _submitting = true);
    try {
      if (_cart.items.isEmpty) {
        throw const ApiException("ပစ္စည်းကို အရင်ရွေးပါ");
      }
      if (_currentLocation == null) {
        await _captureLocation();
      }
      final order = _buildOfflineOrder();
      final result = await _client.checkout(
        discountPct: order.discountPct,
        promoCode: order.promoCode,
        payments: order.payments,
        items: order.items,
        clientOrderId: order.localId,
        location: order.location,
        visitNote: order.visitNote,
        customerId: order.customerId,
      );

      _discountController.text = "0";
      _promoController.clear();
      _payments = [
        _PaymentInput(method: _paymentOptions.firstOrNull ?? "cash", amount: "")
      ];
      _latestReceipt = result.receipt;
      _cart = const CartState(items: [], total: 0);
      await _loadData();
      setState(() {
        _salesStage = 2;
        _syncOnline = true;
      });
      _setFeedback(message: "Order Placed Successfully");
    } on NetworkException catch (error) {
      final order = _buildOfflineOrder();
      await _queueOfflineOrder(order, reason: error.message);
      _setFeedback(
          message:
              "Voucher saved on phone. Line ပြန်ရတာနဲ့ auto sync လုပ်ပေးမယ်။");
    } on ApiException catch (error) {
      _setFeedback(error: error.message);
    } catch (error) {
      _setFeedback(error: error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("session_json");
    await prefs.remove("selected_team_code");
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          initialBaseUrl: widget.baseUrl,
          initialDeviceId: widget.deviceId,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _changeTeam() async {
    if (_isTeamLocked) {
      final shouldSwitch = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Team Locked"),
              content: Text(
                "ဒီ account ကို ${_selectedTeam.label} နဲ့ချိတ်ထားပါတယ်။ နောက်တစ်ယောက်ဝင်ချင်ရင် Switch Account လုပ်ပါမလား?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Switch Account"),
                ),
              ],
            ),
          ) ??
          false;
      if (shouldSwitch) {
        await _logout();
      }
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TeamSelectionScreen(
          baseUrl: widget.baseUrl,
          deviceId: widget.deviceId,
          token: widget.token,
          session: widget.session,
          initialSelectedTeamCode: _selectedTeamCode,
        ),
      ),
    );
  }

  List<Customer> get _teamCustomers {
    return _customers.where((customer) {
      if (customer.teamCode.isNotEmpty) {
        return customer.teamCode == _selectedTeamCode;
      }
      final mappedTeam = _availableTeams.firstWhere(
        (team) => team.townships.contains(customer.township),
        orElse: () =>
            const _SalesTeam(code: "", label: "", township: "", townships: []),
      );
      if (mappedTeam.code.isNotEmpty) {
        return mappedTeam.code == _selectedTeamCode;
      }
      final selectedIndex =
          _availableTeams.indexWhere((team) => team.code == _selectedTeamCode);
      return selectedIndex >= 0 &&
          _availableTeams.isNotEmpty &&
          customer.id % _availableTeams.length == selectedIndex;
    }).toList();
  }

  List<Receipt> get _teamReceipts {
    return _receipts
        .where((receipt) =>
            receipt.cashier.trim().toLowerCase() ==
            widget.session.username.trim().toLowerCase())
        .toList();
  }

  List<Receipt> get _teamWeeklyReceipts {
    return _weeklyReceipts
        .where((receipt) =>
            receipt.cashier.trim().toLowerCase() ==
            widget.session.username.trim().toLowerCase())
        .toList();
  }

  _SalesTeam get _selectedTeam {
    return _availableTeams.firstWhere(
      (team) => team.code == _selectedTeamCode,
      orElse: () => _availableTeams.first,
    );
  }

  List<String> get _selectedTeamTownships {
    if (_selectedTeam.townships.isNotEmpty) {
      return _selectedTeam.townships;
    }
    if (_selectedTeam.township.isNotEmpty) {
      return [_selectedTeam.township];
    }
    return const [];
  }

  Customer? get _selectedCustomer {
    if (_selectedCustomerId == null) {
      return null;
    }
    for (final customer in _customers) {
      if (customer.id == _selectedCustomerId) {
        return customer;
      }
    }
    return null;
  }

  void _confirmCustomerSelection() {
    if (_selectedCustomerId == null) {
      _setFeedback(error: "customer name ကို အရင်ရွေးပါ");
      return;
    }
    setState(() {
      _currentTab = 2;
      _salesStage = 0;
      _message = "";
      _error = "";
    });
  }

  Future<void> _openOrderForCustomer(int customerId) async {
    await _selectCustomer(customerId);
    if (!mounted) return;
    setState(() {
      _currentTab = 2;
      _salesStage = 0;
      _message = "";
      _error = "";
    });
  }

  Future<void> _saveSlipPreview() async {
    final receipt = _latestReceipt;
    if (receipt == null) {
      _setFeedback(error: "Slip data not available");
      return;
    }
    await _saveReceiptPdf(receipt, customer: _selectedCustomer);
  }

  Future<void> _saveReceiptPdf(Receipt receipt, {Customer? customer}) async {
    try {
      final pdfBytes = await _buildSlipPdf(
        receipt: receipt,
        customer: customer,
      );
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoice_${receipt.invoiceId}.pdf",
      );
      _setFeedback(message: "Save To opened for invoice ${receipt.invoiceId}");
    } catch (error) {
      _setFeedback(error: "Save To failed: $error");
    }
  }

  Future<void> _printSlipPreview() async {
    final receipt = _latestReceipt;
    if (receipt == null) {
      _setFeedback(error: "Slip data not available");
      return;
    }
    await _printReceiptPdf(receipt, customer: _selectedCustomer);
  }

  Future<void> _printReceiptPdf(Receipt receipt, {Customer? customer}) async {
    try {
      await Printing.layoutPdf(
        name: "invoice_${receipt.invoiceId}",
        onLayout: (_) => _buildSlipPdf(
          receipt: receipt,
          customer: customer,
        ),
      );
      _setFeedback(message: "Print dialog opened for invoice ${receipt.invoiceId}");
    } catch (error) {
      _setFeedback(error: "Print failed: $error");
    }
  }

  void _openReceiptPreview(Receipt receipt) {
    setState(() {
      _latestReceipt = receipt;
      _salesStage = 2;
      _currentTab = 2;
      _message = "";
      _error = "";
    });
  }

  void _changeCartQuantity(String sku, int delta) {
    final index = _cart.items.indexWhere((item) => item.sku == sku);
    if (index < 0) {
      return;
    }
    final current = _cart.items[index];
    final product = _products.firstWhere(
      (item) => item.sku == sku,
      orElse: () => Product(
        sku: current.sku,
        name: current.name,
        price: current.unitPrice,
        stock: current.quantity,
        category: "",
        priceTiers: [PriceTier(minQty: 1, unitPrice: current.unitPrice)],
      ),
    );
    final nextQty = current.quantity + delta;
    if (nextQty <= 0) {
      setState(() {
        final nextItems = List<CartItem>.from(_cart.items)..removeAt(index);
        _cart = CartState(items: nextItems, total: 0);
        _rebuildCart();
      });
      return;
    }
    if (nextQty > product.stock) {
      _setFeedback(error: "Insufficient stock in local database");
      return;
    }
    final nextUnitPrice = _unitPriceForQuantity(product, nextQty);
    setState(() {
      final nextItems = List<CartItem>.from(_cart.items);
      nextItems[index] = CartItem(
        sku: current.sku,
        name: current.name,
        quantity: nextQty,
        unitPrice: nextUnitPrice,
        lineTotal: nextUnitPrice * nextQty,
      );
      _cart = CartState(items: nextItems, total: 0);
      _rebuildCart();
    });
  }

  List<Widget> _buildDashboardPage(List<Customer> teamCustomers) {
    return [
      _HeroCard(
        session: widget.session,
        deviceId: widget.deviceId,
        baseUrl: widget.baseUrl,
        selectedTeam: _selectedTeam,
        online: _syncOnline,
        pendingCount: _offlineOrders.where((order) => !order.isSynced).length,
      ),
      const SizedBox(height: 14),
      _TopKpiStrip(
        todaySales: _mobileDashboard?.todaySales ?? 0,
        routeCount: _routeStops.length,
        customerCount: teamCustomers.length,
      ),
      const SizedBox(height: 14),
      _RoutePlanCard(
        stops: _routeStops,
        selectedCustomerId: _selectedCustomerId,
        onTapStop: (customerId) => _selectCustomer(customerId),
      ),
      const SizedBox(height: 14),
      _SalesProgressCard(dashboard: _mobileDashboard),
      const SizedBox(height: 14),
      _PromotionListCard(promotions: _mobileDashboard?.promotions ?? const []),
      const SizedBox(height: 14),
      _CustomerChooserPanel(
        team: _selectedTeam,
        customers: teamCustomers,
        selectedCustomerId: _selectedCustomerId,
        onChanged: (value) => _selectCustomer(value),
        onConfirm: _confirmCustomerSelection,
      ),
    ];
  }

  List<Widget> _buildCustomersPage(List<Customer> teamCustomers) {
    final selectedCustomer = _selectedCustomer;
    return [
      _CardBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Customers",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                OutlinedButton.icon(
                  onPressed: _showCreateCustomerSheet,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text("New Customer"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CustomerChooserPanel(
              team: _selectedTeam,
              customers: teamCustomers,
              selectedCustomerId: _selectedCustomerId,
              onChanged: (value) => _selectCustomer(value),
              onConfirm: _confirmCustomerSelection,
            ),
            if (selectedCustomer != null) ...[
              const SizedBox(height: 12),
              _CustomerQuickCard(
                customer: selectedCustomer,
                selected: true,
                onTap: () => _selectCustomer(selectedCustomer.id),
                onOrderTap: () => _openOrderForCustomer(selectedCustomer.id),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildProfilePage() {
    return [
      _CardBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Profile",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _ProfileRow(label: "User", value: widget.session.username),
            _ProfileRow(label: "Role", value: widget.session.role),
            _ProfileRow(label: "Device", value: widget.deviceId),
            _ProfileRow(label: "Team", value: _selectedTeam.label),
            _ProfileRow(label: "Server", value: widget.baseUrl),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _SalesProgressCard(dashboard: _mobileDashboard),
      const SizedBox(height: 14),
      _PromotionListCard(promotions: _mobileDashboard?.promotions ?? const []),
      const SizedBox(height: 14),
      _buildReceiptArchiveCard(
        title: "Weekly Sales Archive",
        receipts: _teamWeeklyReceipts,
        emptyMessage: "Last 7 days sales archive မရှိသေးပါ",
      ),
    ];
  }

  List<Widget> _buildSalesPage(
      List<Product> quickProducts, List<Customer> teamCustomers) {
    final searchQuery = _searchController.text.trim().toLowerCase();
    final saleProducts = _products.where((product) {
      if (product.category == "Fuel types") {
        return false;
      }
      if (searchQuery.isEmpty) {
        return true;
      }
      return product.name.toLowerCase().contains(searchQuery) ||
          product.sku.toLowerCase().contains(searchQuery) ||
          product.category.toLowerCase().contains(searchQuery);
    }).toList();
    final selectedCustomer = _selectedCustomer;
    final widgets = <Widget>[
      _CardBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("အရောင်းလုပ်ငန်းစဉ်",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Chip(
                    label: Text(_salesStage == 0
                        ? "1/3"
                        : _salesStage == 1
                            ? "2/3"
                            : "3/3")),
              ],
            ),
            const SizedBox(height: 12),
            if (selectedCustomer == null)
              const Text("Dashboard မှာ customer name ကို အရင်ရွေးပါ။")
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F2E6),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2D3BA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedCustomer.name.isEmpty
                          ? selectedCustomer.phone
                          : selectedCustomer.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text("Phone: ${selectedCustomer.phone}"),
                    if (selectedCustomer.township.isNotEmpty)
                      Text("Township: ${selectedCustomer.township}"),
                    if (selectedCustomer.address.isNotEmpty)
                      Text("Address: ${selectedCustomer.address}"),
                    if (selectedCustomer.notes.isNotEmpty)
                      Text("Notes: ${selectedCustomer.notes}"),
                    if (selectedCustomer.creditBalance > 0)
                      Text(
                          "Credit: ${_formatKs(selectedCustomer.creditBalance)}"),
                    Text("Team: ${_selectedTeam.label}"),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (selectedCustomer != null) ...[
        _CustomerInsightsCard(
            insights: _customerInsights, customer: selectedCustomer),
        const SizedBox(height: 14),
        _CustomerProfileCard(
          addressController: _addressController,
          activeVoiceField: _activeVoiceField,
          onSave: _saveCustomerProfile,
          onVoiceAddress: () => _startVoiceInput("address"),
        ),
        const SizedBox(height: 14),
      ],
    ];

    if (_salesStage != 2) {
      widgets.addAll([
        _CardBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("ကုန်ပစ္စည်းရွေးရန်",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text("ဆိုင်အတွက်ယူမယ့် ပစ္စည်းကိုရွေးပြီး cart ထဲထည့်ပါ။"),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: "Search by product name / category",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (saleProducts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _EmptyStateCard(
                    icon: Icons.search_off_rounded,
                    title: "No items found",
                    subtitle: "ရှာမတွေ့သေးပါ",
                  ),
                ),
              if (saleProducts.isNotEmpty)
                ...saleProducts.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OrderProductRow(
                      product: product,
                      onAdd: _submitting
                          ? null
                          : () => _addToCart(sku: product.sku),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              if (_currentLocation != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    "GPS: ${_currentLocation!.latitude.toStringAsFixed(5)}, ${_currentLocation!.longitude.toStringAsFixed(5)}",
                    style: const TextStyle(color: Color(0xFF6B5E4A)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildCartCard(summaryOnly: true, editable: true),
        const SizedBox(height: 14),
        _CardBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Direct Order Summary",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _discountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: "Discount %", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promoController,
                decoration: const InputDecoration(
                    labelText: "Promo Code", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              _VoiceReadyField(
                controller: _notesController,
                label: "Visit Notes",
                active: _activeVoiceField == "notes",
                onVoiceTap: () => _startVoiceInput("notes"),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              ..._payments.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: entry.value.method,
                              decoration: const InputDecoration(
                                  border: OutlineInputBorder()),
                              items: _paymentOptions
                                  .map((option) => DropdownMenuItem(
                                      value: option, child: Text(option)))
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _payments[entry.key] =
                                      entry.value.copyWith(method: value);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey(
                                  "payment-${entry.key}-${entry.value.method}"),
                              initialValue: entry.value.amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: "Amount",
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                _payments[entry.key] =
                                    entry.value.copyWith(amount: value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _payments.add(_PaymentInput(
                              method: _paymentOptions.firstOrNull ?? "cash",
                              amount: ""));
                        });
                      },
                      child: const Text("Add Payment"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _payments.length <= 1
                          ? null
                          : () {
                              setState(() {
                                _payments.removeLast();
                              });
                            },
                      child: const Text("Remove Payment"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : () => _checkout(),
                      child: const Text("Final Confirm"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]);
    } else {
      widgets.addAll([
        _CardBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Slip Preview",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (_latestReceipt == null)
                const Text("Slip data not available")
              else
                _SlipPreview(
                    receipt: _latestReceipt!, customer: selectedCustomer),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveSlipPreview,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text("Save To"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _printSlipPreview,
                      icon: const Icon(Icons.print_rounded),
                      label: const Text("Print"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _salesStage = 0;
                          _latestReceipt = null;
                          _currentTab = 0;
                        });
                      },
                      child: const Text("New Order"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      _buildReceiptArchiveCard(
        title: "Weekly Voucher Archive",
        receipts: _teamWeeklyReceipts,
        emptyMessage: "Last 7 days voucher မရှိသေးပါ",
      ),
      ]);
    }

    widgets.addAll([
      const SizedBox(height: 14),
      _buildReceiptArchiveCard(
        title: "Server Synced Receipts",
        receipts: _teamReceipts,
        emptyMessage: "Server synced receipts မရှိသေးပါ",
        maxGroups: 3,
        maxReceiptsPerGroup: 4,
      ),
    ]);

    return widgets;
  }

  Widget _buildReceiptArchiveCard({
    required String title,
    required List<Receipt> receipts,
    required String emptyMessage,
    int? maxGroups,
    int? maxReceiptsPerGroup,
  }) {
    final grouped = <String, List<Receipt>>{};
    for (final receipt in receipts) {
      final dateKey = receipt.timestamp.length >= 10
          ? receipt.timestamp.substring(0, 10)
          : receipt.timestamp;
      grouped.putIfAbsent(dateKey, () => []).add(receipt);
    }

    final entries = grouped.entries.toList()
      ..sort((left, right) => right.key.compareTo(left.key));
    final visibleEntries =
        maxGroups == null ? entries : entries.take(maxGroups).toList();

    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (visibleEntries.isEmpty) Text(emptyMessage),
          ...visibleEntries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2D3BA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...(maxReceiptsPerGroup == null
                          ? entry.value
                          : entry.value.take(maxReceiptsPerGroup))
                      .map(
                    (receipt) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Invoice ${receipt.invoiceId}",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(_formatKs(receipt.invoiceTotal)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(receipt.timestamp),
                            Text("Cashier: ${receipt.cashier}"),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _saveReceiptPdf(receipt),
                                    icon: const Icon(Icons.save_alt_rounded),
                                    label: const Text("Save To"),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _printReceiptPdf(receipt),
                                    icon: const Icon(Icons.print_rounded),
                                    label: const Text("Print"),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => _openReceiptPreview(receipt),
                                child: const Text("Preview Slip"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartCard({required bool summaryOnly, bool editable = false}) {
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(summaryOnly ? "Order Summary" : "Cart",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              Chip(label: Text("${_cart.items.length} items")),
            ],
          ),
          const SizedBox(height: 12),
          if (_cart.items.isEmpty)
            const _EmptyStateCard(
              icon: Icons.inventory_2_rounded,
              title: "No items found",
              subtitle: "Cart ထဲမှာ ပစ္စည်းမရှိသေးပါ",
            )
          else
            ..._cart.items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F2E6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2D3BA)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDD5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.inventory_2_rounded,
                          color: Color(0xFFEA580C)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text("${item.sku}  Qty ${item.quantity} pcs",
                              style: const TextStyle(color: Color(0xFF6B5E4A))),
                          if (editable)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  _QtyButton(
                                    icon: Icons.remove_rounded,
                                    onTap: () =>
                                        _changeCartQuantity(item.sku, -1),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Text(
                                      "${item.quantity}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  _QtyButton(
                                    icon: Icons.add_rounded,
                                    onTap: () =>
                                        _changeCartQuantity(item.sku, 1),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(_formatKs(item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(_formatKs(_cart.total),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827))),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickProducts = _products
        .where((product) => product.category != "Fuel types")
        .take(6)
        .toList();
    final teamCustomers = _teamCustomers;
    final List<Widget> currentPage;
    switch (_currentTab) {
      case 0:
        currentPage = _buildDashboardPage(teamCustomers);
        break;
      case 1:
        currentPage = _buildCustomersPage(teamCustomers);
        break;
      case 2:
        currentPage = _buildSalesPage(quickProducts, teamCustomers);
        break;
      case 3:
        currentPage = _buildProfilePage();
        break;
      default:
        currentPage = _buildDashboardPage(teamCustomers);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("သူဌေးမင်း စားသုံးဆီ"),
        actions: [
          IconButton(
              tooltip: _isTeamLocked ? "Team locked" : "Change team",
              onPressed: () => _changeTeam(),
              icon: Icon(
                _isTeamLocked ? Icons.lock_rounded : Icons.swap_horiz_rounded,
              )),
          IconButton(
            onPressed: _loading
                ? null
                : () async {
                    await _loadData();
                    await _syncPendingOrders(showSuccessMessage: true);
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
              onPressed: () => _logout(),
              icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_startupBusy) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
            const _InfoBanner(
              text: "App data တွေကို background မှာဖွင့်နေပါတယ်...",
              color: Color(0xFF1D4ED8),
              background: Color(0xFFDBEAFE),
            ),
            const SizedBox(height: 12),
          ],
          ...currentPage,
          if (!_startupBusy &&
              _products.isEmpty &&
              _customers.isEmpty &&
              _weeklyReceipts.isEmpty) ...[
            const SizedBox(height: 12),
            const _EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: "No items found",
              subtitle:
                  "Local cache မရှိသေးပါ။ Server ချိတ်ပြီး data တစ်ခါ sync လုပ်ရန်လိုပါတယ်။",
            ),
          ],
          const SizedBox(height: 14),
          _SyncStatusBanner(
            online: _syncOnline,
            pendingCount:
                _offlineOrders.where((order) => !order.isSynced).length,
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 14),
            _InfoBanner(
                text: _message,
                color: const Color(0xFF166534),
                background: const Color(0xFFDCFCE7)),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            _InfoBanner(
                text: _error,
                color: const Color(0xFFB42318),
                background: const Color(0xFFFEE4E2)),
          ],
          const SizedBox(height: 20),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _currentTab = 2;
            _salesStage = 0;
          });
        },
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) => setState(() => _currentTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_rounded),
            label: "Customers",
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: "Orders",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.session,
    required this.deviceId,
    required this.baseUrl,
    required this.selectedTeam,
    required this.online,
    required this.pendingCount,
  });

  final UserSession session;
  final String deviceId;
  final String baseUrl;
  final _SalesTeam selectedTeam;
  final bool online;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF174F45), Color(0xFF0F766E), Color(0xFF2AA198)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _BrandImageBadge(imagePath: "assets/thubatemin_oil.jpg"),
              Chip(label: Text(selectedTeam.code)),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "စားသုံးဆီ",
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(selectedTeam.label,
              style: const TextStyle(color: Color(0xFFD7F8F2), fontSize: 16)),
          const SizedBox(height: 10),
          Text("User: ${session.username}",
              style: const TextStyle(color: Color(0xFFD7F8F2))),
          const SizedBox(height: 4),
          Text("Device: $deviceId",
              style: const TextStyle(color: Color(0xFFD7F8F2))),
          const SizedBox(height: 4),
          Text("Server: $baseUrl",
              style: const TextStyle(color: Color(0xFFD7F8F2))),
          const SizedBox(height: 4),
          Row(
            children: [
              _SyncDot(isOnline: online),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  online ? "Sync connected" : "Offline mode",
                  style: const TextStyle(color: Color(0xFFD7F8F2)),
                ),
              ),
              if (pendingCount > 0)
                Text(
                  "$pendingCount queued",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: _MiniStatChip(
                  icon: Icons.local_drink_rounded,
                  label: "Orders",
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _MiniStatChip(
                  icon: Icons.storefront_rounded,
                  label: "Customers",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD1D5DB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

class _RoutePlanCard extends StatelessWidget {
  const _RoutePlanCard({
    required this.stops,
    required this.selectedCustomerId,
    required this.onTapStop,
  });

  final List<RouteStop> stops;
  final int? selectedCustomerId;
  final ValueChanged<int> onTapStop;

  @override
  Widget build(BuildContext context) {
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Today Route Plan",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (stops.isEmpty)
            const _EmptyStateCard(
              icon: Icons.route_rounded,
              title: "No items found",
              subtitle: "ဒီနေ့အတွက် route plan မရှိသေးပါ",
            )
          else
            ...stops.take(5).map(
                  (stop) => Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selectedCustomerId == stop.customerId
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF8F2E6),
                    child: ListTile(
                      onTap: () => onTapStop(stop.customerId),
                      leading: CircleAvatar(child: Text("${stop.sequence}")),
                      title: Text(stop.customerName),
                      subtitle: Text(
                          "${stop.priorityReason}\n${stop.address.isEmpty ? stop.phone : stop.address}"),
                      trailing: stop.creditBalance > 0
                          ? Text("Credit\n${_formatKs(stop.creditBalance)}",
                              textAlign: TextAlign.end)
                          : const Icon(Icons.chevron_right_rounded),
                      isThreeLine: true,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SalesProgressCard extends StatelessWidget {
  const _SalesProgressCard({
    required this.dashboard,
  });

  final MobileSalesDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Target & Commission",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (data == null)
            const Text("Dashboard data loading...")
          else ...[
            Text("Today Sales: ${_formatKs(data.todaySales)}"),
            Text("Target: ${_formatKs(data.dailyTarget)}"),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: data.dailyTarget <= 0
                  ? 0
                  : (data.completionPct / 100).clamp(0, 1),
              minHeight: 10,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text("Target completed: ${data.completionPct.toStringAsFixed(1)}%"),
            Text(
                "Estimated commission: ${_formatKs(data.estimatedCommission)}"),
          ],
        ],
      ),
    );
  }
}

class _PromotionListCard extends StatelessWidget {
  const _PromotionListCard({
    required this.promotions,
  });

  final List<PromotionInfo> promotions;

  @override
  Widget build(BuildContext context) {
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Active Promotions",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (promotions.isEmpty)
            const Text("လက်ရှိ active promotion မရှိသေးပါ")
          else
            ...promotions.map(
              (promotion) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF2D7A6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        "${promotion.code}  ${promotion.value.toStringAsFixed(0)}${promotion.type == "percentage" ? "%" : ""}",
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(promotion.description.isEmpty
                        ? promotion.category
                        : promotion.description),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerInsightsCard extends StatelessWidget {
  const _CustomerInsightsCard({
    required this.insights,
    required this.customer,
  });

  final CustomerInsights? insights;
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final data = insights;
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Customer History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text("Credit ${_formatKs(customer.creditBalance)}")),
              if ((data?.lastPurchaseAt ?? "").isNotEmpty)
                Chip(
                    label: Text(
                        "Last buy ${data!.lastPurchaseAt.split("T").first}")),
              Chip(
                  label: Text(
                      "Route ${customer.routeOrder == 0 ? "-" : customer.routeOrder}")),
            ],
          ),
          const SizedBox(height: 10),
          if ((data?.favoriteItems ?? const []).isNotEmpty)
            Text("အဝယ်များတာ: ${data!.favoriteItems.join(", ")}"),
          if ((data?.favoriteItems ?? const []).isEmpty)
            const Text("အရင်အဝယ် data မရှိသေးပါ"),
          const SizedBox(height: 8),
          Text("Total spent: ${_formatKs(data?.totalSpent ?? 0)}"),
        ],
      ),
    );
  }
}

class _CustomerProfileCard extends StatelessWidget {
  const _CustomerProfileCard({
    required this.addressController,
    required this.activeVoiceField,
    required this.onSave,
    required this.onVoiceAddress,
  });

  final TextEditingController addressController;
  final String activeVoiceField;
  final VoidCallback onSave;
  final VoidCallback onVoiceAddress;

  @override
  Widget build(BuildContext context) {
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Address",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _VoiceReadyField(
            controller: addressController,
            label: "Customer Address",
            active: activeVoiceField == "address",
            onVoiceTap: onVoiceAddress,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              child: const Text("Save Profile"),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceReadyField extends StatelessWidget {
  const _VoiceReadyField({
    required this.controller,
    required this.label,
    required this.active,
    required this.onVoiceTap,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String label;
  final bool active;
  final VoidCallback onVoiceTap;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: onVoiceTap,
          icon: Icon(active ? Icons.mic : Icons.mic_none_rounded),
        ),
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({
    required this.online,
    required this.pendingCount,
  });

  final bool online;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF166534) : const Color(0xFFB42318);
    final background =
        online ? const Color(0xFFDCFCE7) : const Color(0xFFFEE4E2);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _SyncDot(isOnline: online),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? (pendingCount == 0
                      ? "ဘောင်ချာအားလုံး server ရောက်ပြီးပါပြီ။"
                      : "$pendingCount စောင့်နေတဲ့ voucher ကို sync လုပ်နေပါတယ်။")
                  : "Offline ဖြစ်နေပါတယ်။ Voucher တွေကို ဖုန်းထဲမှာသိမ်းထားပြီး line ပြန်ရတာနဲ့ sync လုပ်ပေးမယ်။",
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({
    required this.isOnline,
  });

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BrandImageBadge extends StatelessWidget {
  const _BrandImageBadge({
    required this.imagePath,
  });

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
        image: DecorationImage(
          image: AssetImage(imagePath),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopKpiStrip extends StatelessWidget {
  const _TopKpiStrip({
    required this.todaySales,
    required this.routeCount,
    required this.customerCount,
  });

  final double todaySales;
  final int routeCount;
  final int customerCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _BigKpiCard(
                label: "Today Sales", value: _formatKs(todaySales))),
        const SizedBox(width: 10),
        Expanded(
            child: _BigKpiCard(label: "Today Stops", value: "$routeCount")),
        const SizedBox(width: 10),
        Expanded(
            child: _BigKpiCard(label: "Customers", value: "$customerCount")),
      ],
    );
  }
}

class _BigKpiCard extends StatelessWidget {
  const _BigKpiCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827))),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 36, color: const Color(0xFF0369A1)),
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4B5563))),
        ],
      ),
    );
  }
}

class _LoadingShimmerScreen extends StatefulWidget {
  const _LoadingShimmerScreen();

  @override
  State<_LoadingShimmerScreen> createState() => _LoadingShimmerScreenState();
}

class _LoadingShimmerScreenState extends State<_LoadingShimmerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ShimmerBlock(height: 170, t: _controller.value),
            const SizedBox(height: 14),
            _ShimmerBlock(height: 110, t: _controller.value),
            const SizedBox(height: 14),
            _ShimmerBlock(height: 110, t: _controller.value),
          ],
        );
      },
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  const _ShimmerBlock({
    required this.height,
    required this.t,
  });

  final double height;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: const [
            Color(0xFFF3F4F6),
            Color(0xFFE5E7EB),
            Color(0xFFF3F4F6)
          ],
          stops: [0, t.clamp(0.2, 0.8).toDouble(), 1],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _CustomerQuickCard extends StatelessWidget {
  const _CustomerQuickCard({
    required this.customer,
    required this.selected,
    required this.onTap,
    required this.onOrderTap,
  });

  final Customer customer;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOrderTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: selected ? const Color(0xFFECFDF5) : Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color:
                selected ? const Color(0xFF10B981) : const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name.isEmpty ? customer.phone : customer.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                  customer.address.isEmpty ? customer.phone : customer.address),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                      label:
                          Text("Credit ${_formatKs(customer.creditBalance)}")),
                  ActionChip(
                    avatar: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text("Order"),
                    onPressed: onOrderTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockIndicator extends StatelessWidget {
  const _StockIndicator({
    required this.stock,
  });

  final int stock;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (stock <= 0) {
      color = const Color(0xFFDC2626);
      label = "ကုန်";
    } else if (stock <= 50) {
      color = const Color(0xFFD97706);
      label = "နည်း";
    } else {
      color = const Color(0xFF16A34A);
      label = "များ";
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _OrderProductRow extends StatelessWidget {
  const _OrderProductRow({
    required this.product,
    required this.onAdd,
  });

  final Product product;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text("${product.sku}  ${product.category}",
                      style: const TextStyle(color: Color(0xFF4B5563))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StockIndicator(stock: product.stock),
                      const SizedBox(width: 8),
                      Text("${product.stock} pcs",
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_formatKs(product.price),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Add"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF111827)),
      ),
    );
  }
}

class _SlipPreview extends StatelessWidget {
  const _SlipPreview({
    required this.receipt,
    required this.customer,
  });

  final Receipt receipt;
  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2D3BA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text("Shwe Htoo Thit",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          Center(child: Text("Invoice ${receipt.invoiceId}")),
          const SizedBox(height: 12),
          Text("Customer: ${customer?.name ?? "-"}"),
          Text("Cashier: ${receipt.cashier}"),
          Text("Time: ${receipt.timestamp}"),
          if (receipt.location != null)
            Text(
              "GPS: ${receipt.location!.latitude.toStringAsFixed(5)}, ${receipt.location!.longitude.toStringAsFixed(5)}",
            ),
          if (receipt.visitNote.isNotEmpty) Text("Note: ${receipt.visitNote}"),
          const Divider(height: 24),
          ...receipt.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text("${item.name} x${item.quantity} pcs")),
                  Text(_formatKs(item.lineTotal)),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Discount"),
              Text(_formatKs(receipt.discount)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Grand Total"),
              Text(_formatKs(receipt.grandTotal)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Invoice Total",
                  style: TextStyle(fontWeight: FontWeight.w800)),
              Text(_formatKs(receipt.invoiceTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerChooserPanel extends StatelessWidget {
  const _CustomerChooserPanel({
    required this.team,
    required this.customers,
    required this.selectedCustomerId,
    required this.onChanged,
    required this.onConfirm,
  });

  final _SalesTeam team;
  final List<Customer> customers;
  final int? selectedCustomerId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final dropdownValue = customers.any((customer) => customer.id == selectedCustomerId)
        ? selectedCustomerId
        : null;
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "customer name ရွေးရန်",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              team.label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          if (customers.isEmpty)
            const _EmptyStateCard(
              icon: Icons.person_search_rounded,
              title: "No items found",
              subtitle: "Customer data မရှိသေးပါ",
            )
          else
            DropdownButtonFormField<int?>(
              initialValue: dropdownValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Customers",
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text("customer ရွေးပါ"),
                ),
                ...customers.map(
                  (customer) => DropdownMenuItem<int?>(
                    value: customer.id,
                    child: Text(
                      customer.name.isEmpty ? customer.phone : customer.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          if (selectedCustomerId != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConfirm,
                child: const Text("Confirm"),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentInput {
  const _PaymentInput({
    required this.method,
    required this.amount,
  });

  final String method;
  final String amount;

  _PaymentInput copyWith({
    String? method,
    String? amount,
  }) {
    return _PaymentInput(
      method: method ?? this.method,
      amount: amount ?? this.amount,
    );
  }
}

class _SalesTeam {
  const _SalesTeam({
    required this.code,
    required this.label,
    required this.township,
    required this.townships,
  });

  factory _SalesTeam.fromServer(SalesTeamInfo team) {
    final townships = team.townships.isEmpty && team.township.isNotEmpty
        ? [team.township]
        : team.townships;
    return _SalesTeam(
      code: team.code,
      label: team.name.isNotEmpty ? team.name : team.code,
      township: townships.isEmpty ? team.township : townships.first,
      townships: townships,
    );
  }

  final String code;
  final String label;
  final String township;
  final List<String> townships;

  String get townshipLabel =>
      townships.isEmpty ? township : townships.join(" ၊ ");
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
