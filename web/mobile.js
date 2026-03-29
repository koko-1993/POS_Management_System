const { useEffect, useMemo, useState } = React;

const MOBILE_DEVICE_KEY = "sht_mobile_device_id";
const MOBILE_TOKEN_KEY = "sht_mobile_token";
const MOBILE_USER_KEY = "sht_mobile_user";
const MOBILE_AUTH_EXPIRED_EVENT = "sht-mobile-auth-expired";

function buildDefaultDeviceId() {
  const part = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `MOBILE-${part}`;
}

function getMobileDeviceId() {
  const existing = localStorage.getItem(MOBILE_DEVICE_KEY);
  if (existing) return existing;
  const next = buildDefaultDeviceId();
  localStorage.setItem(MOBILE_DEVICE_KEY, next);
  return next;
}

function isMobileAuthError(message = "") {
  const normalized = String(message || "").toLowerCase();
  return normalized.includes("invalid token")
    || normalized.includes("missing bearer token")
    || normalized.includes("device mismatch");
}

function expireMobileSession(message = "Session expired. Please log in again.") {
  localStorage.removeItem(MOBILE_TOKEN_KEY);
  localStorage.removeItem(MOBILE_USER_KEY);
  window.dispatchEvent(new CustomEvent(MOBILE_AUTH_EXPIRED_EVENT, { detail: { message } }));
}

async function mobileApi(path, method = "GET", token = "", body, deviceId = getMobileDeviceId(), extraHeaders = {}) {
  const response = await fetch(path, {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Device-ID": deviceId,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...extraHeaders,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json();
  if (!response.ok) {
    const message = data.error || "Request failed";
    if (response.status === 401 && token && isMobileAuthError(message)) {
      expireMobileSession();
      throw new Error("Session expired. Please log in again.");
    }
    throw new Error(message);
  }
  return data;
}

function LoginScreen({ onLogin }) {
  const [username, setUsername] = useState("salestaff");
  const [password, setPassword] = useState("sales123");
  const [otpCode, setOtpCode] = useState("");
  const [deviceId, setDeviceId] = useState(getMobileDeviceId());
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const submit = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError("");
    try {
      localStorage.setItem(MOBILE_DEVICE_KEY, deviceId);
      const result = await mobileApi(
        "/api/login",
        "POST",
        "",
        { username, password, otp_code: otpCode },
        deviceId
      );
      onLogin(result, deviceId);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="mobile-shell">
      <div className="hero">
        <div className="hero-top">
          <div>
            <p className="muted">Field Sales Mobile</p>
            <h1>Shwe Htoo Thit</h1>
          </div>
          <span className="badge">Phone</span>
        </div>
        <p className="muted" style={{ marginTop: 10 }}>
          Sales staff can log in from an authorized phone and create orders on the road.
        </p>
      </div>

      <form className="section-card stack" onSubmit={submit}>
        <div>
          <h2>Login</h2>
          <p className="muted small" style={{ marginTop: 4 }}>
            Ask admin to authorize this phone device ID before first login.
          </p>
        </div>
        <input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="Username" />
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Password" />
        <input value={otpCode} onChange={(e) => setOtpCode(e.target.value)} placeholder="OTP if required" />
        <input value={deviceId} onChange={(e) => setDeviceId(e.target.value.toUpperCase())} placeholder="Mobile device ID" />
        <button type="submit">{loading ? "Signing in..." : "Login from Phone"}</button>
        {error && <div className="message error">{error}</div>}
      </form>
    </div>
  );
}

function MobileApp() {
  const [token, setToken] = useState(localStorage.getItem(MOBILE_TOKEN_KEY) || "");
  const [user, setUser] = useState(() => {
    const raw = localStorage.getItem(MOBILE_USER_KEY);
    return raw ? JSON.parse(raw) : null;
  });
  const [deviceId, setDeviceId] = useState(getMobileDeviceId());
  const [products, setProducts] = useState([]);
  const [cart, setCart] = useState({ items: [], total: 0 });
  const [customers, setCustomers] = useState([]);
  const [receipts, setReceipts] = useState([]);
  const [payments, setPayments] = useState([{ method: "cash", amount: "" }]);
  const [paymentOptions, setPaymentOptions] = useState([]);
  const [sku, setSku] = useState("F100");
  const [qty, setQty] = useState(1);
  const [discount, setDiscount] = useState(0);
  const [promoCode, setPromoCode] = useState("");
  const [customerForm, setCustomerForm] = useState({ name: "", phone: "", email: "", vehicle_no: "" });
  const [selectedCustomerId, setSelectedCustomerId] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const canSell = ["sales_staff", "cashier", "admin"].includes(user?.role || "");

  const quickOptions = useMemo(() => products.slice(0, 6), [products]);

  const clearFeedback = () => {
    setMessage("");
    setError("");
  };

  const loadAll = async () => {
    const [productData, cartData, customerData, receiptData, paymentData] = await Promise.all([
      mobileApi("/api/products", "GET", token, undefined, deviceId),
      mobileApi("/api/cart", "GET", token, undefined, deviceId),
      mobileApi("/api/customers", "GET", token, undefined, deviceId),
      mobileApi("/api/receipts?limit=8", "GET", token, undefined, deviceId),
      mobileApi("/api/payment-options", "GET", token, undefined, deviceId),
    ]);
    setProducts(productData.products);
    setCart(cartData);
    setCustomers(customerData.customers);
    setReceipts(receiptData.receipts);
    setPaymentOptions(paymentData.payment_options);
    setPayments((existing) =>
      existing.map((row) => ({
        ...row,
        method: paymentData.payment_options.includes(row.method) ? row.method : paymentData.payment_options[0],
      }))
    );
  };

  useEffect(() => {
    if (!token) return;
    loadAll().catch((err) => setError(err.message));
  }, [token]);

  const addPaymentRow = () => {
    setPayments((current) => [...current, { method: paymentOptions[0] || "cash", amount: "" }]);
  };

  const updatePaymentRow = (index, key, value) => {
    setPayments((current) => current.map((row, i) => (i === index ? { ...row, [key]: value } : row)));
  };

  const removePaymentRow = (index) => {
    setPayments((current) => (current.length === 1 ? current : current.filter((_, i) => i !== index)));
  };

  const addToCart = async (selectedSku = sku, selectedQty = qty) => {
    clearFeedback();
    try {
      await mobileApi("/api/cart/add", "POST", token, { sku: selectedSku, qty: Number(selectedQty) }, deviceId);
      await loadAll();
      setMessage(`Added ${selectedSku} x${selectedQty}`);
    } catch (err) {
      setError(err.message);
    }
  };

  const createCustomer = async () => {
    clearFeedback();
    try {
      const result = await mobileApi("/api/customers", "POST", token, customerForm, deviceId);
      setCustomerForm({ name: "", phone: "", email: "", vehicle_no: "" });
      setSelectedCustomerId(String(result.customer.id));
      await loadAll();
      setMessage(`Customer ${result.customer.name} saved`);
    } catch (err) {
      setError(err.message);
    }
  };

  const doCheckout = async () => {
    clearFeedback();
    try {
      const paymentPayload = payments
        .map((item) => ({ method: item.method, amount: Number(item.amount) }))
        .filter((item) => item.amount > 0);
      if (!paymentPayload.length) {
        throw new Error("Enter at least one payment");
      }

      const idempotencyKey = `mobile-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      const result = await mobileApi(
        "/api/checkout",
        "POST",
        token,
        {
          discount_pct: Number(discount || 0),
          promo_code: promoCode,
          payments: paymentPayload,
          customer_id: selectedCustomerId ? Number(selectedCustomerId) : null,
        },
        deviceId,
        { "Idempotency-Key": idempotencyKey }
      );
      setDiscount(0);
      setPromoCode("");
      setSelectedCustomerId("");
      setPayments([{ method: paymentOptions[0] || "cash", amount: "" }]);
      await loadAll();
      setMessage(`Invoice ${result.receipt.invoice_id} created`);
    } catch (err) {
      setError(err.message);
    }
  };

  const logout = () => {
    localStorage.removeItem(MOBILE_TOKEN_KEY);
    localStorage.removeItem(MOBILE_USER_KEY);
    setToken("");
    setUser(null);
    setMessage("");
    setError("");
  };

  useEffect(() => {
    const handleAuthExpired = (event) => {
      setToken("");
      setUser(null);
      setMessage("");
      setError(event.detail?.message || "Session expired. Please log in again.");
    };
    window.addEventListener(MOBILE_AUTH_EXPIRED_EVENT, handleAuthExpired);
    return () => window.removeEventListener(MOBILE_AUTH_EXPIRED_EVENT, handleAuthExpired);
  }, []);

  if (!token || !user) {
    return (
      <LoginScreen
        onLogin={(result, nextDeviceId) => {
          localStorage.setItem(MOBILE_TOKEN_KEY, result.token);
          localStorage.setItem(MOBILE_USER_KEY, JSON.stringify(result.user));
          setToken(result.token);
          setUser(result.user);
          setDeviceId(nextDeviceId);
          setError("");
        }}
      />
    );
  }

  if (!canSell) {
    return (
      <div className="mobile-shell">
        <div className="section-card stack">
          <h2>Role not supported on mobile sales</h2>
          <p className="muted">This mobile view is intended for sales staff and selling roles.</p>
          <button className="secondary" onClick={logout}>Logout</button>
        </div>
      </div>
    );
  }

  return (
    <div className="mobile-shell">
      <div className="hero">
        <div className="hero-top">
          <div>
            <p className="muted">Logged in as {user.username}</p>
            <h1>Mobile Selling</h1>
          </div>
          <span className="badge">{user.role}</span>
        </div>
        <p className="muted" style={{ marginTop: 10 }}>
          Device ID: <span className="mono">{deviceId}</span>
        </p>
        <div className="actions" style={{ marginTop: 12 }}>
          <button className="secondary" onClick={() => loadAll().catch((err) => setError(err.message))}>Refresh</button>
          <button className="secondary" onClick={logout}>Logout</button>
        </div>
      </div>

      <div className="section-card">
        <div className="summary-grid">
          <div>
            <p className="muted small">Products</p>
            <div className="kpi">{products.length}</div>
          </div>
          <div>
            <p className="muted small">Cart Total</p>
            <div className="kpi">${Number(cart.total || 0).toFixed(2)}</div>
          </div>
        </div>
      </div>

      <div className="section-card stack">
        <div>
          <h2>Quick Sale</h2>
          <p className="muted small" style={{ marginTop: 4 }}>
            Tap a product below or enter a SKU manually.
          </p>
        </div>
        <div className="product-list">
          {quickOptions.map((product) => (
            <button key={product.sku} className="secondary" onClick={() => {
              setSku(product.sku);
              addToCart(product.sku, 1);
            }}>
              <div className="row-between">
                <strong>{product.name}</strong>
                <span className="mono">{product.sku}</span>
              </div>
              <div className="row-between small muted" style={{ marginTop: 6 }}>
                <span>${Number(product.price).toFixed(2)}</span>
                <span>Stock {product.stock}</span>
              </div>
            </button>
          ))}
        </div>
        <div className="grid-two">
          <input value={sku} onChange={(e) => setSku(e.target.value.toUpperCase())} placeholder="SKU" />
          <input type="number" min="1" value={qty} onChange={(e) => setQty(e.target.value)} placeholder="Qty" />
        </div>
        <button onClick={() => addToCart()}>Add To Cart</button>
      </div>

      <div className="section-card stack">
        <h2>Customer</h2>
        <select value={selectedCustomerId} onChange={(e) => setSelectedCustomerId(e.target.value)}>
          <option value="">Walk-in customer</option>
          {customers.map((customer) => (
            <option key={customer.id} value={customer.id}>
              {customer.name} ({customer.phone})
            </option>
          ))}
        </select>
        <div className="grid-two">
          <input value={customerForm.name} onChange={(e) => setCustomerForm({ ...customerForm, name: e.target.value })} placeholder="New customer name" />
          <input value={customerForm.phone} onChange={(e) => setCustomerForm({ ...customerForm, phone: e.target.value })} placeholder="Phone" />
        </div>
        <div className="grid-two">
          <input value={customerForm.email} onChange={(e) => setCustomerForm({ ...customerForm, email: e.target.value })} placeholder="Email" />
          <input value={customerForm.vehicle_no} onChange={(e) => setCustomerForm({ ...customerForm, vehicle_no: e.target.value })} placeholder="Vehicle No" />
        </div>
        <button className="secondary" onClick={createCustomer}>Save Customer</button>
      </div>

      <div className="section-card stack">
        <div className="row-between">
          <h2>Cart</h2>
          <span className="pill">{cart.items.length} items</span>
        </div>
        <div className="cart-list">
          {cart.items.map((item) => (
            <div className="list-item" key={`${item.sku}-${item.quantity}`}>
              <div className="list-top">
                <strong>{item.name}</strong>
                <span className="mono">{item.sku}</span>
              </div>
              <div className="row-between small muted" style={{ marginTop: 6 }}>
                <span>Qty {item.quantity}</span>
                <span>${Number(item.line_total).toFixed(2)}</span>
              </div>
            </div>
          ))}
          {!cart.items.length && <div className="empty">Cart is empty</div>}
        </div>
        <div className="grid-two">
          <input type="number" min="0" max="100" value={discount} onChange={(e) => setDiscount(e.target.value)} placeholder="Discount %" />
          <input value={promoCode} onChange={(e) => setPromoCode(e.target.value.toUpperCase())} placeholder="Promo code" />
        </div>
        <div className="stack">
          {payments.map((payment, index) => (
            <div className="grid-two" key={index}>
              <select value={payment.method} onChange={(e) => updatePaymentRow(index, "method", e.target.value)}>
                {paymentOptions.map((option) => (
                  <option key={option} value={option}>{option}</option>
                ))}
              </select>
              <input type="number" min="0" step="0.01" value={payment.amount} onChange={(e) => updatePaymentRow(index, "amount", e.target.value)} placeholder="Amount" />
            </div>
          ))}
        </div>
        <div className="actions">
          <button className="secondary" onClick={addPaymentRow}>Add Payment</button>
          <button className="secondary" onClick={() => removePaymentRow(payments.length - 1)}>Remove Payment</button>
        </div>
        <button className="warn" onClick={doCheckout}>Checkout Now</button>
      </div>

      <div className="section-card stack">
        <div className="row-between">
          <h2>Recent Invoices</h2>
          <span className="pill">Latest 8</span>
        </div>
        <div className="receipt-list">
          {receipts.map((receipt) => (
            <div className="list-item" key={`${receipt.invoice_id}-${receipt.timestamp}`}>
              <div className="list-top">
                <strong>Invoice {receipt.invoice_id}</strong>
                <span className="mono small">{receipt.timestamp}</span>
              </div>
              <div className="row-between small muted" style={{ marginTop: 6 }}>
                <span>{receipt.cashier}</span>
                <span>${Number(receipt.invoice_total || receipt.grand_total || 0).toFixed(2)}</span>
              </div>
            </div>
          ))}
          {!receipts.length && <div className="empty">No invoices yet</div>}
        </div>
      </div>

      {message && <div className="message success">{message}</div>}
      {error && <div className="message error">{error}</div>}
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<MobileApp />);
