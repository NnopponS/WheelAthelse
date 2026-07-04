# WheelAthlete — Architecture Delta (Phase 3: Browse & Record Hardening)

> Delta on top of `.project/architecture.md` (Phase 1) and Phase 2 changes
> in `.project/plan.md`. Firmware is untouched in Phase 3 — all changes are
> in the Flutter app.

## Updated high-level diagram (app-side only)

```
┌─────────────────────────────────────────────────────┐
│                Flutter App (Phase 3)                 │
│                                                      │
│  Tabs:  Connect │ Live │ Browse │ Experiments (NEW)  │
│                                                      │
│  Record flow:                                        │
│    Pick Protocol Template (NEW)                      │
│    → auto-fill topic + trial number                  │
│    → Start → countdown → record (no MARK)            │
│    → Stop → summary card → Re-record (NEW)           │
│                                                      │
│  Browse:                                             │
│    Topic → Trial → Session                           │
│    + Delete at all 3 levels (NEW)                    │
│    + Search bar (NEW)                                │
│    + Tag filter chips (NEW)                          │
│                                                      │
│  Experiments dashboard (NEW):                        │
│    Groups sessions by Protocol Template              │
│    Shows progress: "3/5 trials done"                 │
│    Filter by tag                                     │
│                                                      │
│  Storage:                                            │
│    WheelAthleteData/                                 │
│    ├── <topic>/                                      │
│    │   ├── topic_meta.json                           │
│    │   └── trial_<NN>/                               │
│    │       ├── session_<id>.csv                      │
│    │       └── session_<id>_meta.json (+tags)        │
│    └── protocols.json (NEW)                          │
└─────────────────────────────────────────────────────┘
```

## New / modified components

### 1. Protocol Template system (NEW)

**Model:** `app/lib/records/protocol_template.dart`
```dart
class ProtocolTemplate {
  final String id;           // UUID or hex timestamp
  final String name;         // e.g. "20m Sprint Test"
  final String? description; // e.g. "From standing start, 20m max effort"
  final String topicName;    // auto-created/linked topic folder name
  final int targetTrialCount; // e.g. 5 → dashboard shows "3/5 done"
  final int sampleRateHz;    // default 100
  final DateTime createdAt;
}
```

**Storage:** `app/lib/records/protocol_repository.dart`
- Stored as a single `protocols.json` file in the app documents directory
  (alongside `WheelAthleteData/`).
- CRUD: `listTemplates()`, `createTemplate()`, `updateTemplate()`,
  `deleteTemplate()`, `getTemplate(id)`.
- Abstract interface + `PathProviderProtocolRepository` impl +
  `InMemoryProtocolRepository` for tests (same pattern as
  `StorageRepository`).

**Providers:** `app/lib/state/protocol_providers.dart`
- `protocolRepositoryProvider` — Provider<ProtocolRepository>
- `protocolTemplatesProvider` — FutureProvider<List<ProtocolTemplate>>
- `protocolTemplateNotifierProvider` — Notifier for CRUD operations

### 2. Session tags (NEW)

**Model change:** `SessionMeta` gains:
```dart
final List<String> tags;        // default: []
final String? protocolTemplateId; // links session to a template
```
- `toJson` / `fromJson` updated. Old sessions without `tags` default to
  `[]`. Old sessions without `protocolTemplateId` default to `null`.

**Storage change:** `StorageRepository` gains:
- `updateSessionTags(topic, trialNumber, sessionId, List<String> tags)`
- `listAllSessions()` → `List<SessionSummary>` (flat list across all
  topics/trials for search + dashboard). `SessionSummary` = `SessionMeta`
  + `topic` + `trialNumber` (already in meta but explicit for flat list).

### 3. Delete at all 3 levels

**Storage:** `StorageRepository` gains:
- `deleteTrial(topic, trialNumber)` — deletes the trial folder + all
  sessions inside. New method (not yet implemented).

**UI:** `browse_page.dart` — add delete option to popup menus at all 3
levels with confirmation dialogs:
- Topic: popup menu gains "Delete" → confirmation dialog showing trial +
  session count → `deleteTopic()`
- Trial: new popup menu with "Delete" → confirmation showing session
  count → `deleteTrial()`
- Session: `SessionListItem` gains a delete button → confirmation →
  `deleteSession()`

### 4. Mark Event removal

**Files touched:**
- `record_page.dart` — remove `MarkEventButton` from recording view,
  remove `markerCount` badge from recording + stopped views.
- `recording_providers.dart` — remove `markEvent()` method,
  `_markNextBatch` flag, `markers` list from state. Keep `MarkerEvent`
  model + `markers` field in `SessionMeta` for reading old sessions.
- `mark_event_button.dart` — keep file (used in tests / backward compat)
  but stop importing it in record_page. Or delete if no other references.
- CSV `marker` column stays (always `0` for new recordings).

### 5. Quick re-record

**`record_page.dart` stopped view:**
- After stop, summary card shows: topic, trial number, duration, sample
  count, sync quality.
- New "Re-record" button → calls `recordCountdownProvider.start()` with
  the same `SessionConfig` but `trialNumber = nextTrialNumber(topic)`.
- "New Recording" button stays (resets to idle, picks new template/topic).

### 6. Template picker in Record page

**`record_page.dart` idle view:**
- New: horizontal scrollable row of protocol template chips at the top.
- Tapping a template auto-fills: topic (creates if doesn't exist),
  trial number (next for that topic), sample rate.
- "Custom" chip = current behavior (manual topic dropdown).
- Below: existing topic dropdown + trial info + Start button.

### 7. Search/filter on Browse

**`browse_page.dart`:**
- Search bar in the AppBar (or below it) at the Topic list level.
- Filters topics by name (case-insensitive substring).
- At Session list level: search bar filters by session ID, notes, date
  (ISO), and tags.
- Tag filter: horizontal chip row showing all unique tags across the
  current list. Tapping a tag filters to sessions with that tag.

**New:** `app/lib/state/browse_providers.dart`
- `browseSearchProvider` — StateProvider<String> for the search query
- `browseTagFilterProvider` — StateProvider<String?> for the active tag

### 8. Experiment tracker dashboard (NEW)

**New file:** `app/lib/ui/experiment_tracker_page.dart`
- Lists all protocol templates as cards.
- Each card shows: template name, description, progress bar
  (sessions / targetTrialCount), last session date.
- Tapping a card → navigates to the topic's trial list in Browse (or a
  filtered view).
- "New Template" FAB → create template dialog.

**New file:** `app/lib/state/experiment_tracker_providers.dart`
- `experimentProgressProvider` — FutureProvider that loads all templates
  + counts sessions per template (matching by `protocolTemplateId` or
  by `topicName`).

**`home_page.dart`:**
- Add 4th NavigationDestination: "Experiments" (icon: Icons.science_rounded).
- `IndexedStack` gains `_ExperimentsTab()`.

## Data flow

```
User creates Protocol Template
  → protocols.json updated
  → topic folder auto-created (if not exists)

User picks template in Record page
  → SessionConfig carries protocolTemplateId
  → Start → countdown → record → stop
  → SessionMeta saved with protocolTemplateId + tags=[]

User adds tags to session (Browse → session → edit)
  → session_*_meta.json updated with tags

User searches/filters on Browse
  → in-memory filter on loaded list (no storage change)

User opens Experiments tab
  → load all templates + all sessions
  → group sessions by protocolTemplateId
  → show progress per template
```

## File impact summary

| File | Action | Subtask |
|---|---|---|
| `records/protocol_template.dart` | NEW | #22 |
| `records/protocol_repository.dart` | NEW | #22 |
| `records/session_model.dart` | MODIFY (+tags, +protocolTemplateId) | #25 |
| `records/storage_repository.dart` | MODIFY (+deleteTrial, +updateSessionTags, +listAllSessions) | #21, #25 |
| `state/protocol_providers.dart` | NEW | #22 |
| `state/recording_providers.dart` | MODIFY (remove markEvent, +re-record config) | #20, #24 |
| `state/browse_providers.dart` | NEW | #26 |
| `state/experiment_tracker_providers.dart` | NEW | #27 |
| `ui/browse_page.dart` | MODIFY (+delete, +search, +tag filter) | #21, #26 |
| `ui/record_page.dart` | MODIFY (-MARK, +template picker, +re-record) | #20, #23, #24 |
| `ui/experiment_tracker_page.dart` | NEW | #27 |
| `ui/home_page.dart` | MODIFY (+4th tab) | #27 |
| `ui/tag_editor_dialog.dart` | NEW | #25 |
| `widgets/session_list_item.dart` | MODIFY (+delete button, +tags display) | #21, #25 |
| `widgets/protocol_template_card.dart` | NEW | #27 |
| `widgets/mark_event_button.dart` | KEEP (no longer imported in record_page) | #20 |
