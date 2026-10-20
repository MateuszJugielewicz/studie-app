import { ActionButton, Badge, PageState, ViewAsButton } from "../components";
import { rankAtLeast, useApi, useLoad, useStaff } from "../lib/apiContext";
import { date } from "../lib/format";

/** Recent stories (24-hour photos posted by artists and studios). Reports about them arrive in Moderation;
 *  admins can take a story down here. Captions and replies also go through the auto-flags. */
export default function StoriesPage() {
  const api = useApi();
  const me = useStaff();
  const { data, loading, error, reload } = useLoad(() => api.stories());
  const rows = data ?? [];
  const live = (s: (typeof rows)[number]) => !s.removed_at && new Date(s.expires_at) > new Date();
  return (
    <>
      <header className="page-header"><h1>Stories</h1></header>
      <p className="muted">Photos artists and studios share for 24 hours. People can like them and reply; replies go only to the poster. Taking a story down hides it for everyone right away.</p>
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th></th><th>Poster</th><th>Caption</th><th>Views · likes · replies</th><th>Posted</th><th>Status</th><th></th></tr></thead>
            <tbody>
              {rows.map((s) => (
                <tr key={s.id}>
                  <td><a href={s.media_url} target="_blank" rel="noreferrer noopener"><img src={s.media_url} alt="" width={44} height={70} style={{ objectFit: "cover", borderRadius: 8 }} /></a></td>
                  <td className="strong">{s.poster_name ?? "–"}<div className="muted small">{s.poster_email}{s.studio_id ? " · studio" : ""}</div></td>
                  <td>{s.caption || <span className="muted">–</span>}</td>
                  <td>{s.view_count} · {s.like_count} · {s.reply_count}</td>
                  <td>{date(s.created_at, true)}</td>
                  <td>{s.removed_at ? <Badge value="cancelled" text="Taken down" /> : live(s) ? <Badge value="active" text="Live" /> : <Badge value="expired" text="Expired" />}</td>
                  <td className="actions">
                    <ViewAsButton userId={s.user_id} title="View as poster" />
                    {live(s) && rankAtLeast(me.rank, "admin") && (
                      <ActionButton kind="danger" confirm="Take this story down? The poster gets a notification." onClick={async () => { await api.removeStory(s.id); await reload(); }}>Take down</ActionButton>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
    </>
  );
}
