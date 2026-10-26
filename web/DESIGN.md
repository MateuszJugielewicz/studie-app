# EasySesh website design

The website should feel like a website, not a copy of the iPhone and Android apps. It keeps the
brand (the orange → magenta → violet "neon" and the `easysesh•` logo) but uses web conventions:
a real header with text links, solid surfaces with hairline borders, left-aligned page titles,
compact buttons, and wide layouts that use the screen (list + map, photo mosaic, footer columns).

The values live as CSS variables at the top of `src/styles/app.css`. Pages use the variables and
classes, never raw colours.

Direction is based on the project's own brand and general patterns of booking marketplaces and
SaaS marketing sites; no external design library was used.

## Colour

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `--bg` | `#FAF9F7` | `#0E0D0C` | Page background (warm off-white / near-black) |
| `--bg-2` | `#F3F1ED` | `#161513` | Bands and the footer |
| `--card` | `#FFFFFF` | `#1B1A18` | Cards, panels, inputs, menus |
| `--stroke` | `#E8E5E0` | `#2B2926` | Hairline borders and dividers |
| `--stroke-strong` | `#D5D0C8` | `#3A3733` | Input borders, hover borders |
| `--text` | `#17140F` | `#F5F3EF` | Body text and headings |
| `--text-2` | `#625C54` | `#A9A39A` | Secondary text (≥ 4.5:1 on `--bg`) |
| `--text-3` | `#9C968D` | `#6F6A63` | Placeholders, disabled |
| `--primary` | `#C23A17` | `#FF6A3D` | Primary buttons, links, active nav, selected states |
| `--on-primary` | `#FFFFFF` | `#17140F` | Text on `--primary` |
| `--accent` | `#D9431E` | `#FF6A3D` | Icons and small brand marks |
| `--neon` | accent → magenta → violet | | Logo dot, hero highlight, promoted tags. Never on buttons or headings. |
| `--positive` / `--warning` / `--red` | | | Status only |

## Typography

- Display: **Bricolage Grotesque** (variable, self-hosted) for page titles and section headings.
- Body and UI: **Inter** (variable, self-hosted).
- Scale: 12 / 13 / 15 / 16 (body) / 18 / 22 / 30 / 44–68 (hero, fluid).
- Weights: 400 body, 500 UI, 600 labels and buttons, 700 headings.
- Body line height 1.5, headings 1.1, prose capped at ~68ch.

## Spacing and layout

- 4px base: 4, 8, 12, 16, 24, 32, 48, 72, 96.
- Container 1200px (wide pages 1320px), 24px gutter (16px on phones).
- Marketing sections are 72–96px apart; app pages 24–32px.

## Shape and depth

- Radius: 8 (chips, small buttons), 10 (buttons, inputs), 14 (cards), 20 (photos, hero media).
- Shadows: `--shadow-sm` for cards on hover, `--shadow` only for floating things (menus, dialogs).
- No glass blur, except the sticky header.

## Components

- **Header**: sticky, 64px, logo left, text links (active = text colour + 2px primary underline),
  sign in as a quiet link and sign up as a primary button on the right.
- **Phones**: a flat bottom bar with a top border (not a floating pill).
- **Buttons**: 44px, radius 10. Primary = solid `--primary`; secondary = card with border; quiet = text.
  Hover darkens, focus shows a 2px ring, disabled at 45% opacity.
- **Cards**: solid `--card`, 1px `--stroke`, radius 14, no shadow at rest.
- **Forms**: grouped panels with a plain heading above (not iOS uppercase captions).
- **Toggles**: 40×24, `--primary` when on.
- **Segmented control**: tabs on a sunken track, the selected tab is a raised card.
- **Section headings**: display font, 20px, no glow bar.
- **Icon tiles**: tinted square (14% of the colour) with a coloured icon, not a gradient tile.

## Imagery and icons

- Icons: Lucide, 1.75–2px stroke, 16–20px.
- Studio photos are the hero of every listing: 4:3 cards, a 1 + 4 photo mosaic on studio pages.
- No emoji as icons, no device mock-ups of the app on the website.
