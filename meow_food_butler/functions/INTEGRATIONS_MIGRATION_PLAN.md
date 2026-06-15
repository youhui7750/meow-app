# Plan: Move Outscraper + Apify (+ AI extraction) to the Backend

> Goal: pull every third-party HTTP integration out of the Flutter client and into
> `functions/`, one folder per external API. The app keeps **zero API keys** and
> only calls Cloud Functions (honoring CLAUDE.md: "Zero-Client LLM", "Never
> hardcode any API key", region lock `asia-east1`, fail-safe `{ ok, code, … }`).

---

## 1. Why

- **Keys are hardcoded in the client today** — a hard CLAUDE.md violation:
  - Outscraper key: [`lib/services/outscraper_service.dart:7`](../lib/services/outscraper_service.dart#L7)
  - Apify token: [`lib/services/apify_service.dart:10`](../lib/services/apify_service.dart#L10)
  Anyone can pull these from a built app/web bundle.
- **Business logic lives in the UI layer** (the Instagram pipeline is in a
  ViewModel; the Outscraper→FoodCard mapping is in a widget
  [`restaurant_list_sheet.dart`](../lib/views/map/widgets/restaurant_list_sheet.dart)).
- **The AI name-extraction is a stub** ([`ai_agent_service.dart:337`](../lib/services/ai_agent_service.dart#L337)
  returns mocked strings). The backend already has Gemini wired (`agent/`), so the
  real extraction belongs there.
- Centralizing also lets us fix the latency/duplicate-query problems (separate
  doc) once, server-side, with caching and `place_id`-based lookups.

## 2. Current call sites (what we are replacing)

The three files you named map 1:1 onto the backend pipeline stages — none is
dropped. `instagram_import_vm.dart` is the **integrator**, and it becomes
`pipeline.js` (the orchestration moves server-side intact):

| Client file (your role description) | Stage | Becomes |
|---|---|---|
| `apify_service.dart` (IG → caption/location) | scrape | `integrations/apify/` |
| `ai_agent_service.dart` `extractRestaurantName` (**Apify → LLM query**) | extract | `integrations/extract/` (real Gemini) |
| `outscraper_service.dart` (**LLM query → JSON → Card**) | enrich | `integrations/outscraper/` |
| `instagram_import_vm.dart` `pipelineImportAndBuildCard` (**整合兩個 services**) | **orchestrate** | **`integrations/pipeline.js`** + `importInstagram` callable |
| `restaurant_list_sheet.dart` `_fetchRestaurantForExperience` | enrich (re-use) | `fetchRestaurant` callable → same outscraper module |

## 3. Target backend layout (one folder per API)

```
functions/
  integrations/
    index.js            # barrel: re-exports apify, outscraper, extract, pipeline
    keys.js             # getApifyToken() / getOutscraperKey() from Firestore config/*
    apify/
      index.js          # startRun → poll → dataset; returns { caption, location }
    outscraper/
      client.js         # raw HTTP (search-v3 / reviews-v3 / photos), key + timeout
      transform.js      # Outscraper place JSON → FoodCard map (fromMap-ready)
      index.js          # fetchRestaurantDetail / fetchReviews / fetchPhotos
    extract/
      index.js          # extractRestaurantName(caption, locationTag) via Gemini
    pipeline.js         # apify → extract → outscraper → { experience, restaurant }
```

- Mirrors the existing **folder-per-skill** convention in `skills/`.
- Each provider folder is self-contained: its key, base URL, request shaping, and
  response cleaning live together. Swapping/retiring a provider touches one folder.
- `index.js` (functions entry) stays thin — it just wires two new callables to
  `integrations/`.

## 4. Key source: Firestore config docs (redeploy-free) — NOT `defineSecret`

Per your decision, the Apify/Outscraper keys live in Firestore `config/*` docs and
are read **at request time**, exactly like Gemini keys in
[`agent/keys.js`](agent/keys.js) `getGeminiKeys()`. No `defineSecret`, no
`firebase functions:secrets:set`, no redeploy to rotate — just edit the doc.

Add a tiny `integrations/keys.js` mirroring the `getGeminiKeys` shape (60 s cache,
single key each — these providers don't rotate like Gemini):

```js
// integrations/keys.js
const { configDoc } = require("../collections");
// getApifyToken()    -> reads config/apify      field APIFY_TOKEN
// getOutscraperKey() -> reads config/outscraper field OUTSCRAPER_API_KEY
// 60s in-function cache; falls back to process.env.<NAME>; returns "" when missing.
```

Docs to create in the console (Admin SDK bypasses rules; clients are already
denied `config/*` by `firestore.rules`):

```
config/apify        ->  { APIFY_TOKEN:        "apify_api_..." }
config/outscraper   ->  { OUTSCRAPER_API_KEY: "...your outscraper key..." }
```

- The new callables therefore need **no `secrets:` binding** for these two (still
  bind `geminiApiKey` for the extract step, since it shares the chat keys).
- `checkApiKeys` gains best-effort checks: report Apify/Outscraper as "missing"
  when their config docs are empty, so the client startup heads-up still works.
- Optional: a one-line fallback to `process.env.APIFY_TOKEN` / `OUTSCRAPER_API_KEY`
  for local emulator runs, same as `getGeminiKeys` falls back to the secret.

## 5. New callables (in `index.js`) + contracts

Both follow the fail-safe envelope: always resolve to `{ ok, code, … }`, never throw.

### `importInstagram({ url })`
Runs the full pipeline server-side.

Response (maps shaped to match the Dart `fromMap` factories so the client can
deserialize directly):
```jsonc
{
  "ok": true,
  "code": "ok",
  "experience": { /* ExperienceCard.toMap shape: placeId, placeTitle,
                     placeAddress(/location), latitude, longitude, originalURL,
                     photoUrls, personalTags, personalNote, isDone:false, … */ },
  "restaurant": { /* FoodCard.toMap shape: id, displayNames[], location,
                     formattedAddress, rating, reviews, photoUrls,
                     reviewSnippets[], category, … */ }
}
```
Error codes: `bad-url`, `ig-unreadable`, `no-restaurant` (AI), `not-found`
(Outscraper empty), `provider-error`. Each carries a cat-toned `reply` string.

### `fetchRestaurant({ query?, placeId? })`
Single place → FoodCard map. Prefer `placeId` (Outscraper `place_id:` lookup);
fall back to `query`. Collapses detail + photos + reviews into one response
(server runs them with `Promise.all`). This replaces
`_fetchRestaurantForExperience` and also fixes the "queries other places" bug by
accepting an id.

```jsonc
{ "ok": true, "code": "ok", "restaurant": { /* FoodCard.toMap shape */ } }
```

### Runtime options (important)
The Apify poll loop + Outscraper sync calls are slow. Set on both callables:
```js
onCall({ secrets: [geminiApiKey], timeoutSeconds: 300, memory: "512MiB", region: REGION })
```
- Only `geminiApiKey` is bound (for the extract step). Apify/Outscraper keys come
  from Firestore at request time (section 4), so they need no binding.
- Default 60 s will time out on Apify — raise it and cap the poll loop (~4 min) so
  we fail cleanly before the function deadline.

## 6. Module responsibilities (port, don't rewrite behavior)

- **`apify/index.js`** — port `fetchIgCaptionAndLocation` from the Dart service
  verbatim (start actor → poll every 3 s → read dataset). Add a max-attempts
  guard. Token from `resolveApifyToken()`.
- **`outscraper/client.js` + `transform.js`** — port the three fetches and the
  `_prepareQuery` / short-URL expand / `_looksLikePlaceId` / photo-URL upscaling
  helpers. `transform.js` owns the place-JSON → FoodCard map (the logic now in
  `OutscraperService.fetchRestaurantDetail` + `restaurant_list_sheet`'s merges).
- **`extract/index.js`** — real implementation of `extractRestaurantName`. Reuse
  `getGeminiKeys()` + a one-shot Genkit `generate()` (or `getButler(key)`),
  with the existing prompt; key rotation/`UNKNOWN`→null handling. Removes the mock.

- **`pipeline.js` (the integrator — the file you flagged).** This is the full
  server-side port of `instagram_import_vm.dart::pipelineImportAndBuildCard`.
  Nothing from the VM is lost; it is moved verbatim minus the `ChangeNotifier`/UI
  state. Concretely it must reproduce every step:
  1. `apify.fetchIgCaptionAndLocation(igUrl)` → `{ caption, locationTag }`; throw
     `ig-unreadable` when empty.
  2. query = `queryFromLocationTag(locationTag)` **else**
     `extract.extractRestaurantName(caption, locationTag)`; throw `no-restaurant`
     when null (keeps the "use the IG location tag first, fall back to the LLM"
     shortcut from [instagram_import_vm.dart:42-45](../lib/view_models/instagram_import_vm.dart#L42-L45)).
  3. **Outscraper in parallel** — `Promise.all([fetchRestaurantDetail(query),
     fetchPhotos(query, "menu", 5), fetchReviews(query, 3)])` instead of the
     current three sequential `await`s (the VM does them one-by-one — this is the
     main perf win, ~3× faster on the slow path).
  4. `tags = extractHashtags(caption)`; fallback `["IG匯入","待吃清單"]`.
  5. `photoUrls = mergePhotoUrls(detail.photoUrls, menuPhotos)`.
  6. Build the **ExperienceCard map** (placeId, placeTitle, placeAddress, lat/lng,
     `originalURL: igUrl`, photoUrls, personalTags=tags, `personalRating: 0`,
     `personalNote: caption`, `isDone: false`) and the **FoodCard map**
     (`detail ?? fallback` then `copyForImport(originalURL, visited:false, tags,
     photoUrls, reviewSnippets)`), exactly as the VM does at
     [instagram_import_vm.dart:78-126](../lib/view_models/instagram_import_vm.dart#L78-L126).
  7. Return `{ experience, restaurant }`.
  Helpers `queryFromLocationTag`, `extractHashtags`, `mergePhotoUrls` move here too
  (they're private to the VM today).

**Photo persistence decision:** keep `RestaurantRepository.saveRestaurant`
(client) for now — it already mirrors photos into Storage and is unrelated to key
safety. Backend returns data only. (Optional later phase: move caching to backend
so the client never touches Storage write logic either.)

## 7. Frontend changes (make the client lightweight)

Net effect: the app ships **no provider keys, no HTTP scraping code, no polling
loop, no JSON→Card mapping** — only two thin callable clients plus the existing
models for deserialization.

- **Delete** `services/outscraper_service.dart` (~320 lines),
  `services/apify_service.dart` (~57 lines), and `AiAgentService` (the mock).
  Also remove the `http` import usage these added. Keep `ChatService` (it happens
  to live in `ai_agent_service.dart` — split it into its own file while here, or
  leave it; it's unrelated to extraction).
- **Add** thin callable clients (region `asia-east1`, mirror `ChatService`):
  - `InstagramImportService.import(url)` → `importInstagram` → returns
    `InstagramImportResult` (parse `experience`/`restaurant` via the existing
    `ExperienceCard.fromMap` / `FoodCard.fromMap`).
  - `RestaurantLookupService.fetch({query, placeId})` → `fetchRestaurant`.
  Each is ~30 lines: build payload, call, map result, handle the `{ ok, code }`
  envelope. No business logic.
- **`instagram_import_vm.dart`** keeps only the `ChangeNotifier` state machine
  (`isLoading`, `loadingMessage`, `errorMessage`) and delegates to
  `InstagramImportService` — all pipeline/HTTP code (~140 lines) moves to
  `pipeline.js`. The loading-message strings can stay client-side for UX.
- **`restaurant_list_sheet.dart`** `_fetchRestaurantForExperience` → one call to
  `RestaurantLookupService` with `experience.placeId ?? experience.placeTitle`
  (drops the 3 sequential Outscraper calls from the widget; also fixes the
  "queries other places" bug by passing the id).
- No widget/UI changes; `import_dialog.dart` and `main_map_screen.dart` keep
  working against the unchanged `InstagramImportResult` type.

## 8. Execution order

1. **Keys**: add `integrations/keys.js` (`getApifyToken`/`getOutscraperKey` from
   Firestore, getGeminiKeys-style); extend `checkApiKeys` to report them.
2. **Provider modules**: `integrations/apify`, `integrations/outscraper`,
   `integrations/extract`. `node --check` each.
3. **Pipeline**: `integrations/pipeline.js` + `integrations/index.js` barrel.
4. **Callables**: add `importInstagram` + `fetchRestaurant` to `index.js` with
   `timeoutSeconds`/`memory`. Keep `chatWithButler`/`checkApiKeys` untouched.
5. **Deploy + create docs**: `firebase deploy --only functions`, then create
   `config/apify` and `config/outscraper` in the console (you'll do the keys). No
   `secrets:set`, no redeploy to rotate later.
6. **Frontend**: add the two callable clients; rewire the VM + list sheet; delete
   the old services. `flutter analyze`.
7. **Verify** (section 9).
8. **Cleanup**: the hardcoded keys are gone with the deleted files; update
   CLAUDE.md "Active Session State".

> Backend (steps 1–5) and frontend (step 6) are deployable independently: the new
> callables can ship first and be smoke-tested (with the config docs in place)
> before the client switches over.

## 9. Verification

- **Backend, pre-deploy**: `node --check` on every new file; `npm run serve`
  (emulator) and hit `importInstagram`/`fetchRestaurant` with a known IG URL and a
  known `placeId`. For the emulator, seed keys via the Firestore emulator
  `config/apify`+`config/outscraper` docs, or the `process.env` fallback.
- **Contract**: confirm returned maps deserialize via `FoodCard.fromMap` /
  `ExperienceCard.fromMap` (watch `displayNames`, `location`, `reviewSnippets`,
  `personalTags`).
- **End-to-end**: `flutter run` → paste an IG link → card imports; open a My
  Places card → detail loads. Confirm **no API keys remain in the client** (grep
  the bundle) and `checkApiKeys` flags missing Apify/Outscraper keys.
- **Latency**: Apify import completes within the 300 s budget; `fetchRestaurant`
  with `placeId` returns the correct place (not a different branch).

## 10. Risks / notes

- **Function timeout**: the #1 risk. Apify polling can run minutes — must raise
  `timeoutSeconds` and cap poll attempts. If imports routinely exceed ~5 min,
  follow up with an async job pattern (write status to Firestore, client watches).
- **Cold start**: first import after deploy is slower; acceptable.
- **Region**: all new callables pinned to `asia-east1` (CLAUDE.md lock).
- **Cost/quota**: extraction now spends Gemini quota (shared with chat keys) — same
  rotation via `getGeminiKeys()`. Outscraper/Apify quotas unchanged, just moved.
- **Scope guard**: this migration is lift-and-shift + key safety. The
  duplicate-query / `place_id` performance fixes are tracked separately; `fetchRestaurant`'s
  `placeId`-first signature is the hook for them.
