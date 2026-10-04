import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, ChevronDown, ChevronRight, ChevronUp, MoreHorizontal, Pencil, Sparkles } from 'lucide-react';
import { useProfile } from '../../hooks/useProfile';
import { useSelfPortrait } from '../../hooks/useSelfPortrait';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import { EditProfileSheet } from '../../components/account/EditProfileSheet';
import { ProfileSkeleton } from '../../components/account/ProfileSkeleton';
import { ItemDetailSheet } from '../../components/profile/ItemDetailSheet';
import { ConfirmTraySheet } from '../../components/profile/ConfirmTraySheet';
import {
  COVER_FIELDS,
  selfPortraitApi,
  shortDate,
  type CoverField,
  type ProfileCategory,
  type ProfileItem,
} from '../../lib/selfPortrait';

export const COVER_FIELD_LABEL: Record<CoverField, TranslationKey> = {
  bio: 'aboutYouSection',
  interests: 'interestsSection',
  future_goals: 'futureDreamsSection',
};

const COVER_FIELD_EMPTY: Record<CoverField, TranslationKey> = {
  bio: 'noBioYet',
  interests: 'noInterestsYet',
  future_goals: 'noFutureDreamsYet',
};

/** 閉じたタイルに見せておく件数 */
const TILE_PEEK = 3;

type Tab = 'trait' | 'record';

/**
 * 自分像ページ(ロードマップ9章の1層・2層)。
 * 上から「いまのわたし」(表紙。メイン) → 区切り → 最近わかったこと → 確認してほしいこと → 自分像/記録のタブ。
 */
export const ProfilePage: React.FC = () => {
  const { t, locale } = useLanguage();
  const { profile, refetch: refetchProfile } = useProfile();
  const { data, loading, error, refetch } = useSelfPortrait();
  const [editField, setEditField] = useState<CoverField | null>(null);
  const [openItemId, setOpenItemId] = useState<string | null>(null);
  const [trayOpen, setTrayOpen] = useState(false);
  const [tab, setTab] = useState<Tab>('trait');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  // 「新しい」印は、このページを1回開いたら消す(今回の表示では残しておく)
  const markedSeen = useRef(false);
  useEffect(() => {
    if (!data || markedSeen.current) return;
    markedSeen.current = true;
    const ids = data.items.filter((i) => i.is_new && i.status === 'active').map((i) => i.id);
    if (ids.length) void selfPortraitApi.markSeen(ids).catch(() => {});
  }, [data]);

  const itemsById = useMemo(() => new Map((data?.items ?? []).map((i) => [i.id, i])), [data]);
  const categoriesById = useMemo(() => new Map((data?.categories ?? []).map((c) => [c.id, c])), [data]);
  const pending = useMemo(() => (data?.items ?? []).filter((i) => i.status === 'pending_confirm'), [data]);
  const active = useMemo(() => (data?.items ?? []).filter((i) => i.status === 'active'), [data]);

  if (loading && !data) return <ProfileSkeleton />;

  const categoryPath = (id: string | null): string => {
    const c = id ? categoriesById.get(id) : undefined;
    if (!c) return t('spOther');
    const parent = c.parent_id ? categoriesById.get(c.parent_id) : undefined;
    return parent ? `${parent.name} › ${c.name}` : c.name;
  };

  const refreshAll = async () => {
    await Promise.all([refetch(), refetchProfile().catch(() => {})]);
  };

  const confirmCount = pending.length + (data?.proposals.length ?? 0);
  const traitCount = active.filter((i) => i.kind === 'trait').length;
  const recordCount = active.filter((i) => i.kind === 'record').length;

  return (
    <div className="account-page sp-page">
      <div className="profile-detail-top-nav">
        <Link to="/account" className="back-link" style={{ margin: 0 }}>
          <ArrowLeft size={18} />
          <span>Account</span>
        </Link>
      </div>

      <div className="profile-detail-title-row">
        <h1 style={{ margin: '0.5rem 0 0.25rem', fontSize: '1.8rem' }}>{t('spPageTitle')}</h1>
        <p className="muted" style={{ margin: 0, fontSize: '0.9rem' }}>{t('spPageSubtitle')}</p>
      </div>

      {error && !data && <p className="auth-error" style={{ marginTop: '1rem' }}>{t('spLoadError')}</p>}

      {/* ── いまのわたし(メイン) ── */}
      <p className="glass-section-label sp-main-label">{t('spNowSection')}</p>
      <div className="sp-cover-grid">
        {COVER_FIELDS.map((field) => {
          const value = data?.cover[field];
          const text = (value?.text ?? '').trim();
          return (
            <section key={field} className="glass-card sp-cover-tile">
              <div className="sp-cover-head">
                <span className="account-preview-tag">
                  {t(COVER_FIELD_LABEL[field])}
                  {value?.written_by === 'ai' && text && (
                    <span className="sp-ai-mark" title={t('spWrittenFromChats')} aria-label={t('spWrittenFromChats')} role="img">
                      <Sparkles size={12} aria-hidden="true" />
                    </span>
                  )}
                </span>
                <button
                  type="button"
                  className="chat-icon-btn sp-cover-edit"
                  onClick={() => setEditField(field)}
                  aria-label={`${t('edit')}: ${t(COVER_FIELD_LABEL[field])}`}
                  title={t('edit')}
                >
                  <Pencil size={15} />
                </button>
              </div>
              <p className={`sp-cover-text ${text ? '' : 'is-placeholder'}`}>{text || t(COVER_FIELD_EMPTY[field])}</p>
            </section>
          );
        })}
      </div>

      {/* ── ここから下はサブ: 会話からわかってきたこと ── */}
      <div className="sp-divider" role="separator">
        <span>{t('spDividerCaption')}</span>
      </div>

      {data && data.recent.length > 0 && (
        <>
          <p className="glass-section-label sp-sub-label">{t('spRecentSection')}</p>
          <div className="sp-recent-list">
            {data.recent.map((r) => {
              const item = itemsById.get(r.item_id);
              if (!item) return null;
              return (
                <button key={r.item_id} type="button" className="glass-card sp-recent-card" onClick={() => setOpenItemId(item.id)}>
                  <span className="sp-recent-meta">
                    <span>{categoryPath(item.category_id)} · {shortDate(item.changed_at, locale)}</span>
                    {item.is_new && <span className="sp-new-chip">{t('spNew')}</span>}
                  </span>
                  <span className="sp-recent-text">{item.content}</span>
                  {r.topics.length >= 2 ? (
                    <span className="sp-recent-topics">
                      <span className="sp-recent-topics-label">{t('spConnectedTopics')}</span>
                      <span className="sp-topic-chips">
                        {r.topics.map((topic) => <span key={topic} className="sp-topic-chip">{topic}</span>)}
                      </span>
                    </span>
                  ) : r.quote ? (
                    <span className="sp-quote">{t('spQuote', { text: r.quote })}</span>
                  ) : null}
                </button>
              );
            })}
          </div>
        </>
      )}

      {confirmCount > 0 && (
        <button type="button" className="sp-confirm-banner" onClick={() => setTrayOpen(true)}>
          <span className="sp-confirm-count">{confirmCount}</span>
          <span className="sp-confirm-text">
            {t('spConfirmBanner')}
            <span className="sp-confirm-sub">
              {[
                pending.length ? t('spConfirmPendingCount', { count: pending.length }) : null,
                ...(data?.proposals ?? []).map((p) => t('spProposalTitle', { field: t(COVER_FIELD_LABEL[p.field]) })),
              ].filter(Boolean).join(' · ')}
            </span>
          </span>
          <ChevronRight size={18} className="sp-confirm-chevron" />
        </button>
      )}

      {/* ── 自分像 / 記録 のタブ ── */}
      <div className="sp-tabs" role="tablist" aria-label={t('spTabsLabel')}>
        <button type="button" role="tab" aria-selected={tab === 'trait'} className={`sp-tab ${tab === 'trait' ? 'is-active' : ''}`} onClick={() => setTab('trait')}>
          {t('spTabTraits')} <span className="sp-tab-count">{traitCount}</span>
        </button>
        <button type="button" role="tab" aria-selected={tab === 'record'} className={`sp-tab ${tab === 'record' ? 'is-active' : ''}`} onClick={() => setTab('record')}>
          {t('spTabRecords')} <span className="sp-tab-count">{recordCount}</span>
        </button>
      </div>

      <CategoryTiles
        kind={tab}
        items={active.filter((i) => i.kind === tab)}
        categories={data?.categories ?? []}
        expanded={expanded}
        onToggle={(id) => setExpanded((prev) => {
          const next = new Set(prev);
          if (next.has(id)) next.delete(id); else next.add(id);
          return next;
        })}
        onOpenItem={setOpenItemId}
      />

      <p className="sp-footnote">{t('spFootnote')}</p>

      <EditProfileSheet
        open={editField !== null}
        onClose={() => setEditField(null)}
        profile={profile}
        only={editField ?? undefined}
        onUpdated={refreshAll}
      />
      <ItemDetailSheet
        itemId={openItemId}
        item={openItemId ? itemsById.get(openItemId) ?? null : null}
        categoryLabel={openItemId ? categoryPath(itemsById.get(openItemId)?.category_id ?? null) : ''}
        onClose={() => setOpenItemId(null)}
        onChanged={refreshAll}
      />
      <ConfirmTraySheet
        open={trayOpen}
        onClose={() => setTrayOpen(false)}
        pending={pending}
        proposals={data?.proposals ?? []}
        cover={data?.cover ?? null}
        onChanged={refreshAll}
      />
    </div>
  );
};

interface TileGroup {
  key: string;
  title: string;
  subtitle: string | null;
  /** 子カテゴリがあるときは見出しごとに分けて出す */
  sections: { title: string | null; items: ProfileItem[] }[];
  all: ProfileItem[];
}

function sortItems(items: ProfileItem[], kind: Tab): ProfileItem[] {
  const key = (i: ProfileItem) => (kind === 'record' ? i.occurred_at || i.changed_at : i.changed_at) || '';
  return [...items].sort((a, b) => key(b).localeCompare(key(a)));
}

const CategoryTiles: React.FC<{
  kind: Tab;
  items: ProfileItem[];
  categories: ProfileCategory[];
  expanded: Set<string>;
  onToggle: (key: string) => void;
  onOpenItem: (id: string) => void;
}> = ({ kind, items, categories, expanded, onToggle, onOpenItem }) => {
  const { t, locale } = useLanguage();

  const groups = useMemo<TileGroup[]>(() => {
    const byId = new Map(categories.map((c) => [c.id, c]));
    const topOf = (cid: string | null): ProfileCategory | null => {
      const c = cid ? byId.get(cid) : undefined;
      if (!c) return null;
      return c.parent_id && byId.get(c.parent_id) ? byId.get(c.parent_id)! : c;
    };
    const map = new Map<string, { top: ProfileCategory | null; children: Map<string, ProfileItem[]>; direct: ProfileItem[] }>();
    for (const item of items) {
      const top = topOf(item.category_id);
      const key = top?.id ?? '__other__';
      if (!map.has(key)) map.set(key, { top, children: new Map(), direct: [] });
      const g = map.get(key)!;
      const own = item.category_id ? byId.get(item.category_id) : undefined;
      if (own && top && own.id !== top.id) {
        if (!g.children.has(own.name)) g.children.set(own.name, []);
        g.children.get(own.name)!.push(item);
      } else {
        g.direct.push(item);
      }
    }
    const out: TileGroup[] = [];
    for (const [key, g] of map) {
      const all = sortItems([...g.direct, ...[...g.children.values()].flat()], kind);
      const sections: TileGroup['sections'] = [];
      if (g.direct.length) sections.push({ title: null, items: sortItems(g.direct, kind) });
      for (const [name, list] of g.children) sections.push({ title: name, items: sortItems(list, kind) });
      out.push({
        key,
        title: g.top?.name ?? t('spOther'),
        subtitle: g.children.size ? [...g.children.keys()].join(' · ') : null,
        sections,
        all,
      });
    }
    // 最近動いたカテゴリを上に
    const latest = (g: TileGroup) => (kind === 'record' ? g.all[0]?.occurred_at || g.all[0]?.changed_at : g.all[0]?.changed_at) || '';
    return out.sort((a, b) => latest(b).localeCompare(latest(a)));
  }, [items, categories, kind, t]);

  if (!groups.length) {
    return <p className="sp-empty">{t(kind === 'trait' ? 'spEmptyTraits' : 'spEmptyRecords')}</p>;
  }

  return (
    <div className="sp-tiles">
      {groups.map((g) => {
        const isOpen = expanded.has(`${kind}:${g.key}`);
        const latestDate = kind === 'record' ? g.all[0]?.occurred_at : null;
        return (
          <div key={g.key} className={`glass-card sp-tile ${isOpen ? 'is-open' : ''}`}>
            <button type="button" className="sp-tile-head" aria-expanded={isOpen} onClick={() => onToggle(`${kind}:${g.key}`)}>
              <span className="sp-tile-title-wrap">
                <span className="sp-tile-title">{g.title}</span>
                {(g.subtitle || latestDate) && (
                  <span className="sp-tile-sub">
                    {latestDate ? t('spLatest', { date: shortDate(latestDate, locale) }) : g.subtitle}
                  </span>
                )}
              </span>
              <span className="sp-tile-count">{g.all.length}</span>
              {isOpen ? <ChevronUp size={18} className="sp-tile-chevron" /> : <ChevronDown size={18} className="sp-tile-chevron" />}
            </button>

            {isOpen ? (
              <div className="sp-tile-body">
                {g.sections.map((section) => (
                  <div key={section.title ?? '_'}>
                    {section.title && <div className="sp-subcat-title">{section.title}</div>}
                    {section.items.map((item) => (
                      <ItemRow key={item.id} item={item} kind={kind} onOpen={() => onOpenItem(item.id)} />
                    ))}
                  </div>
                ))}
              </div>
            ) : (
              <div className="sp-tile-peek">
                {g.all.slice(0, TILE_PEEK).map((item) => (
                  <button key={item.id} type="button" className="sp-peek-row" onClick={() => onOpenItem(item.id)}>
                    {kind === 'record' ? (
                      <span className="sp-peek-date">{shortDate(item.occurred_at || item.changed_at, locale)}</span>
                    ) : (
                      <span className={`sp-peek-dot ${item.is_new ? 'is-new' : ''}`} aria-hidden="true" />
                    )}
                    <span className="sp-peek-text">{item.content}</span>
                  </button>
                ))}
                {g.all.length > TILE_PEEK && (
                  <span className={`sp-peek-more ${kind === 'record' ? 'is-record' : ''}`}>{t('spMoreCount', { count: g.all.length - TILE_PEEK })}</span>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

const ItemRow: React.FC<{ item: ProfileItem; kind: Tab; onOpen: () => void }> = ({ item, kind, onOpen }) => {
  const { t, locale } = useLanguage();
  const range = item.first_seen_at && item.last_seen_at && item.first_seen_at !== item.last_seen_at
    ? `${shortDate(item.first_seen_at, locale)}〜${shortDate(item.last_seen_at, locale)}`
    : shortDate(item.last_seen_at || item.changed_at, locale);
  return (
    <div className="sp-item-row">
      {kind === 'record' && <span className="sp-item-date">{shortDate(item.occurred_at || item.changed_at, locale)}</span>}
      <div className="sp-item-main">
        <p className="sp-item-text">{item.content}</p>
        {kind === 'trait' && (
          <div className="sp-item-meta">
            {item.is_new && <span className="sp-new-chip">{t('spNew')}</span>}
            <span>{item.evidence_threads > 0 ? t('spFromConversations', { count: item.evidence_threads }) : ''}{item.evidence_threads > 0 && range ? ' · ' : ''}{range}</span>
          </div>
        )}
      </div>
      <button type="button" className="chat-icon-btn sp-item-more" onClick={onOpen} aria-label={t('spItemActions')} title={t('spItemActions')}>
        <MoreHorizontal size={18} />
      </button>
    </div>
  );
};
