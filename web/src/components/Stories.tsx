// Stories (like Instagram): a row of circles for everyone with a live story, a full-screen viewer that
// plays them (tap left/right, hold to pause), likes and replies, and posting a photo with a caption.
// Stories disappear after 24 hours. The poster sees who viewed, liked and replied, and can remove one.
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useNavigate } from "react-router-dom";
import { Eye, Flag, Heart, ImagePlus, MessageCircle, Plus, Send, Trash2, X } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { compressImage } from "../lib/image";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import type { Story, StoryActivity, StoryAuthor } from "../lib/types";
import { ReportSheet } from "./social";
import { Avatar, ConfirmDialog, PromotedTag, Sheet, Spinner, ToolButton, VerifiedBadge, useToast } from "./ui";

const STORY_SECONDS = 6;

/** Can the signed-in user post? Artists with a profile, studios once approved. */
function useCanPost() {
  const app = useApp();
  if (!app.account || !app.account.email_verified_at) return false;
  if (app.account.role === "artist") return !!app.artistProfile?.artist_name.trim();
  if (app.account.role === "studio_owner") return app.ownedStudio?.status === "approved";
  return false;
}

export function StoryBar() {
  const app = useApp();
  const canPost = useCanPost();
  const [authors, setAuthors] = useState<StoryAuthor[] | null>(null);
  const [viewing, setViewing] = useState<number | null>(null);
  const [composing, setComposing] = useState(false);
  const load = useCallback(() => api.storyFeed().then(setAuthors).catch(() => setAuthors([])), []);
  useEffect(() => { if (app.account) load(); }, [app.account, load]);
  if (!app.account || authors == null) return null;
  const own = authors.find((a) => a.is_own);
  const others = authors.filter((a) => !a.is_own);
  if (!canPost && others.length === 0) return null;
  const ordered = own ? [own, ...others] : others;

  return (
    <>
      <div className="story-bar" role="list" aria-label={t("Stories")}>
        {canPost && !own && (
          <button className="story-circle" onClick={() => setComposing(true)} role="listitem">
            <span className="story-ring add"><Avatar url={app.account.role === "studio_owner" ? app.ownedStudio?.photo_urls[0] : app.artistProfile?.avatar_url} name={t("You")} size={58} /><span className="story-plus"><Plus size={14} /></span></span>
            <span className="caption2 clamp-1">{t("Your story")}</span>
          </button>
        )}
        {ordered.map((a, i) => (
          <button key={a.user_id} className="story-circle" onClick={() => setViewing(i)} role="listitem">
            <span className={`story-ring ${a.all_seen ? "seen" : ""}`}>
              <Avatar url={a.avatar_url} name={a.name} size={58} />
              {a.is_own && canPost && <span className="story-plus" onClick={(e) => { e.stopPropagation(); setComposing(true); }}><Plus size={14} /></span>}
            </span>
            <span className="caption2 clamp-1">{a.is_own ? t("Your story") : a.name}</span>
          </button>
        ))}
      </div>
      {viewing != null && <StoryViewer authors={ordered} start={viewing} onClose={() => { setViewing(null); load(); }} />}
      <StoryComposer open={composing} onClose={() => setComposing(false)} onPosted={() => { setComposing(false); load(); }} />
    </>
  );
}

function Overlay({ children }: { children: ReactNode }) {
  return createPortal(<div className="story-overlay">{children}</div>, document.body);
}

function StoryViewer({ authors, start, onClose }: { authors: StoryAuthor[]; start: number; onClose: () => void }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [authorIndex, setAuthorIndex] = useState(start);
  const [stories, setStories] = useState<Story[] | null>(null);
  const [index, setIndex] = useState(0);
  const [progress, setProgress] = useState(0);
  const [paused, setPaused] = useState(false);
  const [reply, setReply] = useState("");
  const [showActivity, setShowActivity] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [reporting, setReporting] = useState(false);
  const author = authors[authorIndex];
  const story = stories?.[index];

  useEffect(() => {
    setStories(null); setIndex(0); setProgress(0);
    api.userStories(author.user_id).then((list) => {
      if (list.length === 0) { next(); return; }
      setStories(list);
      // Start at the first one not seen yet.
      const firstNew = list.findIndex((s) => !s.seen);
      setIndex(firstNew > 0 && !author.is_own ? firstNew : 0);
    }).catch((e) => { toast(userMessage(e)); onClose(); });
  }, [authorIndex]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { if (story && !author.is_own && !story.seen) api.markStoryViewed(story.id).catch(() => undefined); }, [story?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const next = useCallback(() => {
    setProgress(0);
    if (stories && index < stories.length - 1) setIndex(index + 1);
    else if (authorIndex < authors.length - 1) setAuthorIndex(authorIndex + 1);
    else onClose();
  }, [stories, index, authorIndex, authors.length, onClose]);
  const previous = () => {
    setProgress(0);
    if (index > 0) setIndex(index - 1);
    else if (authorIndex > 0) setAuthorIndex(authorIndex - 1);
  };

  const holding = paused || showActivity || confirmRemove || reporting || reply.length > 0;
  useEffect(() => {
    if (!story || holding) return;
    const timer = window.setInterval(() => setProgress((p) => {
      if (p >= 1) { window.setTimeout(next, 0); return 1; }
      return p + 0.05 / STORY_SECONDS;
    }), 50);
    return () => window.clearInterval(timer);
  }, [story, holding, next]);

  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.tagName === "INPUT") return;
      if (e.key === "Escape") onClose(); else if (e.key === "ArrowRight") next(); else if (e.key === "ArrowLeft") previous();
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });

  async function toggleLike() {
    if (!story || !stories) return;
    const like = !story.liked_by_me;
    setStories(stories.map((s) => (s.id === story.id ? { ...s, liked_by_me: like, like_count: s.like_count + (like ? 1 : -1) } : s)));
    try { await api.likeStory(story.id, like); } catch (e) { toast(userMessage(e)); }
  }
  async function sendReply() {
    if (!story || !reply.trim()) return;
    try { await api.replyToStory(story.id, reply.trim()); setReply(""); toast(t("Reply sent."), "info"); } catch (e) { toast(userMessage(e)); }
  }
  async function remove() {
    if (!story || !stories) return;
    try {
      await api.removeStory(story.id);
      const rest = stories.filter((s) => s.id !== story.id);
      if (rest.length === 0) onClose(); else { setStories(rest); setIndex(Math.min(index, rest.length - 1)); setProgress(0); }
    } catch (e) { toast(userMessage(e)); }
  }
  const openProfile = () => { onClose(); navigate(author.studio_id ? `/studios/${author.studio_id}` : `/artists/${author.user_id}`); };

  return (
    <Overlay>
      <div className="story-stage" onPointerDown={() => setPaused(true)} onPointerUp={() => setPaused(false)} onPointerLeave={() => setPaused(false)}>
        {story ? <img key={story.id} src={story.media_url} alt="" className="story-media" draggable={false} /> : <div className="story-media center"><Spinner /></div>}
        <div className="story-top">
          <div className="story-progress">
            {(stories ?? [null]).map((s, i) => (
              <span key={s?.id ?? i}><span style={{ width: `${(i < index ? 1 : i === index ? progress : 0) * 100}%` }} /></span>
            ))}
          </div>
          <div className="row" style={{ gap: 10 }}>
            <button className="row" style={{ gap: 8, color: "#fff" }} onClick={openProfile}>
              <Avatar url={author.avatar_url} name={author.name} size={34} />
              <span className="subhead bold">{author.name}</span>{author.is_verified && <VerifiedBadge />}{author.is_promoted && <PromotedTag />}
              {story && <span className="caption" style={{ opacity: 0.75 }}>{Dates.relative(story.created_at)}</span>}
            </button>
            <span className="grow" />
            {author.is_own && story && <button className="story-icon" aria-label={t("Remove story")} onClick={() => setConfirmRemove(true)}><Trash2 size={18} /></button>}
            {!author.is_own && story && <button className="story-icon" aria-label={t("Report")} onClick={() => setReporting(true)}><Flag size={18} /></button>}
            <button className="story-icon" aria-label={t("Close")} onClick={onClose}><X size={22} /></button>
          </div>
        </div>
        <button className="story-tap left" aria-label={t("Previous")} onClick={previous} />
        <button className="story-tap right" aria-label={t("Next")} onClick={next} />
        <div className="story-bottom" onPointerDown={(e) => e.stopPropagation()}>
          {story?.caption && <div className="story-caption">{story.caption}</div>}
          {story && (author.is_own ? (
            <button className="story-activity-btn" onClick={() => setShowActivity(true)}>
              <Eye size={16} />{format("%lld views", story.view_count ?? 0)}<Heart size={16} />{story.like_count}<MessageCircle size={16} />{story.reply_count ?? 0}
            </button>
          ) : (
            <div className="row" style={{ gap: 8 }}>
              <input className="story-reply" placeholder={format("Reply to %@…", author.name)} value={reply} maxLength={1000}
                onChange={(e) => setReply(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") sendReply(); }} />
              {reply.trim() ? (
                <button className="story-icon" aria-label={t("Send")} onClick={sendReply}><Send size={20} /></button>
              ) : (
                <button className={`story-icon ${story.liked_by_me ? "liked" : ""}`} aria-label={t(story.liked_by_me ? "Unlike" : "Like")} onClick={toggleLike}>
                  <Heart size={24} fill={story.liked_by_me ? "currentColor" : "none"} />
                </button>
              )}
            </div>
          ))}
        </div>
      </div>
      {story && author.is_own && <ActivitySheet open={showActivity} storyId={story.id} onClose={() => setShowActivity(false)} />}
      <ReportSheet open={reporting} onClose={() => setReporting(false)} target={author.studio_id ? "studio" : "user"} targetId={author.studio_id ?? author.user_id} />
      <ConfirmDialog open={confirmRemove} title="Remove this story?" message="It disappears for everyone right away."
        actions={[{ title: "Remove", destructive: true, action: remove }]} onClose={() => setConfirmRemove(false)} />
    </Overlay>
  );
}

function ActivitySheet({ open, storyId, onClose }: { open: boolean; storyId: string; onClose: () => void }) {
  const [people, setPeople] = useState<StoryActivity[] | null>(null);
  useEffect(() => { if (open) { setPeople(null); api.storyActivity(storyId).then(setPeople).catch(() => setPeople([])); } }, [open, storyId]);
  return (
    <Sheet open={open} onClose={onClose} title="Activity" closeLabel="Done">
      {people == null ? <Spinner /> : people.length === 0 ? <div className="subhead secondary center" style={{ padding: 24 }}>{t("No one has seen this story yet.")}</div> : (
        <div className="stack">
          {people.map((p) => (
            <div key={p.person_id} className="card tight row top" style={{ gap: 10 }}>
              <Avatar url={p.avatar_url} name={p.name} size={40} />
              <div className="grow">
                <div className="row subhead semibold" style={{ gap: 6 }}>{p.name}{p.liked && <Heart size={14} color="var(--red)" fill="var(--red)" />}</div>
                {p.reply ? <div className="footnote">{p.reply}</div> : <div className="caption secondary">{p.viewed_at ? Dates.relative(p.viewed_at) : ""}</div>}
              </div>
            </div>
          ))}
        </div>
      )}
    </Sheet>
  );
}

export function StoryComposer({ open, onClose, onPosted }: { open: boolean; onClose: () => void; onPosted: () => void }) {
  const toast = useToast();
  const [photo, setPhoto] = useState<Blob | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [caption, setCaption] = useState("");
  const [posting, setPosting] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { if (!open) { setPhoto(null); setPreview(null); setCaption(""); } }, [open]);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  async function choose(file: File | undefined) {
    if (!file) return;
    try { const blob = await compressImage(file, 1440, 0.85); setPhoto(blob); setPreview(URL.createObjectURL(blob)); } catch (e) { toast(userMessage(e)); }
  }
  async function post() {
    if (!photo) return;
    setPosting(true);
    try { await api.postStory(photo, caption.trim()); toast(t("Your story is up for 24 hours."), "info"); onPosted(); } catch (e) { toast(userMessage(e)); }
    setPosting(false);
  }
  return (
    <Sheet open={open} onClose={onClose} title="New story" closeLabel="Cancel"
      actions={<ToolButton title={posting ? "Posting…" : "Share"} bold disabled={!photo || posting} onClick={post} />}>
      <div className="stack">
        <input ref={input} type="file" accept="image/*" hidden onChange={(e) => choose(e.target.files?.[0])} />
        <button className="story-pick" onClick={() => input.current?.click()} style={preview ? { backgroundImage: `url(${preview})` } : undefined}>
          {!preview && <><ImagePlus size={32} /><span className="subhead semibold">{t("Choose a photo")}</span></>}
        </button>
        <label className="field"><input placeholder={t("Add a caption (optional)")} value={caption} maxLength={200} onChange={(e) => setCaption(e.target.value)} /></label>
        <div className="caption secondary">{t("Stories are shown to people on EasySesh for 24 hours. Keep it about your music or studio – the community guidelines apply.")}</div>
        <button className="btn primary block" disabled={!photo || posting} onClick={post}>{posting ? <Spinner /> : t("Share story")}</button>
      </div>
    </Sheet>
  );
}
