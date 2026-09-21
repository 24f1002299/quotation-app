# Voice-First Quotation App — Product Design

## Design intent

The app is for contractors who are often on site, may have limited time and may prefer Hindi, Marathi, or Hinglish over long English forms. The interface should feel calm, dependable, and practical: one clear next action per screen, large tap targets, readable money values, and no hidden essential controls.

The main journey is deliberately short:

```text
Open app → New voice quote → Speak / type → Review line items → Add customer details
        → Generate PDF → Share → Return to home
```

Every online or AI-assisted action has a visible state and a manual alternative. A user must always be able to finish a quotation by typing and editing.

## Colour system

Use the supplied palette as a restrained, high-contrast neutral system.

| Token | Hex | Use |
|---|---:|---|
| `surface` | `#E6E8E6` | App background, quiet cards, disabled fill |
| `surfaceMuted` | `#CED0CE` | Dividers, input borders, secondary containers |
| `sage` | `#9FB8AD` | Informational highlights, selected filters, soft success surfaces |
| `forest` | `#475841` | Primary actions, active navigation, headings, key totals |
| `gunmetal` | `#3F403F` | Main body text, icons, dark surfaces |

Rules:

- Use `#E6E8E6` as the default canvas; it reduces glare in outdoor use better than a stark white screen.
- Use `#475841` only for the primary action, selected state, and important totals. Do not use it as a large background everywhere.
- Set text in `#3F403F`; use white text only on `#475841` or `#3F403F` after contrast verification.
- Use `#9FB8AD` for confirmation and status surfaces, not as the only indicator of success or selection. Pair colour with an icon and label.
- Use semantic exception colours outside the palette only where necessary: destructive/error red, warning amber, and success green. They must be accessible and never be the only signal.

Suggested Flutter theme tokens:

```dart
const appBackground = Color(0xFFE6E8E6);
const surfaceMuted = Color(0xFFCED0CE);
const sage = Color(0xFF9FB8AD);
const forest = Color(0xFF475841);
const ink = Color(0xFF3F403F);
```

## Foundations

- **Typography:** Use Noto Sans Devanagari (already required for PDFs) or a paired, highly legible sans family. Base body text is at least 16sp; money totals are 24–32sp, semi-bold.
- **Touch:** All interactive targets are at least 48 × 48dp. Primary action buttons are full-width and 56dp tall.
- **Spacing:** Use an 8dp grid. Standard screen padding: 20dp. Card radius: 16dp. Keep shadows subtle; borders and spacing should create the hierarchy.
- **Language:** The selected language is always visible in the capture flow. Use plain Hindi/Marathi labels with small English support text only when it prevents ambiguity. Never rely on an icon alone for a primary action.
- **Feedback:** Show autosave/sync state near the title or primary action: `Saved`, `Saving…`, `Offline — saved on this phone`, or `Sync failed — Retry`.
- **Accessibility:** Support Android font scaling, TalkBack labels, high contrast for text, and an alternative typed route for every voice task.

## Navigation model

Use a simple bottom navigation bar with three destinations. Keep the centre action visually dominant.

```text
[Home]              [New quote]              [Quotes]
 overview              starts flow              searchable history
```

`New quote` opens a choice sheet with **Speak quote** first and **Type quote** second. Settings, profile, rate card, language, help, and privacy live in the Home overflow/profile area—not in the bottom navigation.

Back behaviour protects unfinished work:

- From capture/review, Back returns to the prior step and retains the draft.
- Leaving a changed draft shows `Save draft and leave` and `Keep editing`; never present a destructive default.
- After sharing, show a success screen with `Done` as the primary action and `Edit quote` as a secondary option.

## Core screens

### 1. First-time setup

Keep onboarding to one focused screen sequence: phone sign-in, business/trade, and rate setup. Ask only for the minimum needed to create a first quote; logo, GSTIN, address, and terms can be completed later from Profile.

```text
Business details
Your business name [________________]
Trade              [Tiling ▾]
City (optional)    [________________]

                 [Continue]
```

Use a labelled progress indicator such as `Step 1 of 2`, not dots with no meaning. When rates are initially missing, offer `Set rates now` and `Use later`; the latter routes to a quote with missing rates clearly flagged.

### 2. Home

The home screen should answer “what do I do next?” in one glance.

```text
Good morning, Asha                         [Profile]
Offline — drafts are safe on this phone

[ 🎙  New voice quote ]
   Speak in Hindi, Marathi, or Hinglish

Drafts (2)                                      See all
[Patil Residence · 3 items · Edited 10 min ago >]

Recent quotes                                   See all
[Sharma Tiles · ₹24,600 · Shared · Yesterday >]
```

The voice CTA uses `forest` with white text. The microphone is supplementary to the text label. A single compact offline banner appears only when relevant.

### 3. Capture / transcript

This is the focus screen: no bottom navigation while recording. The main record button stays in the thumb-reachable lower area.

```text
< Back                 New voice quote          Hindi ▾

Tell us the work and quantities
Example: “Kitchen wall tiles, 120 square feet.”

                 [ large mic button ]
                    Tap to speak

                 00:18  Recording…
                  [Stop recording]

               or [Type quotation instead]
```

After transcription, replace the recorder with an editable transcript. Show a simple status: `Checking items…` then `3 items found`. On failure, retain the transcript and present `Try again` and `Create manually` side by side; neither should be hidden behind an error dialog.

### 4. Review quote

Review is the trust screen. The grand total remains visible in a sticky footer but never obscures controls. Each line item is an easy-to-scan card, not an editable spreadsheet.

```text
< Back                  Review quote              Saved
Patil Residence                         Add customer >

Needs attention (1)
[! Wall paint             Quantity needs checking >]

Line items                                      [+ Add item]
[Floor tiles   120 sq ft × ₹85        ₹10,200     >]
[Grouting       120 sq ft × ₹15        ₹1,800     >]

Subtotal                                    ₹12,000
GST                                         Not added

Total                                      ₹12,000
[Continue to PDF]
```

Tapping a line item opens a bottom sheet with fields in this order: item, quantity, unit, rate, then calculated amount. Amount is read-only. Use `Save changes` as the only primary action. Provide Delete as a labelled, destructive secondary action with confirmation.

Uncertain or missing values use a warning icon, explicit sentence, and `Fix now`; never use an unexplained confidence percentage. PDF generation is disabled only for essential unresolved values, and the blocking message names the exact item/field.

### 5. Customer and terms

Use progressive disclosure. Client name and phone/site are near the top; quotation number, validity, GST, advance, notes, and terms live in an `More quote details` section. Preserve the last used defaults.

```text
Customer details
Client name *       [________________]
Phone (optional)    [________________]
Site (optional)     [________________]

More quote details                            [Expand]

[Generate PDF]
```

### 6. PDF preview and share

Generate the PDF locally, present a clear preview, then put `Share PDF` at the bottom as the sole primary CTA.

```text
< Back              Quotation ready
[ PDF preview ]
Quote Q-... · ₹12,000 · 13 Sep 2026

[Share PDF]
 Edit quote
```

After Android’s share sheet returns, do not falsely claim delivery. Mark the quote as `Shared` only when the user confirms `Mark as shared`, or label it `Share sheet opened` if no confirmation is required by the product.

### 7. Quote history

Default to an uncluttered chronological list. Search by customer/quote number, with chips for `Draft`, `Ready`, and `Shared`. Each row has customer, amount, date, and status—nothing else.

Empty state: `Your quotations will appear here` with `Create a voice quote` CTA.

## States and microcopy

| Situation | Message | Action |
|---|---|---|
| Offline | `You’re offline. This draft is saved on this phone.` | `Continue editing` |
| No microphone access | `Microphone permission is needed to record. You can still type a quote.` | `Allow microphone`, `Type quote` |
| Transcription failure | `We could not turn this recording into text. Your draft is safe.` | `Try again`, `Create manually` |
| Missing rate | `Add a rate for Floor tiles before creating the PDF.` | `Add rate` |
| Extraction uncertainty | `Please check the quantity for Wall paint.` | `Review item` |
| Sync failed | `Couldn’t sync changes. They remain saved on this phone.` | `Retry` |

Avoid technical words such as “schema”, “API”, “confidence”, or error codes in the normal UI. Put a support reference ID behind a `Get help` link.

## PDF visual direction

The PDF is a business document, so it should be more formal than the app: white page, `ink` body text, `forest` headings/rules, and a thin `sage` accent. Avoid dark page backgrounds, decorative illustrations, and crowded table borders. The total is visually strong but not oversized; include quote ID, issue date, validity, and business contact information for credibility.

## Validation checklist

- A new user can identify the primary action on every core screen in under five seconds.
- The first voice quote is reachable from Home in one tap.
- A contractor can complete the flow with one thumb and large text enabled.
- Every error preserves work and gives a manual or retry path.
- Critical state is expressed with text and icon as well as colour.
- The design is tested with Hindi, Marathi, Hinglish, long customer names, long item names, and an offline draft.
