const { useEffect, useRef, useState } = React;

const OFFLINE_QUEUE_KEY = "sht_offline_queue";
const DEVICE_ID_KEY = "sht_device_id";
const LANGUAGE_KEY = "sht_lang";
const ADMIN_TOKEN_KEY = "sht_admin_token";
const ADMIN_USER_KEY = "sht_admin_user";
const AUTH_EXPIRED_EVENT = "sht-auth-expired";
const DEFAULT_DEVICE_ID = "POS-TERMINAL-01";
const DEFAULT_LANG = "en";
const YANGON_REGION_TOWNSHIPS = [
  "Ahlon Township",
  "Bahan Township",
  "Botataung Township",
  "Dagon Seikkan Township",
  "Dagon Township",
  "Dala Township",
  "Dawbon Township",
  "East Dagon Township",
  "Hlaing Township",
  "Hlaingthaya East Township",
  "Hlaingthaya Township",
  "Insein Township",
  "Kamayut Township",
  "Kyauktada Township",
  "Kyimyindaing Township",
  "Lanmadaw Township",
  "Latha Township",
  "Mayangon Township",
  "Mingala Taungnyunt Township",
  "Mingaladon Township",
  "North Dagon Township",
  "North Okkalapa Township",
  "Pabedan Township",
  "Pazundaung Township",
  "Sanchaung Township",
  "Seikkan Township",
  "Seikkyi Kanaungto Township",
  "Shwepyitha Township",
  "South Dagon Township",
  "South Okkalapa Township",
  "Tamwe Township",
  "Thaketa Township",
  "Thingangyun Township",
  "Yankin Township",
];

const I18N = {
  en: {
    login: "Sign In",
    username: "Username",
    password: "Password",
    otp: "OTP (if 2FA required)",
    overview: "Overview",
    sales: "Sales",
    teams: "Teams",
    customers: "Customers",
    shifts: "Shifts",
    reports: "Reports",
    audit: "Audit",
    stock: "Stock",
    receipts: "Receipts",
    refresh: "Refresh All",
    sync: "Sync",
    logout: "Logout",
    add: "Add",
    remove: "Remove",
    checkout: "Checkout",
    low_stock: "Stock not enough",
    invalid_payment: "Invalid payments",
    cart_empty: "Cart is empty",
    queued: "Offline mode: action queued for sync",
    tax_invoice: "Tax Invoice",
    tax_rate: "Tax Rate %",
    tin: "Tax ID / TIN",
    print_thermal: "Print Thermal",
    print_a4: "Print A4",
    lang_toggle: "မြန်မာ",
  },
  my: {
    login: "ဝင်မည်",
    username: "အသုံးပြုသူအမည်",
    password: "လျှို့ဝှက်နံပါတ်",
    otp: "OTP (2FA လိုအပ်ပါက)",
    overview: "ခြုံငုံ",
    sales: "အရောင်း",
    teams: "အသင်းများ",
    customers: "ဖောက်သည်",
    shifts: "Shift",
    reports: "အစီရင်ခံစာ",
    audit: "စစ်ဆေးမှတ်တမ်း",
    stock: "စတော့",
    receipts: "ဘောင်ချာ",
    refresh: "ပြန်တင်",
    sync: "Sync",
    logout: "ထွက်မည်",
    add: "ထည့်မည်",
    remove: "ဖယ်မည်",
    checkout: "ငွေရှင်းမည်",
    low_stock: "စတော့မလုံလောက်ပါ",
    invalid_payment: "ပေးချေမှု မမှန်ကန်ပါ",
    cart_empty: "Cart ထဲတွင် ပစ္စည်းမရှိပါ",
    queued: "Offline mode: queue ထဲသို့သိမ်းပြီးပါပြီ",
    tax_invoice: "အခွန်ဘောင်ချာ",
    tax_rate: "အခွန် %",
    tin: "Tax ID / TIN",
    print_thermal: "Thermal ပရင့်",
    print_a4: "A4 ပရင့်",
    lang_toggle: "English",
  },
};

function t(lang, key) {
  return (I18N[lang] && I18N[lang][key]) || I18N.en[key] || key;
}

function formatKs(amount) {
  return `Ks ${Number(amount || 0).toFixed(0)}`;
}

function shortenAddress(address, maxLength = 18) {
  const text = String(address || "").trim();
  if (!text) return "-";
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength).trimEnd()}...`;
}

function buildTeamTargets(products, existingTargets = []) {
  const quantityBySku = new Map(
    (Array.isArray(existingTargets) ? existingTargets : []).map((target) => [
      String(target.sku || "").toUpperCase(),
      Number(target.quantity || 0),
    ])
  );
  return products.map((product) => ({
    sku: product.sku,
    name: product.name,
    quantity: quantityBySku.get(String(product.sku || "").toUpperCase()) || 0,
  }));
}

function emptyTeamForm(products = []) {
  return {
    name: "",
    sales_man_name: "",
    position: "",
    phone: "",
    township: "",
    townships: [],
    item_targets: buildTeamTargets(products),
  };
}

function emptySalesAccountForm(products = []) {
  return {
    username: "",
    full_name: "",
    password: "",
    use_new_team: false,
    team_code: "",
    active: true,
    team_draft: emptyTeamForm(products),
  };
}

function normalizeSalesAccountDraft(account) {
  return {
    username: account?.username || "",
    full_name: account?.full_name || "",
    password: "",
    use_new_team: false,
    team_code: account?.team_code || "",
    active: account?.active !== false,
    team_draft: emptyTeamForm(),
  };
}

function normalizeTeamDraft(team, products = []) {
  const townships = Array.isArray(team?.townships) && team.townships.length
    ? [...new Set(team.townships.map((item) => String(item || "").trim()).filter(Boolean))]
    : (team?.township ? [String(team.township).trim()] : []);
  return {
    id: team?.id,
    code: team?.code || "",
    name: team?.name || "",
    sales_man_name: team?.sales_man_name || "",
    position: team?.position || "",
    phone: team?.phone || "",
    township: townships[0] || "",
    townships,
    item_targets: buildTeamTargets(products, team?.item_targets || []),
  };
}

function toggleTownshipSelection(townships, township) {
  const current = new Set((townships || []).map((item) => String(item || "").trim()).filter(Boolean));
  if (current.has(township)) {
    current.delete(township);
  } else {
    current.add(township);
  }
  return YANGON_REGION_TOWNSHIPS.filter((item) => current.has(item));
}

function coveredTownshipsForTeam(team) {
  return ((team?.townships && team.townships.length) ? team.townships : [team?.township]).filter(Boolean);
}

function isSameCalendarDay(timestamp, now = new Date()) {
  if (!timestamp) return false;
  const value = new Date(timestamp);
  if (Number.isNaN(value.getTime())) return false;
  return value.getFullYear() === now.getFullYear()
    && value.getMonth() === now.getMonth()
    && value.getDate() === now.getDate();
}

function buildOverviewLiveData(teams, customers, receipts) {
  const customerById = new Map((customers || []).map((customer) => [Number(customer.id), customer]));
  const teamByCode = new Map((teams || []).map((team) => [String(team.code || "").toUpperCase(), team]));
  const teamStats = new Map();
  const recentEvents = [];

  (teams || []).forEach((team) => {
    const code = String(team.code || "").toUpperCase();
    teamStats.set(code, {
      code,
      name: team.name || team.code || "Team",
      salesMan: team.sales_man_name || "-",
      shops: new Set(),
      amount: 0,
      latestSaleAt: "",
    });
  });

  (receipts || []).forEach((receipt) => {
    if (!isSameCalendarDay(receipt.timestamp)) return;
    const directCustomer = receipt.customer || null;
    const storedCustomer = directCustomer?.id ? customerById.get(Number(directCustomer.id)) : null;
    const teamCode = String(directCustomer?.team_code || storedCustomer?.team_code || "").toUpperCase();
    if (!teamCode || !teamStats.has(teamCode)) return;

    const amount = Number(receipt.invoice_total || receipt.grand_total || 0);
    const team = teamStats.get(teamCode);
    const shopKey = String(directCustomer?.id || storedCustomer?.id || directCustomer?.phone || storedCustomer?.phone || receipt.invoice_id);
    const shopName = directCustomer?.name || storedCustomer?.name || directCustomer?.phone || storedCustomer?.phone || "Walk-in";

    team.shops.add(shopKey);
    team.amount += amount;
    team.latestSaleAt = receipt.timestamp || team.latestSaleAt;

    const resolvedTeam = teamByCode.get(teamCode);
    recentEvents.push({
      invoiceId: receipt.invoice_id,
      timestamp: receipt.timestamp,
      amount,
      shopName,
      teamName: resolvedTeam?.name || team.name,
      salesMan: resolvedTeam?.sales_man_name || team.salesMan,
    });
  });

  return {
    cards: Array.from(teamStats.values())
      .map((team) => ({
        code: team.code,
        name: team.name,
        salesMan: team.salesMan,
        shopsSold: team.shops.size,
        amount: team.amount,
        latestSaleAt: team.latestSaleAt,
      }))
      .filter((team) => team.shopsSold > 0 || team.amount > 0)
      .sort((left, right) => right.amount - left.amount),
    events: recentEvents
      .sort((left, right) => String(right.timestamp).localeCompare(String(left.timestamp)))
      .slice(0, 8),
  };
}

function uniqueTownships(items = []) {
  return [...new Set((items || []).map((item) => String(item || "").trim()).filter(Boolean))];
}

function buildTeamPayload(draft) {
  const townships = uniqueTownships(draft?.townships || []);
  return {
    name: draft?.name || "",
    sales_man_name: draft?.sales_man_name || "",
    position: draft?.position || "",
    phone: draft?.phone || "",
    township: townships[0] || "",
    townships,
    item_targets: (draft?.item_targets || []).filter((item) => Number(item.quantity || 0) > 0),
  };
}

function patchDraft(setter, patch) {
  setter((current) => ({
    ...current,
    ...patch,
  }));
}

function teamMonthlySalesSeries(team, receipts, customers) {
  const monthStart = new Date();
  monthStart.setDate(1);
  monthStart.setHours(0, 0, 0, 0);
  const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0);
  const coveredTownships = new Set(coveredTownshipsForTeam(team));
  const customerById = new Map((customers || []).map((customer) => [Number(customer.id), customer]));
  const totalsByDay = new Map();

  for (let day = 1; day <= monthEnd.getDate(); day += 1) {
    totalsByDay.set(day, 0);
  }

  (receipts || []).forEach((receipt) => {
    if (!receipt.timestamp) return;
    const saleDate = new Date(receipt.timestamp);
    if (Number.isNaN(saleDate.getTime())) return;
    if (saleDate < monthStart || saleDate > monthEnd) return;
    const customer = receipt.customer?.id
      ? customerById.get(Number(receipt.customer.id))
      : null;
    const belongsToTeam = (customer && customer.team_code === team.code)
      || (customer && coveredTownships.has(customer.township))
      || (receipt.customer && receipt.customer.team_code === team.code);
    if (!belongsToTeam) return;
    const day = saleDate.getDate();
    totalsByDay.set(day, Number(totalsByDay.get(day) || 0) + Number(receipt.invoice_total || receipt.grand_total || 0));
  });

  return Array.from(totalsByDay.entries()).map(([day, total]) => ({ day, total }));
}

function getDeviceId() {
  const existing = localStorage.getItem(DEVICE_ID_KEY);
  if (existing) return existing;
  localStorage.setItem(DEVICE_ID_KEY, DEFAULT_DEVICE_ID);
  return DEFAULT_DEVICE_ID;
}

function readQueue() {
  try {
    return JSON.parse(localStorage.getItem(OFFLINE_QUEUE_KEY) || "[]");
  } catch {
    return [];
  }
}

function readStoredUser() {
  try {
    const raw = localStorage.getItem(ADMIN_USER_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function persistSession(token, user) {
  if (token) {
    localStorage.setItem(ADMIN_TOKEN_KEY, token);
  } else {
    localStorage.removeItem(ADMIN_TOKEN_KEY);
  }
  if (user) {
    localStorage.setItem(ADMIN_USER_KEY, JSON.stringify(user));
  } else {
    localStorage.removeItem(ADMIN_USER_KEY);
  }
}

function writeQueue(queue) {
  localStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(queue));
}

function isAuthErrorMessage(message = "") {
  const normalized = String(message || "").toLowerCase();
  return normalized.includes("invalid token")
    || normalized.includes("missing bearer token")
    || normalized.includes("device mismatch");
}

function expireStoredSession(message = "Session expired. Please sign in again.") {
  persistSession("", null);
  window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT, { detail: { message } }));
}

async function api(path, method = "GET", token = "", body, queueOnFailure = true, extraHeaders = {}) {
  try {
    const res = await fetch(path, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-Device-ID": getDeviceId(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...extraHeaders,
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    const data = await res.json();
    if (!res.ok) {
      const message = data.error || "Request failed";
      if (res.status === 401 && token && isAuthErrorMessage(message)) {
        expireStoredSession();
        throw new Error("Session expired. Please sign in again.");
      }
      throw new Error(message);
    }
    return data;
  } catch (err) {
    if (queueOnFailure && method !== "GET" && err instanceof TypeError) {
      const queue = readQueue();
      queue.push({ path, method, body, token, extraHeaders });
      writeQueue(queue);
      throw new Error("Offline mode: action queued for sync");
    }
    throw err;
  }
}

function Login({ onLogin, lang, onToggleLang }) {
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("admin123");
  const [otpCode, setOtpCode] = useState("");
  const [error, setError] = useState("");

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const data = await api("/api/login", "POST", "", { username, password, otp_code: otpCode }, false);
      if (data.user?.role === "sales_staff") {
        throw new Error("Sales staff must use the mobile app.");
      }
      onLogin(data);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div className="app">
      <div className="card" style={{ maxWidth: "460px", margin: "8vh auto" }}>
        <h1 className="title">Shwe Htoo Thit</h1>
        <div className="space-between">
          <p className="subtitle">POS Management Console</p>
          <button type="button" className="secondary" onClick={onToggleLang}>{t(lang, "lang_toggle")}</button>
        </div>
        <form onSubmit={submit}>
          <div style={{ marginTop: 12 }}>
            <label>{t(lang, "username")}</label>
            <input value={username} onChange={(e) => setUsername(e.target.value)} />
          </div>
          <div style={{ marginTop: 12 }}>
            <label>{t(lang, "password")}</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
          </div>
          <div style={{ marginTop: 14 }}>
            <label>{t(lang, "otp")}</label>
            <input value={otpCode} onChange={(e) => setOtpCode(e.target.value)} placeholder="123456" />
          </div>
          <div style={{ marginTop: 14 }}>
            <button type="submit">{t(lang, "login")}</button>
          </div>
          {error && <p className="error">{error}</p>}
        </form>
        <p className="subtitle" style={{ marginTop: 12 }}>
          Web users: admin / cashier / storekeeper
        </p>
      </div>
    </div>
  );
}

function App() {
  const [token, setToken] = useState(localStorage.getItem(ADMIN_TOKEN_KEY) || "");
  const [user, setUser] = useState(readStoredUser());
  const [section, setSection] = useState("overview");
  const [lang, setLang] = useState(localStorage.getItem(LANGUAGE_KEY) || DEFAULT_LANG);

  const [products, setProducts] = useState([]);
  const [customers, setCustomers] = useState([]);
  const [teams, setTeams] = useState([]);
  const [accounts, setAccounts] = useState([]);
  const [cart, setCart] = useState({ items: [], total: 0 });
  const [alerts, setAlerts] = useState([]);
  const [shifts, setShifts] = useState([]);
  const [receipts, setReceipts] = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);

  const [salesReport, setSalesReport] = useState(null);
  const [inventoryReport, setInventoryReport] = useState(null);
  const [pnlReport, setPnlReport] = useState(null);
  const [employeeSalesReport, setEmployeeSalesReport] = useState(null);

  const [promotions, setPromotions] = useState([]);
  const [paymentOptions, setPaymentOptions] = useState([]);

  const [queueCount, setQueueCount] = useState(readQueue().length);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const [overviewLiveNotice, setOverviewLiveNotice] = useState("");
  const seenOverviewReceiptIds = useRef(new Set());
  const overviewNoticeTimer = useRef(null);

  const [sku, setSku] = useState("T100");
  const [qty, setQty] = useState(1);
  const [discount, setDiscount] = useState(0);
  const [promoCode, setPromoCode] = useState("");
  const [customerId, setCustomerId] = useState("");
  const [payments, setPayments] = useState([{ method: "cash", amount: "" }]);
  const [taxConfig, setTaxConfig] = useState({ enabled: false, rate: "5", tin: "" });

  const [customerForm, setCustomerForm] = useState({ name: "", phone: "", township: "", address: "" });
  const [editingCustomer, setEditingCustomer] = useState(null);
  const [showCreateCustomerModal, setShowCreateCustomerModal] = useState(false);
  const [teamForm, setTeamForm] = useState(emptyTeamForm());
  const [teamModalOpen, setTeamModalOpen] = useState(false);
  const [editingTeam, setEditingTeam] = useState(null);
  const [accountForm, setAccountForm] = useState(emptySalesAccountForm(products));
  const [editingAccount, setEditingAccount] = useState(null);
  const [editingProduct, setEditingProduct] = useState(null);

  const [newProduct, setNewProduct] = useState({
    sku: "",
    name: "",
    price: "",
    cost_price: "",
    category: "စားသုံးဆီ",
    unit: "pcs",
    low_stock_threshold: "",
  });
  const [stockPatch, setStockPatch] = useState({ sku: "", delta: "" });
  const [showThreshold, setShowThreshold] = useState(false);

  const [salesPeriod, setSalesPeriod] = useState("daily");
  const [pnlPeriod, setPnlPeriod] = useState("monthly");

  const role = user?.role || "";
  const canSell = ["cashier"].includes(role);
  const canStock = ["admin", "storekeeper"].includes(role);
  const canCustomers = ["admin", "cashier", "storekeeper"].includes(role);
  const canTeams = ["admin", "storekeeper"].includes(role);
  const canUsers = role === "admin";
  const canPnl = role === "admin";
  const canAudit = role === "admin";
  const townshipOptions = [...new Set(
    teams.flatMap((team) =>
      Array.isArray(team.townships) && team.townships.length
        ? team.townships
        : (team.township ? [team.township] : [])
    ).filter(Boolean)
  )];
  const customerTownshipOptions = townshipOptions.length ? townshipOptions : YANGON_REGION_TOWNSHIPS;
  const teamsWithCustomers = teams.map((team) => ({
    ...team,
    customers: customers.filter((customer) => {
      if (customer.team_code) return customer.team_code === team.code;
      const coveredTownships = Array.isArray(team.townships) && team.townships.length
        ? team.townships
        : (team.township ? [team.township] : []);
      return coveredTownships.includes(customer.township);
    }),
  }));
  const activeTeamDraft = editingTeam || teamForm;
  const overviewLiveData = buildOverviewLiveData(teams, customers, receipts);

  const clearFlash = () => {
    setMsg("");
    setErr("");
  };
  const applySession = (nextToken, nextUser) => {
    setToken(nextToken || "");
    setUser(nextUser || null);
    persistSession(nextToken || "", nextUser || null);
  };
  const logout = () => {
    applySession("", null);
  };
  const toggleLang = () => {
    const next = lang === "en" ? "my" : "en";
    setLang(next);
    localStorage.setItem(LANGUAGE_KEY, next);
  };

  const refreshQueueCount = () => setQueueCount(readQueue().length);

  const loadProducts = async () => setProducts((await api("/api/products", "GET", token)).products);
  const loadCustomers = async () => setCustomers((await api("/api/customers", "GET", token)).customers);
  const loadTeams = async () => setTeams((await api("/api/teams", "GET", token)).teams || []);
  const loadUsers = async () => setAccounts((await api("/api/users", "GET", token)).users || []);
  const loadCart = async () => setCart(await api("/api/cart", "GET", token));
  const loadAlerts = async () => {
    try {
      const data = await api("/api/alerts/low-stock", "GET", token);
      setAlerts(data.alerts);
    } catch {
      setAlerts([]);
    }
  };
  const loadShifts = async () => setShifts((await api("/api/shifts", "GET", token)).shifts);
  const loadReceipts = async () => setReceipts((await api("/api/receipts?limit=200", "GET", token)).receipts);
  const loadAuditLogs = async () => {
    if (!canAudit) {
      setAuditLogs([]);
      return;
    }
    setAuditLogs((await api("/api/audit-logs?limit=100", "GET", token)).logs);
  };
  const loadPromotions = async () => setPromotions((await api("/api/promotions", "GET", token)).promotions);
  const loadPaymentOptions = async () => {
    const data = await api("/api/payment-options", "GET", token);
    setPaymentOptions(data.payment_options);
    setPayments((old) => old.map((p) => ({ ...p, method: data.payment_options.includes(p.method) ? p.method : data.payment_options[0] })));
  };

  const loadReports = async () => {
    setSalesReport((await api(`/api/reports/sales?period=${salesPeriod}`, "GET", token)).report);
    setEmployeeSalesReport((await api("/api/reports/employee-sales", "GET", token)).report);
    if (canStock) {
      setInventoryReport((await api("/api/reports/inventory", "GET", token)).report);
    }
    if (canPnl) {
      setPnlReport((await api(`/api/reports/profit-loss?period=${pnlPeriod}`, "GET", token)).report);
    }
  };

  const loadAll = async () => {
    const tasks = [loadProducts(), loadCart(), loadReceipts(), loadPromotions(), loadPaymentOptions(), loadShifts()];
    if (canCustomers) tasks.push(loadCustomers(), loadTeams());
    if (canUsers) tasks.push(loadUsers());
    if (canStock) tasks.push(loadAlerts());
    if (canAudit) tasks.push(loadAuditLogs());
    await Promise.all(tasks);
  };

  useEffect(() => {
    if (!token) return;
    loadAll().catch((e) => setErr(e.message));
  }, [token]);

  useEffect(() => {
    if (user?.role !== "sales_staff") return;
    applySession("", null);
    setErr("Sales staff web access has been removed. Please use the mobile app.");
  }, [user]);

  useEffect(() => {
    const handleAuthExpired = (event) => {
      applySession("", null);
      setErr(event.detail?.message || "Session expired. Please sign in again.");
    };
    window.addEventListener(AUTH_EXPIRED_EVENT, handleAuthExpired);
    return () => window.removeEventListener(AUTH_EXPIRED_EVENT, handleAuthExpired);
  }, []);

  useEffect(() => {
    if (!token || section !== "reports") return;
    loadReports().catch((e) => setErr(e.message));
  }, [section, salesPeriod, pnlPeriod]);

  useEffect(() => {
    if (!token || section !== "overview" || !canAudit) return undefined;
    const timer = setInterval(() => {
      Promise.all([loadReceipts(), loadCustomers(), loadTeams()]).catch((e) => setErr(e.message));
    }, 5000);
    return () => clearInterval(timer);
  }, [token, section, canAudit]);

  useEffect(() => {
    if (!token || section !== "stock" || !canStock) return undefined;
    const timer = setInterval(() => {
      Promise.all([loadProducts(), loadAlerts()]).catch((e) => setErr(e.message));
    }, 5000);
    return () => clearInterval(timer);
  }, [token, section, canStock]);

  useEffect(() => {
    if (!canAudit) return;
    const currentIds = receipts.map((receipt) => receipt.invoice_id);
    if (!seenOverviewReceiptIds.current.size) {
      seenOverviewReceiptIds.current = new Set(currentIds);
      return;
    }

    const newReceipts = receipts.filter((receipt) => !seenOverviewReceiptIds.current.has(receipt.invoice_id));
    currentIds.forEach((id) => seenOverviewReceiptIds.current.add(id));
    if (!newReceipts.length) return;

    const latest = newReceipts
      .filter((receipt) => isSameCalendarDay(receipt.timestamp))
      .sort((left, right) => String(right.timestamp).localeCompare(String(left.timestamp)))[0];
    if (!latest) return;

    const directCustomer = latest.customer || null;
    const storedCustomer = directCustomer?.id
      ? customers.find((customer) => Number(customer.id) === Number(directCustomer.id))
      : null;
    const teamCode = String(directCustomer?.team_code || storedCustomer?.team_code || "").toUpperCase();
    const team = teams.find((item) => String(item.code || "").toUpperCase() === teamCode);
    const shopName = directCustomer?.name || storedCustomer?.name || directCustomer?.phone || storedCustomer?.phone || "Walk-in";
    const amount = Number(latest.invoice_total || latest.grand_total || 0);

    setOverviewLiveNotice(`${team?.name || "Sales team"} finished order for ${shopName} - ${formatKs(amount)}`);
    if (overviewNoticeTimer.current) clearTimeout(overviewNoticeTimer.current);
    overviewNoticeTimer.current = setTimeout(() => setOverviewLiveNotice(""), 6000);
  }, [receipts, customers, teams, canAudit]);

  useEffect(() => () => {
    if (overviewNoticeTimer.current) clearTimeout(overviewNoticeTimer.current);
  }, []);

  useEffect(() => {
    setTeamForm((current) => ({
      ...current,
      item_targets: buildTeamTargets(products, current.item_targets),
    }));
    setEditingTeam((current) => (
      current
        ? { ...current, item_targets: buildTeamTargets(products, current.item_targets) }
        : current
    ));
    setAccountForm((current) => ({
      ...current,
      team_draft: {
        ...(current.team_draft || emptyTeamForm(products)),
        item_targets: buildTeamTargets(products, current.team_draft?.item_targets),
      },
    }));
  }, [products]);

  const openCreateTeamModal = () => {
    setEditingTeam(null);
    setTeamForm(emptyTeamForm(products));
    setTeamModalOpen(true);
  };

  const openEditTeamModal = (team) => {
    setEditingTeam(normalizeTeamDraft(team, products));
    setTeamModalOpen(true);
  };

  const closeTeamModal = () => {
    setTeamModalOpen(false);
    setEditingTeam(null);
    setTeamForm(emptyTeamForm(products));
  };

  const openCreateAccount = () => {
    setEditingAccount(null);
    setAccountForm(emptySalesAccountForm(products));
  };

  const openEditAccount = (account) => {
    setEditingAccount(normalizeSalesAccountDraft(account));
  };

  const closeAccountEditor = () => {
    setEditingAccount(null);
    setAccountForm(emptySalesAccountForm(products));
  };

  const validateTeamDraft = (draft) => {
    const payload = buildTeamPayload(draft);
    if (!payload.name.trim() || !payload.sales_man_name.trim() || !payload.position.trim() || !payload.phone.trim()) {
      throw new Error("Team Name, Sale Man Name, Position, and Phone Number are required");
    }
    if (!payload.townships.length) {
      throw new Error("Select at least one township for the team");
    }
    return payload;
  };

  const createTeamRecord = async (draft) => {
    const payload = validateTeamDraft(draft);
    const data = await api("/api/teams", "POST", token, payload);
    if (data.team) {
      setTeams((current) => [...current.filter((team) => team.id !== data.team.id), data.team]);
      return data.team;
    }
    throw new Error("Team creation failed");
  };

  const addPaymentRow = () => {
    setPayments((old) => [...old, { method: paymentOptions[0] || "cash", amount: "" }]);
  };

  const updatePaymentRow = (idx, key, value) => {
    setPayments((old) => old.map((r, i) => (i === idx ? { ...r, [key]: value } : r)));
  };

  const removePaymentRow = (idx) => {
    setPayments((old) => (old.length > 1 ? old.filter((_, i) => i !== idx) : old));
  };

  const doAddCart = async () => {
    clearFlash();
    try {
      await api("/api/cart/add", "POST", token, { sku, qty: Number(qty) });
      await loadCart();
      setMsg("Added to cart");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doRemoveCart = async () => {
    clearFlash();
    try {
      await api("/api/cart/remove", "POST", token, { sku, qty: Number(qty) });
      await loadCart();
      setMsg("Removed from cart");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doCheckout = async () => {
    clearFlash();
    try {
      if (!cart.items.length) {
        setErr(t(lang, "cart_empty"));
        return;
      }
      const paymentPayload = payments
        .map((p) => ({ method: p.method, amount: Number(p.amount) }))
        .filter((p) => p.amount > 0);
      if (!paymentPayload.length) {
        setErr(t(lang, "invalid_payment"));
        return;
      }
      const invoiceBase = Number(cart.total || 0) * (1 - Number(discount || 0) / 100);
      const invoiceTax = taxConfig.enabled ? invoiceBase * (Number(taxConfig.rate || 0) / 100) : 0;
      const invoiceNeed = Number((invoiceBase + invoiceTax).toFixed(2));
      const paid = Number(paymentPayload.reduce((n, p) => n + Number(p.amount || 0), 0).toFixed(2));
      if (paid < invoiceNeed) {
        setErr(`${t(lang, "invalid_payment")} (${paid.toFixed(2)} < ${invoiceNeed.toFixed(2)})`);
        return;
      }

      const idempotencyKey = `checkout-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
      const result = await api(
        "/api/checkout",
        "POST",
        token,
        {
          discount_pct: Number(discount),
          promo_code: promoCode,
          payments: paymentPayload,
          customer_id: customerId ? Number(customerId) : null,
          generate_tax_invoice: taxConfig.enabled,
          tax_rate: Number(taxConfig.rate || 0),
          tax_tin: taxConfig.tin,
        },
        true,
        { "Idempotency-Key": idempotencyKey }
      );

      const refreshTasks = [loadCart(), loadProducts(), loadReceipts(), loadAlerts()];
      if (section === "reports") refreshTasks.push(loadReports().catch(() => {}));
      await Promise.all(refreshTasks);
      setMsg(`Invoice ${result.receipt.invoice_id} generated (${result.exports.csv}, ${result.exports.pdf})`);
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doCreateCustomer = async () => {
    clearFlash();
    try {
      await api("/api/customers", "POST", token, customerForm);
      setCustomerForm({ name: "", phone: "", township: "", address: "" });
      setShowCreateCustomerModal(false);
      await loadCustomers();
      setMsg("Customer created");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doUpdateCustomer = async () => {
    clearFlash();
    if (!editingCustomer) return;
    try {
      await api(`/api/customers/${editingCustomer.id}`, "PATCH", token, editingCustomer);
      setEditingCustomer(null);
      await loadCustomers();
      setMsg("Customer updated");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doDeleteCustomer = async (id) => {
    clearFlash();
    try {
      await api(`/api/customers/${id}`, "DELETE", token);
      await loadCustomers();
      setMsg("Customer deleted");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doCreateTeam = async () => {
    clearFlash();
    try {
      const team = await createTeamRecord(teamForm);
      closeTeamModal();
      await Promise.all([loadTeams(), loadCustomers()]);
      setMsg(`Team created with ${coveredTownshipsForTeam(team).length} townships`);
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doUpdateTeam = async () => {
    clearFlash();
    if (!editingTeam) return;
    try {
      const payload = validateTeamDraft(editingTeam);
      const data = await api(`/api/teams/${editingTeam.id}`, "PATCH", token, payload);
      if (data.team) {
        setTeams((current) => current.map((team) => (team.id === data.team.id ? data.team : team)));
      }
      closeTeamModal();
      await Promise.all([loadTeams(), loadCustomers()]);
      setMsg(`Team updated with ${payload.townships.length} townships`);
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doDeleteTeam = async (id) => {
    clearFlash();
    try {
      await api(`/api/teams/${id}`, "DELETE", token);
      if (editingTeam && editingTeam.id === id) closeTeamModal();
      await Promise.all([loadTeams(), loadCustomers()]);
      setMsg("Team deleted");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doCreateAccount = async () => {
    clearFlash();
    try {
      if (!accountForm.username.trim() || !accountForm.password.trim()) {
        setErr("Username and password are required");
        return;
      }
      let teamCode = accountForm.team_code;
      if (accountForm.use_new_team) {
        const team = await createTeamRecord(accountForm.team_draft);
        teamCode = team.code;
      }
      if (!String(teamCode || "").trim()) {
        setErr("Select a sale team or create a new one");
        return;
      }
      const data = await api("/api/users", "POST", token, {
        username: accountForm.username.trim(),
        full_name: accountForm.full_name.trim(),
        password: accountForm.password,
        role: "sales_staff",
        team_code: teamCode,
        active: accountForm.active,
      });
      setAccounts((current) => [...current.filter((item) => item.username !== data.user.username), data.user]);
      closeAccountEditor();
      await Promise.all([loadUsers(), loadTeams(), loadCustomers()]);
      setMsg(accountForm.use_new_team ? "Sales account and new team created" : "Sales account created");
    } catch (e) {
      setErr(e.message);
    }
  };

  const doUpdateAccount = async () => {
    clearFlash();
    if (!editingAccount) return;
    try {
      const payload = {
        full_name: editingAccount.full_name.trim(),
        team_code: editingAccount.team_code,
        active: editingAccount.active,
        ...(editingAccount.password.trim() ? { password: editingAccount.password } : {}),
      };
      const data = await api(`/api/users/${editingAccount.username}`, "PATCH", token, payload);
      setAccounts((current) => current.map((item) => (item.username === data.user.username ? data.user : item)));
      closeAccountEditor();
      await loadUsers();
      setMsg("Sales account updated");
    } catch (e) {
      setErr(e.message);
    }
  };

  const doDeleteAccount = async (username) => {
    clearFlash();
    try {
      await api(`/api/users/${username}`, "DELETE", token);
      if (editingAccount && editingAccount.username === username) {
        closeAccountEditor();
      }
      await loadUsers();
      setMsg("Sales account deleted");
    } catch (e) {
      setErr(e.message);
    }
  };

  const renderTownshipDropdownManager = (draft, setter) => {
    const selectedTownships = uniqueTownships(draft.townships || []);
    const claimedByOtherTeam = new Map(
      teams
        .filter((team) => team.code !== draft.code)
        .flatMap((team) =>
          coveredTownshipsForTeam(team).map((township) => [township, team.name || team.code])
        )
    );
    return (
      <div style={{ marginTop: 10 }}>
        <p className="subtitle" style={{ margin: "0 0 8px" }}>
          မြို့နယ်တွေကို dropdown ထဲက checkbox နဲ့ multi ရွေးနိုင်ပါတယ်။ ရွေးပြီးသားကို `✓`, အခြား team ကသုံးနေတဲ့မြို့နယ်ကို disabled ပြထားပါတယ်။
        </p>
        <details className="township-dropdown township-picker">
          <summary>{selectedTownships.length ? `${selectedTownships.length} townships selected` : "Select township(s)"}</summary>
          <div className="township-dropdown-menu">
            {YANGON_REGION_TOWNSHIPS.map((township) => {
              const selected = selectedTownships.includes(township);
              const claimedBy = claimedByOtherTeam.get(township);
              const locked = Boolean(claimedBy) && !selected;
              return (
                <label
                  key={township}
                  className={`township-dropdown-item township-option ${locked ? "locked" : ""}`}
                >
                  <input
                    type="checkbox"
                    checked={selected}
                    disabled={locked}
                    onChange={() => {
                      setter((current) => {
                        const nextTownships = toggleTownshipSelection(current?.townships || [], township);
                        return {
                          ...current,
                          township: nextTownships[0] || "",
                          townships: nextTownships,
                        };
                      });
                    }}
                  />
                  <span>{selected ? `✓ ${township}` : township}</span>
                  {locked && <span className="subtitle">{claimedBy}</span>}
                </label>
              );
            })}
          </div>
        </details>
        <div className="stack" style={{ marginTop: 10 }}>
          {selectedTownships.length ? selectedTownships.map((township) => (
            <div className="list-row township-row" key={`${draft.code || draft.name || "new"}-${township}`}>
              <span>{township}</span>
              <button
                type="button"
                className="secondary"
                onClick={() => {
                  setter((current) => ({
                    ...current,
                    township: current?.township || "",
                    townships: uniqueTownships(current?.townships || []).filter((item) => item !== township),
                  }));
                }}
              >
                Remove
              </button>
            </div>
          )) : <p className="subtitle" style={{ margin: 0 }}>No township selected yet.</p>}
        </div>
      </div>
    );
  };

  const renderItemTargetPlanner = (draft, setter) => (
    <div style={{ marginTop: 14 }}>
      <div className="space-between">
        <strong>Item Quantity Targets</strong>
        <span className="badge">
          {(draft.item_targets || []).filter((item) => Number(item.quantity || 0) > 0).length} items
        </span>
      </div>
      <p className="subtitle" style={{ margin: "8px 0 10px" }}>
        Admin က team တစ်ခုချင်းစီအတွက် ရောင်းရမယ့် item quantity ကို manual သတ်မှတ်နိုင်ပါတယ်။
      </p>
      <div className="stack">
        {(draft.item_targets || []).map((item, index) => (
          <div className="list-row" key={`${draft.code || draft.name || "new"}-${item.sku}`}>
            <span><strong>{item.sku}</strong> {item.name}</span>
            <input
              type="number"
              min="0"
              value={item.quantity}
              onChange={(e) => {
                const nextQty = Math.max(0, Number(e.target.value || 0));
                setter((current) => ({
                  ...current,
                  item_targets: (current?.item_targets || []).map((target, targetIndex) => (
                    targetIndex === index ? { ...target, quantity: nextQty } : target
                  )),
                }));
              }}
              style={{ width: 120 }}
            />
          </div>
        ))}
      </div>
    </div>
  );

  const renderTownshipDropdownTag = (team) => {
    const townships = coveredTownshipsForTeam(team);
    return (
      <details className="township-dropdown">
        <summary>{townships.length ? `${townships.length} townships` : "No township"}</summary>
        <div className="township-dropdown-menu">
          {townships.length ? townships.map((township) => (
            <div key={`${team.code}-${township}`} className="township-dropdown-item">{township}</div>
          )) : <div className="township-dropdown-item">No township assigned</div>}
        </div>
      </details>
    );
  };

  const renderTeamMonthlySalesChart = (team) => {
    const series = teamMonthlySalesSeries(team, receipts, customers);
    const maxTotal = Math.max(...series.map((entry) => entry.total), 1);
    const monthLabel = new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric" }).format(new Date());
    const totalRevenue = series.reduce((sum, entry) => sum + entry.total, 0);
    return (
      <div style={{ marginTop: 16 }}>
        <div className="space-between">
          <strong>{monthLabel} Team Sales</strong>
        <span className="badge">{formatKs(totalRevenue)}</span>
        </div>
        <div className="team-chart">
          {series.map((entry) => (
            <div className="team-chart-bar-wrap" key={`${team.code}-${entry.day}`}>
              <div
                className="team-chart-bar"
                style={{ height: `${Math.max(8, (entry.total / maxTotal) * 150)}px` }}
                title={`Day ${entry.day}: ${formatKs(entry.total)}`}
              />
              <span>{entry.day}</span>
            </div>
          ))}
        </div>
      </div>
    );
  };

  const doShiftStart = async () => {
    clearFlash();
    try {
      await api("/api/shifts/start", "POST", token, {});
      await loadShifts();
      setMsg("Shift started");
    } catch (e) {
      setErr(e.message);
    }
  };

  const doShiftEnd = async () => {
    clearFlash();
    try {
      await api("/api/shifts/end", "POST", token, {});
      await loadShifts();
      setMsg("Shift ended");
    } catch (e) {
      setErr(e.message);
    }
  };

  const doAddProduct = async () => {
    clearFlash();
    try {
      await api("/api/products", "POST", token, {
        ...newProduct,
        price: Number(newProduct.price),
        cost_price: Number(newProduct.cost_price),
        stock: 0,
        low_stock_threshold: Number(newProduct.low_stock_threshold),
      });
      setNewProduct({
        sku: "",
        name: "",
        price: "",
        cost_price: "",
        category: "စားသုံးဆီ",
    unit: "pcs",
        low_stock_threshold: "",
      });
      await Promise.all([loadProducts(), loadAlerts()]);
      setMsg("Product added");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doUpdateStock = async () => {
    clearFlash();
    try {
      await api(`/api/products/${stockPatch.sku}/stock`, "PATCH", token, { delta: Number(stockPatch.delta) });
      setStockPatch({ sku: "", delta: "" });
      await Promise.all([loadProducts(), loadAlerts()]);
      setMsg("Stock updated");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doUpdateProduct = async () => {
    clearFlash();
    if (!editingProduct) return;
    try {
      await api(`/api/products/${editingProduct.sku}`, "PATCH", token, {
        name: editingProduct.name,
        price: Number(editingProduct.price),
        cost_price: Number(editingProduct.cost_price),
        category: editingProduct.category,
        unit: editingProduct.unit,
        low_stock_threshold: Number(editingProduct.low_stock_threshold),
      });
      setEditingProduct(null);
      await Promise.all([loadProducts(), loadAlerts()]);
      setMsg("Item updated");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const doDeleteProduct = async (itemId) => {
    clearFlash();
    try {
      await api(`/api/products/${itemId}`, "DELETE", token);
      if (editingProduct && editingProduct.sku === itemId) setEditingProduct(null);
      await Promise.all([loadProducts(), loadAlerts()]);
      setMsg("Item deleted");
    } catch (e) {
      setErr(e.message);
      refreshQueueCount();
    }
  };

  const syncOfflineQueue = async () => {
    clearFlash();
    const queue = readQueue();
    if (!queue.length) {
      setMsg("No offline actions to sync");
      return;
    }

    const remaining = [];
    for (const action of queue) {
      try {
        await api(action.path, action.method, action.token || token, action.body, false, action.extraHeaders || {});
      } catch {
        remaining.push(action);
      }
    }

    writeQueue(remaining);
    refreshQueueCount();
    setMsg(remaining.length ? `Synced partially. Remaining ${remaining.length}` : "Offline queue synced");
    await loadAll();
  };

  const quickSkuOptions = products.slice(0, 8).map((p) => p.sku);

  const setQuickPayment = (extra = 0) => {
    const payable = Number((cart.total || 0) + extra).toFixed(2);
    setPayments([{ method: "cash", amount: payable }]);
  };

  const printReceipt = (receipt, paper = "thermal") => {
    const tax = receipt.tax_invoice || {};
    const rows = receipt.items
      .map(
        (i) =>
          `<tr><td>${i.sku}</td><td>${i.name}</td><td>${i.quantity} pcs</td><td>${formatKs(i.line_total)}</td></tr>`
      )
      .join("");
    const width = paper === "thermal" ? "80mm" : "210mm";
    const html = `
      <html>
        <head>
          <title>Invoice ${receipt.invoice_id}</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 8mm; }
            .sheet { width: ${width}; max-width: 100%; }
            h2, p { margin: 0 0 6px 0; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; }
            th, td { border-bottom: 1px solid #ddd; text-align: left; padding: 4px; }
          </style>
        </head>
        <body>
          <div class="sheet">
            <h2>Shwe Htoo Thit</h2>
            <p>Invoice: ${receipt.invoice_id}</p>
            <p>Time: ${receipt.timestamp}</p>
            <p>Cashier: ${receipt.cashier || "-"}</p>
            <table>
              <thead><tr><th>SKU</th><th>Item</th><th>Qty</th><th>Total</th></tr></thead>
              <tbody>${rows}</tbody>
            </table>
            <p>Subtotal: ${formatKs(receipt.subtotal || 0)}</p>
            <p>Discount: ${formatKs(receipt.discount || 0)}</p>
            <p>Grand Total: ${formatKs(receipt.grand_total || 0)}</p>
            <p>Tax: ${formatKs(tax.tax_amount || 0)}</p>
            <p><strong>Invoice Total: ${formatKs(receipt.invoice_total || receipt.grand_total || 0)}</strong></p>
          </div>
        </body>
      </html>`;
    const win = window.open("", "_blank", "width=900,height=900");
    if (!win) return setErr("Popup blocked. Allow popups for printing.");
    win.document.write(html);
    win.document.close();
    win.focus();
    win.print();
  };

  if (!token || !user) {
    return (
      <Login
        lang={lang}
        onToggleLang={toggleLang}
        onLogin={(data) => {
          applySession(data.token, data.user);
        }}
      />
    );
  }

  return (
    <div className="app shell">
      <aside className="sidebar card">
        <div>
          <h2 className="sidebar-title">Shwe Htoo Thit</h2>
          <p className="subtitle">{user.username} ({user.role})</p>
        </div>

        <div className="sidebar-nav">
          <button className={`nav-btn ${section === "overview" ? "active" : ""}`} onClick={() => setSection("overview")}>{t(lang, "overview")}</button>
          {canSell && <button className={`nav-btn ${section === "sales" ? "active" : ""}`} onClick={() => setSection("sales")}>{t(lang, "sales")}</button>}
          {canTeams && <button className={`nav-btn ${section === "teams" ? "active" : ""}`} onClick={() => setSection("teams")}>{t(lang, "teams")}</button>}
          {canUsers && <button className={`nav-btn ${section === "accounts" ? "active" : ""}`} onClick={() => setSection("accounts")}>Accounts</button>}
          {canCustomers && <button className={`nav-btn ${section === "customers" ? "active" : ""}`} onClick={() => setSection("customers")}>{t(lang, "customers")}</button>}
          <button className={`nav-btn ${section === "shifts" ? "active" : ""}`} onClick={() => setSection("shifts")}>{t(lang, "shifts")}</button>
          <button className={`nav-btn ${section === "reports" ? "active" : ""}`} onClick={() => setSection("reports")}>{t(lang, "reports")}</button>
          {canAudit && <button className={`nav-btn ${section === "audit" ? "active" : ""}`} onClick={() => setSection("audit")}>{t(lang, "audit")}</button>}
          {canStock && <button className={`nav-btn ${section === "stock" ? "active" : ""}`} onClick={() => setSection("stock")}>{t(lang, "stock")}</button>}
          <button className={`nav-btn ${section === "receipts" ? "active" : ""}`} onClick={() => setSection("receipts")}>{t(lang, "receipts")}</button>
        </div>

        <div className="card" style={{ padding: 10 }}>
          <div className="space-between">
            <span className="subtitle">Offline Queue</span>
            <span className="mono">{queueCount}</span>
          </div>
          <button className="secondary" onClick={syncOfflineQueue} style={{ marginTop: 8 }}>
            {t(lang, "sync")}
          </button>
        </div>

        <button className="secondary" onClick={toggleLang}>{t(lang, "lang_toggle")}</button>
        <button className="danger" onClick={logout}>{t(lang, "logout")}</button>
      </aside>

      <main className="content">
        <div className="header">
          <div>
            <h1 className="title">Shwe Htoo Thit</h1>
            <p className="subtitle">Role-based POS with shifts, reports, and offline sync queue</p>
          </div>
          <button className="secondary" onClick={() => loadAll().catch((e) => setErr(e.message))}>{t(lang, "refresh")}</button>
        </div>

        <div className="grid">
          {section === "overview" && (
            <>
              <div className="card col-3"><p className="subtitle">Products</p><p className="kpi">{products.length}</p></div>
              <div className="card col-3"><p className="subtitle">Customers</p><p className="kpi">{customers.length}</p></div>
              <div className="card col-3"><p className="subtitle">Cart Total</p><p className="kpi">{formatKs(cart.total)}</p></div>
              <div className="card col-3"><p className="subtitle">Low Stock Alerts</p><p className="kpi">{alerts.length}</p></div>
              {canAudit && <div className="card col-3"><p className="subtitle">Audit Events</p><p className="kpi">{auditLogs.length}</p></div>}
              {canAudit && overviewLiveNotice && (
                <div className="card col-12 success">
                  <div className="space-between">
                    <strong>Live Update</strong>
                    <span className="badge">Order Finished</span>
                  </div>
                  <p style={{ margin: "10px 0 0" }}>{overviewLiveNotice}</p>
                </div>
              )}
              {canAudit && (
                <div className="card col-12">
                  <div className="space-between">
                    <div>
                      <h3>Today Sales Team Updates</h3>
                      <p className="subtitle" style={{ marginTop: 6 }}>Admin overview အတွက် team တစ်ခုချင်းစီရဲ့ ဒီနေ့ shop sold count နဲ့ amount ကို live card box နဲ့ပြထားပါတယ်။</p>
                    </div>
                    <span className="badge">{overviewLiveData.cards.length} active teams</span>
                  </div>
                  <div className="grid" style={{ marginTop: 16 }}>
                    {overviewLiveData.cards.length ? overviewLiveData.cards.map((item) => (
                      <div className="card col-4" key={`overview-${item.code}`} style={{ padding: 14 }}>
                        <p className="subtitle" style={{ margin: 0 }}>{item.name}</p>
                        <h3 style={{ margin: "8px 0 4px" }}>{item.shopsSold} shop sold</h3>
                        <p className="kpi" style={{ margin: "4px 0" }}>{formatKs(item.amount)}</p>
                        <p className="subtitle" style={{ margin: "6px 0 0" }}>Salesman: {item.salesMan}</p>
                        <p className="subtitle" style={{ margin: "4px 0 0" }}>Latest: {item.latestSaleAt || "-"}</p>
                      </div>
                    )) : <p className="subtitle" style={{ margin: 0 }}>No team sales recorded today yet.</p>}
                  </div>
                </div>
              )}
              {canAudit && (
                <div className="card col-12">
                  <div className="space-between">
                    <h3>Recent Order Finish Updates</h3>
                    <span className="subtitle">Auto refresh every 5 seconds</span>
                  </div>
                  <div className="stack" style={{ marginTop: 12 }}>
                    {overviewLiveData.events.length ? overviewLiveData.events.map((event) => (
                      <div className="list-row" key={`event-${event.invoiceId}`}>
                        <span><strong>{event.teamName}</strong> - {event.shopName}</span>
                        <span>{event.salesMan}</span>
                        <span>{formatKs(event.amount)}</span>
                        <span>{event.timestamp}</span>
                      </div>
                    )) : <p className="subtitle" style={{ margin: 0 }}>No completed orders today yet.</p>}
                  </div>
                </div>
              )}

              <div className="card col-6">
                <h3>Promotions</h3>
                {promotions.map((p) => <div className="list-row" key={p.code}><span className="mono">{p.code}</span><span>{p.type}</span><span>{p.category || "all"}</span></div>)}
              </div>
              <div className="card col-6">
                <h3>Low Stock</h3>
                {alerts.map((a) => <div className={`list-row ${a.severity}`} key={a.sku}><span className="mono">{a.sku}</span><span>{a.name}</span><span>{a.stock}/{a.threshold} pcs</span></div>)}
              </div>
            </>
          )}

          {section === "sales" && canSell && (
            <>
              <div className="card col-5">
                <h3>Sale Entry</h3>
                <div className="row">
                  {quickSkuOptions.map((code) => (
                    <button key={code} className="secondary quick-btn" onClick={() => setSku(code)}>{code}</button>
                  ))}
                </div>
                <div style={{ height: 8 }} />
                <div className="row"><input value={sku} onChange={(e) => setSku(e.target.value.toUpperCase())} placeholder="SKU" /><input type="number" min="1" value={qty} onChange={(e) => setQty(e.target.value)} /></div>
                <div className="row" style={{ marginTop: 8 }}>
                  <button className="secondary quick-btn" onClick={() => setQty(Math.max(1, Number(qty || 1) - 1))}>-1</button>
                  <button className="secondary quick-btn" onClick={() => setQty(Number(qty || 1) + 1)}>+1</button>
                  <button className="secondary quick-btn" onClick={() => setQty(Number(qty || 1) + 5)}>+5</button>
                </div>
                <div className="row" style={{ marginTop: 8 }}><button onClick={doAddCart}>{t(lang, "add")}</button><button className="secondary" onClick={doRemoveCart}>{t(lang, "remove")}</button></div>
                <div style={{ marginTop: 8 }}><label>Discount %</label><input type="number" min="0" max="100" value={discount} onChange={(e) => setDiscount(e.target.value)} /></div>
                <div style={{ marginTop: 8 }}><label>Promo Code</label><input value={promoCode} onChange={(e) => setPromoCode(e.target.value.toUpperCase())} /></div>
                <div style={{ marginTop: 8 }}><label>Customer ID (optional)</label><input value={customerId} onChange={(e) => setCustomerId(e.target.value)} /></div>
                <div style={{ marginTop: 8 }} className="row">
                  <label><input type="checkbox" checked={taxConfig.enabled} onChange={(e) => setTaxConfig({ ...taxConfig, enabled: e.target.checked })} /> {t(lang, "tax_invoice")}</label>
                </div>
                {taxConfig.enabled && (
                  <>
                    <div style={{ marginTop: 8 }}><label>{t(lang, "tax_rate")}</label><input type="number" min="0" step="0.01" value={taxConfig.rate} onChange={(e) => setTaxConfig({ ...taxConfig, rate: e.target.value })} /></div>
                    <div style={{ marginTop: 8 }}><label>{t(lang, "tin")}</label><input value={taxConfig.tin} onChange={(e) => setTaxConfig({ ...taxConfig, tin: e.target.value })} /></div>
                  </>
                )}

                <div style={{ marginTop: 8 }}>
                  <div className="space-between"><label>Payments</label><button className="secondary" onClick={addPaymentRow}>Add</button></div>
                  <div className="row" style={{ marginTop: 8 }}>
                    <button className="secondary quick-btn" onClick={() => setQuickPayment(0)}>Exact</button>
                    <button className="secondary quick-btn" onClick={() => setQuickPayment(5)}>+5</button>
                    <button className="secondary quick-btn" onClick={() => setQuickPayment(10)}>+10</button>
                  </div>
                  <div className="stack">
                    {payments.map((p, i) => (
                      <div className="payment-row" key={i}>
                        <select value={p.method} onChange={(e) => updatePaymentRow(i, "method", e.target.value)}>{paymentOptions.map((op) => <option key={op} value={op}>{op}</option>)}</select>
                        <input type="number" min="0" step="0.01" value={p.amount} onChange={(e) => updatePaymentRow(i, "amount", e.target.value)} placeholder="Amount" />
                        <button className="secondary" onClick={() => removePaymentRow(i)}>x</button>
                      </div>
                    ))}
                  </div>
                </div>
                <button style={{ marginTop: 10 }} onClick={doCheckout}>{t(lang, "checkout")}</button>
              </div>

              <div className="card col-7">
                <h3>Cart</h3>
                <table className="table"><thead><tr><th>SKU</th><th>Name</th><th>Qty</th><th>Unit Price</th><th>Total</th></tr></thead><tbody>{cart.items.map((i) => <tr key={`${i.sku}-${i.quantity}`}><td className="mono">{i.sku}</td><td>{i.name}</td><td>{i.quantity} pcs</td><td>{formatKs(i.unit_price)}</td><td>{formatKs(i.line_total)}</td></tr>)}</tbody></table>
                <p className="kpi">{formatKs(cart.total)}</p>
              </div>
            </>
          )}

          {section === "customers" && canCustomers && (
            <>
              <div className="card col-12">
                <div className="space-between">
                  <h3 style={{ margin: 0 }}>Customers</h3>
                  <button onClick={() => setShowCreateCustomerModal(true)}>New Customer</button>
                </div>
                {editingCustomer && (
                  <div className="stack" style={{ marginTop: 16 }}>
                    <h4 style={{ margin: 0 }}>Edit Customer</h4>
                    <input value={editingCustomer.name || ""} onChange={(e) => setEditingCustomer({ ...editingCustomer, name: e.target.value })} placeholder="Name" />
                    <input value={editingCustomer.phone || ""} onChange={(e) => setEditingCustomer({ ...editingCustomer, phone: e.target.value })} placeholder="Phone" />
                    <select value={editingCustomer.township || ""} onChange={(e) => setEditingCustomer({ ...editingCustomer, township: e.target.value })}>
                      <option value="">Township ရွေးပါ</option>
                      {customerTownshipOptions.map((township) => <option key={township} value={township}>{township}</option>)}
                    </select>
                    <input value={editingCustomer.address || ""} onChange={(e) => setEditingCustomer({ ...editingCustomer, address: e.target.value })} placeholder="Address" />
                    <div className="row"><button onClick={doUpdateCustomer}>Update</button><button className="secondary" onClick={() => setEditingCustomer(null)}>Cancel</button></div>
                  </div>
                )}
              </div>
              <div className="card col-12">
                <h3>Customer List</h3>
                <table className="table"><thead><tr><th>ID</th><th>Name</th><th>Phone</th><th>Township</th><th>Sale Team</th><th>Address</th><th>Loyalty</th><th>Action</th></tr></thead><tbody>{customers.map((c) => <tr key={c.id}><td className="mono">{c.id}</td><td>{c.name}</td><td>{c.phone}</td><td>{c.township || "-"}</td><td>{c.team_code || "-"}</td><td title={c.address || "-"}>{shortenAddress(c.address)}</td><td>{c.loyalty_points}</td><td><div className="row"><button className="secondary" onClick={() => setEditingCustomer(c)}>Edit</button><button className="danger" onClick={() => doDeleteCustomer(c.id)}>Delete</button></div></td></tr>)}</tbody></table>
              </div>
              {showCreateCustomerModal && (
                <div className="modal-backdrop" onClick={() => setShowCreateCustomerModal(false)}>
                  <div className="modal-card" onClick={(e) => e.stopPropagation()}>
                    <div className="space-between">
                      <h3 style={{ margin: 0 }}>New Customer</h3>
                      <button className="secondary" onClick={() => setShowCreateCustomerModal(false)}>Close</button>
                    </div>
                    <div className="stack" style={{ marginTop: 16 }}>
                      <input value={customerForm.name} onChange={(e) => setCustomerForm({ ...customerForm, name: e.target.value })} placeholder="Name" />
                      <input value={customerForm.phone} onChange={(e) => setCustomerForm({ ...customerForm, phone: e.target.value })} placeholder="Phone" />
                      <select value={customerForm.township} onChange={(e) => setCustomerForm({ ...customerForm, township: e.target.value })}>
                        <option value="">Township ရွေးပါ</option>
                        {customerTownshipOptions.map((township) => <option key={township} value={township}>{township}</option>)}
                      </select>
                      <input value={customerForm.address} onChange={(e) => setCustomerForm({ ...customerForm, address: e.target.value })} placeholder="Address" />
                      <div className="row">
                        <button onClick={doCreateCustomer}>Create</button>
                        <button className="secondary" onClick={() => setShowCreateCustomerModal(false)}>Cancel</button>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </>
          )}

          {section === "teams" && canTeams && (
            <>
              <div className="card col-12">
                <div className="space-between">
                  <div>
                    <h3>Sales Teams</h3>
                    <p className="subtitle">Team card ကို click လုပ်လိုက်တာနဲ့ modal box တက်လာပြီး township multi-select dropdown, item quantity target, တစ်လစာ sales chart ကိုတန်း manage လုပ်နိုင်ပါတယ်။ Team အသစ်ဖွင့်မယ်ဆို Accounts tab ထဲက New Sales Account ကိုသုံးပါ။</p>
                  </div>
                  <div className="row">
                    <span className="badge">{teams.length} teams</span>
                  </div>
                </div>
                <div className="grid" style={{ marginTop: 16 }}>
                  {teamsWithCustomers.map((team) => (
                    <div className="card col-6 team-card clickable-row" style={{ padding: 12 }} key={`${team.id}-customers`} onClick={() => openEditTeamModal(team)}>
                      <div className="space-between">
                        <div>
                          <strong>{team.name}</strong>
                          <p className="subtitle" style={{ marginTop: 6 }}>#{team.id} / {team.sales_man_name || "-"} / {team.position || "-"}</p>
                        </div>
                        <span className="badge">{team.customers.length} customers</span>
                      </div>
                      <p className="subtitle" style={{ margin: "8px 0 0" }}>Phone: {team.phone || "-"}</p>
                      <div style={{ marginTop: 8 }}>
                        <span className="subtitle">Townships:</span>
                        <div style={{ marginTop: 6 }}>{renderTownshipDropdownTag(team)}</div>
                      </div>
                      <p className="subtitle" style={{ margin: "8px 0 0" }}>
                        Item Targets: {(team.item_targets || []).filter((item) => Number(item.quantity || 0) > 0).map((item) => `${item.name || item.sku} (${item.quantity})`).join(" ၊ ") || "Not set yet"}
                      </p>
                      {renderTeamMonthlySalesChart(team)}
                      <div className="row" style={{ marginTop: 12 }}>
                        <button className="secondary" onClick={(e) => { e.stopPropagation(); openEditTeamModal(team); }}>Manage</button>
                        <button className="danger" onClick={(e) => { e.stopPropagation(); doDeleteTeam(team.id); }}>Delete</button>
                      </div>
                      <div className="stack" style={{ marginTop: 10 }}>
                        {team.customers.length ? team.customers.map((customer) => (
                          <div className="list-row" key={`${team.id}-${customer.id}`}>
                            <span>{customer.name}</span>
                            <span>{customer.phone}</span>
                            <span title={customer.address || customer.township || "-"}>{shortenAddress(customer.address || customer.township || "-")}</span>
                          </div>
                        )) : <p className="subtitle" style={{ margin: 0 }}>No customers assigned yet.</p>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              {teamModalOpen && (
                <div className="modal-backdrop" onClick={closeTeamModal}>
                  <div className="modal-card team-modal-card" onClick={(e) => e.stopPropagation()}>
                    <div className="space-between">
                      <div>
                        <h3 style={{ margin: 0 }}>Manage Team</h3>
                        <p className="subtitle" style={{ marginTop: 6 }}>
                          Team info, townships, item quantity target, monthly sales curve ကိုဒီ box ထဲမှာ manage လုပ်နိုင်ပါတယ်။
                        </p>
                      </div>
                      <button className="secondary" onClick={closeTeamModal}>Close</button>
                    </div>
                    <div className="grid" style={{ marginTop: 12 }}>
                      <div className="col-6"><input value={activeTeamDraft.name} onChange={(e) => (editingTeam ? patchDraft(setEditingTeam, { name: e.target.value }) : patchDraft(setTeamForm, { name: e.target.value }))} placeholder="Team Name" /></div>
                      <div className="col-6"><input value={activeTeamDraft.sales_man_name} onChange={(e) => (editingTeam ? patchDraft(setEditingTeam, { sales_man_name: e.target.value }) : patchDraft(setTeamForm, { sales_man_name: e.target.value }))} placeholder="Sale Man Name" /></div>
                      <div className="col-6"><input value={activeTeamDraft.position} onChange={(e) => (editingTeam ? patchDraft(setEditingTeam, { position: e.target.value }) : patchDraft(setTeamForm, { position: e.target.value }))} placeholder="Position" /></div>
                      <div className="col-6"><input value={activeTeamDraft.phone} onChange={(e) => (editingTeam ? patchDraft(setEditingTeam, { phone: e.target.value }) : patchDraft(setTeamForm, { phone: e.target.value }))} placeholder="Phone Number" /></div>
                      <div className="col-12">{editingTeam ? renderTownshipDropdownManager(editingTeam, setEditingTeam) : renderTownshipDropdownManager(teamForm, setTeamForm)}</div>
                      <div className="col-12">{editingTeam ? renderItemTargetPlanner(editingTeam, setEditingTeam) : renderItemTargetPlanner(teamForm, setTeamForm)}</div>
                      <div className="col-12">{renderTeamMonthlySalesChart(editingTeam || { ...teamForm, code: "DRAFT" })}</div>
                      <div className="col-12 row">
                        <button onClick={editingTeam ? doUpdateTeam : doCreateTeam}>{editingTeam ? "Update Team" : "Save Team"}</button>
                        {editingTeam && <button className="danger" onClick={() => doDeleteTeam(editingTeam.id)}>Delete Team</button>}
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </>
          )}

          {section === "accounts" && canUsers && (
            <>
              <div className="card col-12">
                <div className="space-between">
                  <div>
                    <h3>Sales Accounts</h3>
                    <p className="subtitle">Mobile sales staff account, password, active status, and team assignment ကို admin ကဒီနေရာကနေပဲ manage လုပ်နိုင်ပါတယ်။ Team အသစ်လိုရင် ဒီ form ထဲကနေပဲတစ်ခါတည်းဖွင့်နိုင်ပါတယ်။</p>
                  </div>
                  <div className="row">
                    <span className="badge">{accounts.length} accounts</span>
                    <button onClick={openCreateAccount}>New Sales Account</button>
                  </div>
                </div>
              </div>

              <div className="card col-12">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Username</th>
                      <th>Full Name</th>
                      <th>Role</th>
                      <th>Team</th>
                      <th>Status</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {accounts
                      .filter((account) => account.role === "sales_staff")
                      .map((account) => (
                        <tr key={account.username}>
                          <td className="mono">{account.username}</td>
                          <td>{account.full_name || "-"}</td>
                          <td>{account.role}</td>
                          <td>{account.team_code || "-"}</td>
                          <td>
                            <span className={`pill ${account.active ? "ok" : "warn"}`}>
                              {account.active ? "Active" : "Inactive"}
                            </span>
                          </td>
                          <td>
                            <div className="row">
                              <button className="secondary" onClick={() => openEditAccount(account)}>Edit</button>
                              <button className="danger" onClick={() => doDeleteAccount(account.username)}>Delete</button>
                            </div>
                          </td>
                        </tr>
                      ))}
                  </tbody>
                </table>
                {!accounts.filter((account) => account.role === "sales_staff").length && (
                  <p className="subtitle">No sales accounts yet.</p>
                )}
              </div>

              <div className="card col-12">
                <div className="space-between">
                  <h3>{editingAccount ? "Edit Sales Account" : "Create Sales Account"}</h3>
                  {(editingAccount || accountForm.username || accountForm.full_name || accountForm.team_code || accountForm.use_new_team) && (
                    <button className="secondary" onClick={closeAccountEditor}>Clear</button>
                  )}
                </div>
                <div className="grid" style={{ marginTop: 12 }}>
                  <div className="col-6">
                    <input
                      value={(editingAccount || accountForm).username}
                      readOnly={Boolean(editingAccount)}
                      onChange={(e) => setAccountForm({ ...accountForm, username: e.target.value })}
                      placeholder="Username"
                    />
                  </div>
                  <div className="col-6">
                    <input
                      value={(editingAccount || accountForm).full_name}
                      onChange={(e) => editingAccount
                        ? setEditingAccount({ ...editingAccount, full_name: e.target.value })
                        : setAccountForm({ ...accountForm, full_name: e.target.value })}
                      placeholder="Full Name"
                    />
                  </div>
                  <div className="col-6">
                    <input
                      type="password"
                      value={(editingAccount || accountForm).password}
                      onChange={(e) => editingAccount
                        ? setEditingAccount({ ...editingAccount, password: e.target.value })
                        : setAccountForm({ ...accountForm, password: e.target.value })}
                      placeholder={editingAccount ? "New Password (optional)" : "Password"}
                    />
                  </div>
                  <div className="col-6">
                    {editingAccount ? (
                      <select
                        value={editingAccount.team_code}
                        onChange={(e) => setEditingAccount({ ...editingAccount, team_code: e.target.value })}
                      >
                        <option value="">Select sale team</option>
                        {teams.map((team) => <option key={team.code} value={team.code}>{team.name || team.code}</option>)}
                      </select>
                    ) : (
                      <div className="stack">
                        <label>
                          <input
                            type="checkbox"
                            checked={accountForm.use_new_team}
                            onChange={(e) => setAccountForm((current) => ({
                              ...current,
                              use_new_team: e.target.checked,
                              team_code: e.target.checked ? "" : current.team_code,
                            }))}
                          /> Create new team with this account
                        </label>
                        {!accountForm.use_new_team && (
                          <select
                            value={accountForm.team_code}
                            onChange={(e) => setAccountForm({ ...accountForm, team_code: e.target.value })}
                          >
                            <option value="">Select sale team</option>
                            {teams.map((team) => <option key={team.code} value={team.code}>{team.name || team.code}</option>)}
                          </select>
                        )}
                      </div>
                    )}
                  </div>
                  <div className="col-12">
                    <label>
                      <input
                        type="checkbox"
                        checked={(editingAccount || accountForm).active}
                        onChange={(e) => editingAccount
                          ? setEditingAccount({ ...editingAccount, active: e.target.checked })
                          : setAccountForm({ ...accountForm, active: e.target.checked })}
                      /> Active
                    </label>
                  </div>
                  {!editingAccount && accountForm.use_new_team && (
                    <>
                      <div className="col-12">
                        <div className="space-between">
                          <strong>New Team Information</strong>
                          <span className="badge">
                            {(accountForm.team_draft.item_targets || []).filter((item) => Number(item.quantity || 0) > 0).length} targets
                          </span>
                        </div>
                        <p className="subtitle" style={{ marginTop: 8 }}>
                          Team tab ထဲက create features ကို ဒီနေရာကိုရွှေ့ထားပါတယ်။ Account အသစ်ဖွင့်ရင်း team info, township, item target ကိုတစ်ခါတည်းသတ်မှတ်နိုင်ပါတယ်။
                        </p>
                      </div>
                      <div className="col-6">
                        <input
                          value={accountForm.team_draft.name}
                          onChange={(e) => setAccountForm((current) => ({
                            ...current,
                            team_draft: { ...current.team_draft, name: e.target.value },
                          }))}
                          placeholder="Team Name"
                        />
                      </div>
                      <div className="col-6">
                        <input
                          value={accountForm.team_draft.sales_man_name}
                          onChange={(e) => setAccountForm((current) => ({
                            ...current,
                            team_draft: { ...current.team_draft, sales_man_name: e.target.value },
                          }))}
                          placeholder="Sale Man Name"
                        />
                      </div>
                      <div className="col-6">
                        <input
                          value={accountForm.team_draft.position}
                          onChange={(e) => setAccountForm((current) => ({
                            ...current,
                            team_draft: { ...current.team_draft, position: e.target.value },
                          }))}
                          placeholder="Position"
                        />
                      </div>
                      <div className="col-6">
                        <input
                          value={accountForm.team_draft.phone}
                          onChange={(e) => setAccountForm((current) => ({
                            ...current,
                            team_draft: { ...current.team_draft, phone: e.target.value },
                          }))}
                          placeholder="Phone Number"
                        />
                      </div>
                      <div className="col-12">
                        {renderTownshipDropdownManager(
                          accountForm.team_draft,
                          (updater) => setAccountForm((current) => ({
                            ...current,
                            team_draft: updater(current.team_draft),
                          })),
                        )}
                      </div>
                      <div className="col-12">
                        {renderItemTargetPlanner(
                          accountForm.team_draft,
                          (updater) => setAccountForm((current) => ({
                            ...current,
                            team_draft: updater(current.team_draft),
                          })),
                        )}
                      </div>
                    </>
                  )}
                  <div className="col-12 row">
                    <button onClick={editingAccount ? doUpdateAccount : doCreateAccount}>
                      {editingAccount ? "Update Account" : "Create Account"}
                    </button>
                    {editingAccount && (
                      <button className="danger" onClick={() => doDeleteAccount(editingAccount.username)}>
                        Delete Account
                      </button>
                    )}
                  </div>
                </div>
              </div>
            </>
          )}

          {section === "shifts" && (
            <>
              <div className="card col-4">
                <h3>Shift Tracking</h3>
                <div className="row"><button onClick={doShiftStart}>Start Shift</button><button className="secondary" onClick={doShiftEnd}>End Shift</button></div>
                <p className="subtitle" style={{ marginTop: 10 }}>Daily sales by employee is available in Reports.</p>
              </div>
              <div className="card col-8">
                <h3>Shift Logs</h3>
                <table className="table"><thead><tr><th>ID</th><th>User</th><th>Start</th><th>End</th><th>Txns</th><th>Revenue</th></tr></thead><tbody>{shifts.map((s) => <tr key={s.id}><td>{s.id}</td><td>{s.username}</td><td>{s.start}</td><td>{s.end || "OPEN"}</td><td>{s.transactions}</td><td>{formatKs(s.revenue)}</td></tr>)}</tbody></table>
              </div>
            </>
          )}

          {section === "reports" && (
            <>
              <div className="card col-12">
                <div className="row">
                  <div>
                    <label>Sales Period</label>
                    <select value={salesPeriod} onChange={(e) => setSalesPeriod(e.target.value)}><option value="daily">daily</option><option value="weekly">weekly</option><option value="monthly">monthly</option></select>
                  </div>
                  {canPnl && (
                    <div>
                      <label>P&L Period</label>
                      <select value={pnlPeriod} onChange={(e) => setPnlPeriod(e.target.value)}><option value="daily">daily</option><option value="weekly">weekly</option><option value="monthly">monthly</option></select>
                    </div>
                  )}
                  <button onClick={() => loadReports().catch((e) => setErr(e.message))}>Load Reports</button>
                </div>
              </div>

              {salesReport && <div className="card col-4"><h3>Sales Report</h3><p>Transactions: {salesReport.transactions}</p><p>Revenue: {formatKs(salesReport.total_sales)}</p><p>Profit: {formatKs(salesReport.total_profit)}</p></div>}
              {employeeSalesReport && <div className="card col-4"><h3>Employee Daily Sales</h3>{Object.entries(employeeSalesReport.employees || {}).map(([u,v]) => <div className="list-row" key={u}><span>{u}</span><span>{v.transactions} txns</span><span>{formatKs(v.revenue)}</span></div>)}</div>}
              {inventoryReport && <div className="card col-4"><h3>Inventory Report</h3><p>Total Products: {inventoryReport.total_products}</p><p>Stock Units: {inventoryReport.total_stock_units} pcs</p><p>Cost Value: {formatKs(inventoryReport.inventory_cost_value)}</p><p>Sale Value: {formatKs(inventoryReport.inventory_sale_value)}</p></div>}
              {pnlReport && <div className="card col-12"><h3>Profit & Loss</h3><p>Revenue: {formatKs(pnlReport.revenue)}</p><p>Cost: {formatKs(pnlReport.cost)}</p><p>Gross Profit: {formatKs(pnlReport.gross_profit)}</p></div>}
            </>
          )}

          {section === "audit" && canAudit && (
            <>
              <div className="card col-12">
                <div className="space-between">
                  <div>
                    <h3>Audit Trail</h3>
                    <p className="subtitle">Recent admin-visible transaction and security events</p>
                  </div>
                  <button className="secondary" onClick={() => loadAuditLogs().catch((e) => setErr(e.message))}>Reload Logs</button>
                </div>
              </div>
              <div className="card col-12">
                <table className="table">
                  <thead>
                    <tr>
                      <th>Time</th>
                      <th>User</th>
                      <th>Action</th>
                      <th>Target</th>
                      <th>Device</th>
                      <th>Details Hash</th>
                    </tr>
                  </thead>
                  <tbody>
                    {auditLogs.map((log, idx) => (
                      <tr key={`${log.timestamp}-${log.target}-${idx}`}>
                        <td>{log.timestamp}</td>
                        <td>{log.username}</td>
                        <td><span className="pill info">{log.action}</span></td>
                        <td className="mono">{log.target}</td>
                        <td className="mono">{log.device_id || "-"}</td>
                        <td className="mono hash-cell">{log.details_hash}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {!auditLogs.length && <p className="subtitle">No audit events recorded yet.</p>}
              </div>
            </>
          )}

          {section === "stock" && canStock && (
            <>
              <div className="card col-4">
                <div className="space-between">
                  <h3>{editingProduct ? "Edit Item" : "Add Item"}</h3>
                  <button
                    type="button"
                    className="secondary"
                    aria-pressed={showThreshold}
                    onClick={() => setShowThreshold((current) => !current)}
                  >
                    {showThreshold ? "Hide Threshold" : "Show Threshold"}
                  </button>
                </div>
                {editingProduct ? (
                  <>
                    <input value={editingProduct.sku} readOnly />
                    <div style={{ height: 8 }} />
                    <input value={editingProduct.name} onChange={(e) => setEditingProduct({ ...editingProduct, name: e.target.value })} placeholder="Name" />
                    <div style={{ height: 8 }} />
                    <div className="row"><input type="number" step="0.01" value={editingProduct.price} onChange={(e) => setEditingProduct({ ...editingProduct, price: e.target.value })} placeholder="Sale Price" /><input type="number" step="0.01" value={editingProduct.cost_price} onChange={(e) => setEditingProduct({ ...editingProduct, cost_price: e.target.value })} placeholder="Cost" /></div>
                    <div style={{ height: 8 }} />
                    <div className="row">
                      {showThreshold && <input type="number" value={editingProduct.low_stock_threshold} onChange={(e) => setEditingProduct({ ...editingProduct, low_stock_threshold: e.target.value })} placeholder="Threshold" />}
                      <input value={editingProduct.unit} onChange={(e) => setEditingProduct({ ...editingProduct, unit: e.target.value })} placeholder="Unit" />
                    </div>
                    <div style={{ height: 8 }} />
                    <input value={editingProduct.category} onChange={(e) => setEditingProduct({ ...editingProduct, category: e.target.value })} placeholder="Category" />
                    <div style={{ marginTop: 8 }} className="row"><button onClick={doUpdateProduct}>Update Item</button><button className="secondary" onClick={() => setEditingProduct(null)}>Cancel</button></div>
                  </>
                ) : (
                  <>
                    <input value={newProduct.sku} onChange={(e) => setNewProduct({ ...newProduct, sku: e.target.value.toUpperCase() })} placeholder="Item ID" />
                    <div style={{ height: 8 }} />
                    <input value={newProduct.name} onChange={(e) => setNewProduct({ ...newProduct, name: e.target.value })} placeholder="Name" />
                    <div style={{ height: 8 }} />
                    <div className="row"><input type="number" step="0.01" value={newProduct.price} onChange={(e) => setNewProduct({ ...newProduct, price: e.target.value })} placeholder="Sale Price" /><input type="number" step="0.01" value={newProduct.cost_price} onChange={(e) => setNewProduct({ ...newProduct, cost_price: e.target.value })} placeholder="Cost" /></div>
                    <div style={{ height: 8 }} />
                    <div className="row">
                      {showThreshold && <input type="number" value={newProduct.low_stock_threshold} onChange={(e) => setNewProduct({ ...newProduct, low_stock_threshold: e.target.value })} placeholder="Threshold" />}
                      <input value={newProduct.unit} onChange={(e) => setNewProduct({ ...newProduct, unit: e.target.value })} placeholder="Unit" />
                    </div>
                    <div style={{ height: 8 }} />
                    <input value={newProduct.category} onChange={(e) => setNewProduct({ ...newProduct, category: e.target.value })} placeholder="Category" />
                    <div style={{ marginTop: 8 }}><button onClick={doAddProduct}>Add Item</button></div>
                  </>
                )}

                <h3 style={{ marginTop: 14 }}>Update Stock</h3>
                <div className="row"><input value={stockPatch.sku} onChange={(e) => setStockPatch({ ...stockPatch, sku: e.target.value.toUpperCase() })} placeholder="Item ID" /><input type="number" value={stockPatch.delta} onChange={(e) => setStockPatch({ ...stockPatch, delta: e.target.value })} placeholder="Delta" /></div>
                <div style={{ marginTop: 8 }}><button className="secondary" onClick={doUpdateStock}>Apply</button></div>
              </div>
              <div className="card col-8">
                <div className="space-between">
                  <h3>Stock Tracking</h3>
                  <span className="subtitle">Auto refresh every 5 seconds</span>
                </div>
                <table className="table"><thead><tr><th>Item ID</th><th>Name</th><th>Quantity</th>{showThreshold && <th>Threshold</th>}<th>Unit</th><th>Status</th><th>Action</th></tr></thead><tbody>{products.map((p) => <tr key={p.sku}><td className="mono">{p.sku}</td><td>{p.name}</td><td>{p.stock}</td>{showThreshold && <td>{p.low_stock_threshold ?? "-"}</td>}<td>{p.unit || "pcs"}</td><td><span className={`pill ${p.low_stock ? "warn" : "ok"}`}>{p.low_stock ? "LOW" : "OK"}</span></td><td><div className="row"><button className="secondary" onClick={() => setEditingProduct({ ...p })}>Edit</button><button className="danger" onClick={() => doDeleteProduct(p.sku)}>Delete</button></div></td></tr>)}</tbody></table>
              </div>
            </>
          )}

          {section === "receipts" && (
            <div className="card col-12">
              <h3>Receipts</h3>
              <table className="table"><thead><tr><th>Invoice</th><th>Time</th><th>Cashier</th><th>Revenue</th><th>Cost</th><th>Profit</th><th>Print</th></tr></thead><tbody>{receipts.map((r) => <tr key={r.invoice_id + r.timestamp}><td className="mono">{r.invoice_id}</td><td>{r.timestamp}</td><td>{r.cashier}</td><td>{formatKs(r.invoice_total || r.grand_total)}</td><td>{formatKs(r.total_cost || 0)}</td><td>{formatKs(r.gross_profit || 0)}</td><td><div className="row"><button className="secondary quick-btn" onClick={() => printReceipt(r, "thermal")}>{t(lang, "print_thermal")}</button><button className="secondary quick-btn" onClick={() => printReceipt(r, "a4")}>{t(lang, "print_a4")}</button></div></td></tr>)}</tbody></table>
            </div>
          )}

          <div className="card col-12">
            {msg && <div className="success">{msg}</div>}
            {err && <div className="error">{err}</div>}
          </div>
        </div>
      </main>
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
