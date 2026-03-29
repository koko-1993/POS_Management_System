const { useEffect, useState } = React;

const OFFICE_TOKEN_KEY = "sht_office_token";

function formatKs(amount) {
  return `Ks ${Number(amount || 0).toFixed(0)}`;
}

function mapLink(location) {
  if (!location) return "";
  return `https://www.google.com/maps?q=${location.latitude},${location.longitude}`;
}

function OfficeApp() {
  const [token, setToken] = useState(localStorage.getItem(OFFICE_TOKEN_KEY) || "");
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("admin123");
  const [staff, setStaff] = useState([]);
  const [receipts, setReceipts] = useState([]);
  const [error, setError] = useState("");

  const applyToken = (nextToken) => {
    setToken(nextToken || "");
    if (nextToken) {
      localStorage.setItem(OFFICE_TOKEN_KEY, nextToken);
    } else {
      localStorage.removeItem(OFFICE_TOKEN_KEY);
    }
  };

  const login = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Device-ID": "OFFICE-DASHBOARD-01",
        },
        body: JSON.stringify({ username, password, otp_code: "" }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Login failed");
      applyToken(data.token);
    } catch (err) {
      setError(err.message);
    }
  };

  const load = async () => {
    const res = await fetch("/api/field-force", {
      headers: {
        Authorization: `Bearer ${token}`,
        "X-Device-ID": "OFFICE-DASHBOARD-01",
      },
    });
    const data = await res.json();
    if (!res.ok) {
      if ((data.error || "").toLowerCase().includes("token")) {
        applyToken("");
      }
      throw new Error(data.error || "Load failed");
    }
    setStaff(data.staff || []);
    setReceipts(data.receipts || []);
  };

  useEffect(() => {
    if (!token) return;
    load().catch((err) => setError(err.message));
    const timer = setInterval(() => {
      load().catch((err) => setError(err.message));
    }, 15000);
    return () => clearInterval(timer);
  }, [token]);

  if (!token) {
    return (
      <div className="app">
        <div className="card" style={{ maxWidth: 460, margin: "10vh auto" }}>
          <h1 className="title">Office Dashboard</h1>
          <form onSubmit={login}>
            <label>Username</label>
            <input value={username} onChange={(e) => setUsername(e.target.value)} />
            <label style={{ marginTop: 12, display: "block" }}>Password</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
            <button type="submit" style={{ marginTop: 16 }}>Open Dashboard</button>
          </form>
          {error && <p className="error">{error}</p>}
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <div className="hero-panel">
        <div>
          <p className="eyebrow">Office Control</p>
          <h1 className="title">Field Force Live Dashboard</h1>
          <p className="subtitle">Sales staff location and today sales overview</p>
        </div>
        <div className="row">
          <div className="card" style={{ padding: 14 }}>
            <p className="subtitle">Live Teams</p>
            <p className="kpi">{staff.length}</p>
          </div>
          <div className="card" style={{ padding: 14 }}>
            <p className="subtitle">Today Revenue</p>
            <p className="kpi">{formatKs(staff.reduce((sum, member) => sum + Number(member.today_sales || 0), 0))}</p>
          </div>
        </div>
      </div>
      <div className="grid two-col" style={{ marginTop: 20 }}>
        <div className="card">
          <h2>Sales Staff Location</h2>
          {staff.map((member) => (
            <div key={member.username} className="card" style={{ padding: 14, marginTop: 12 }}>
              <div className="space-between">
                <strong>{member.username}</strong>
                <span className="badge">{formatKs(member.today_sales)}</span>
              </div>
              <div className="subtitle" style={{ marginTop: 8 }}>Transactions: {member.transactions}</div>
              <div className="subtitle">Last invoice: {member.last_invoice_id || "-"}</div>
              <div className="subtitle">Seen: {member.last_seen_at || "-"}</div>
              <div className="subtitle">
                GPS: {member.location ? `${member.location.latitude.toFixed(5)}, ${member.location.longitude.toFixed(5)}` : "No GPS yet"}
              </div>
              {member.location && (
                <div className="row" style={{ marginTop: 10 }}>
                  <a className="badge" href={mapLink(member.location)} target="_blank" rel="noreferrer">Open in Maps</a>
                </div>
              )}
            </div>
          ))}
        </div>
        <div className="card">
          <h2>Recent Sales</h2>
          {receipts.map((receipt) => (
            <div key={receipt.invoice_id} className="list-row">
              <div>
                <strong>Invoice {receipt.invoice_id}</strong>
                <div className="subtitle">{receipt.cashier}</div>
              </div>
              <div className="subtitle">
                {formatKs(receipt.invoice_total || receipt.grand_total)}
                <br />
                {receipt.timestamp}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<OfficeApp />);
