import { useParams } from "react-router-dom";
import { api } from "../lib/api";
import { useApp, useLoad } from "../lib/state";
import { Loading, PageHead } from "../components/ui";
import { ReviewRow, ReviewSummary } from "../components/social";

/** All reviews of a studio. The studio's owner can reply and dispute ratings here. */
export default function Reviews() {
  const { id = "" } = useParams();
  const app = useApp();
  const { data } = useLoad(async () => ({ studio: await api.studio(id), reviews: await api.reviews(id) }), [id]);
  if (!data) return <Loading />;
  const canReply = app.account?.id === data.studio.owner_id;
  return (
    <main className="page narrow">
      <PageHead title="Reviews" />
      <div className="stack">
        <ReviewSummary studio={data.studio} reviews={data.reviews} />
        {data.reviews.map((r) => <ReviewRow key={r.id} initial={r} canReply={canReply} />)}
      </div>
    </main>
  );
}
