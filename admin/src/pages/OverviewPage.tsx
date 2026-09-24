import { useState } from "react";
import { BarChart, PageState, Stat, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { money } from "../lib/format";

type Range = "7" | "30" | "90" | "365";

export default function OverviewPage() {
  const api = useApi();
  const [range, setRange] = useState<Range>("30");
  const { data: stats, loading, error } = useLoad(() => api.stats(Number(range)), [range]);

  return (
    <>
      <header className="page-header">
        <h1>Overview</h1>
        <Tabs<Range>
          value={range}
          onChange={setRange}
          tabs={[{ id: "7", title: "7 days" }, { id: "30", title: "30 days" }, { id: "90", title: "90 days" }, { id: "365", title: "1 year" }]}
        />
      </header>
      <PageState loading={loading && !stats} error={error}>
        {stats && (
          <>
            <section className="grid stats">
              <Stat title="Artists" value={stats.artists} />
              <Stat title="Studios live" value={stats.studios_live} hint={`${stats.studio_owners} studio accounts`} />
              <Stat title="Pending applications" value={stats.studios_pending} />
              <Stat title="Bookings" value={stats.bookings_total} hint={`${stats.bookings_confirmed} confirmed · ${stats.bookings_cancelled} cancelled`} />
              <Stat title="Booking rate" value={`${stats.booking_rate}%`} hint="Started bookings that were paid & confirmed" />
              <Stat title="Open reports" value={stats.open_reports} hint={`${stats.open_disputes} open disputes`} />
              <Stat title="Failed payments" value={stats.failed_payments} />
            </section>

            <section className="grid two">
              <div className="card">
                <h3>Revenue</h3>
                {Object.keys(stats.revenue).length === 0 && <p className="muted">No payments in this period.</p>}
                <table>
                  <thead><tr><th>Currency</th><th>Sales</th><th>Card</th><th>Cash</th><th>Platform (10%)</th><th>Refunds</th><th>Fees owed</th></tr></thead>
                  <tbody>
                    {Object.entries(stats.revenue).map(([currency, r]) => (
                      <tr key={currency}>
                        <td>{currency}</td>
                        <td>{money(r.gross, currency)}</td>
                        <td>{money(r.card, currency)}</td>
                        <td>{money(r.cash, currency)}</td>
                        <td className="strong">{money(r.platform, currency)}</td>
                        <td>{money(r.refunds, currency)}</td>
                        <td>{money(r.fees_owed, currency)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="muted small">Sales = completed sessions in the period. EasySesh earns 10% of every sale; for cash sales the studio owes the fee ("Fees owed" is the current outstanding total).</p>
              </div>
              <div className="card">
                <h3>Bookings per day</h3>
                <BarChart data={stats.bookings_per_day.map((d) => ({ label: d.day, value: d.bookings }))} />
              </div>
            </section>

            <section className="grid two">
              <div className="card">
                <h3>Most popular studios</h3>
                <table>
                  <thead><tr><th>Studio</th><th>City</th><th>Bookings</th><th>Rating</th></tr></thead>
                  <tbody>
                    {stats.top_studios.map((s) => (
                      <tr key={s.id}><td>{s.name}</td><td>{s.city}</td><td>{s.bookings}</td><td>★ {s.rating.toFixed(1)}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="card">
                <h3>Most popular areas</h3>
                <table>
                  <thead><tr><th>Area</th><th>City</th><th>Bookings</th></tr></thead>
                  <tbody>
                    {stats.top_areas.map((a) => (
                      <tr key={`${a.city}-${a.area}`}><td>{a.area ?? "–"}</td><td>{a.city}</td><td>{a.bookings}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
      </PageState>
    </>
  );
}
