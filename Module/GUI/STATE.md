# GUI Shared State

`$Script:` variables shared across GUI.psm1 and `Module/GUI/*.ps1`.
Scope is `Show-TweakGUI`'s closure. Not everything here is documented — this covers
what's actually useful to know when working in this area.

---

## The two infrastructure variables

| Variable | Purpose |
|----------|---------|
| `$Script:Ctx` | Context hashtable — groups `$Script:` state into categories (Theme, Data, Run, Filter, GameMode, UI, Services, Config, Mode, Preset, State). Created by `New-GuiContext`. Functions that accept `[hashtable]$Context = $Script:Ctx` can be tested with a substitute hashtable. |
| `$Script:GuiState` | Reactive state container — holds StatusText, StatusForeground, RunInProgress, ProgressCompleted, ProgressTotal, ProgressAction. Subscriber callbacks fire on the UI thread. Created by `New-ObservableState`. |

---

## Phase 2 consolidated state (in `$Script:Ctx`)

These variables were migrated from raw `$Script:` into `$Script:Ctx` sub-hashtables with accessor functions. Use the accessors in new code.

| Ctx path | Accessor (get / set) | Purpose |
|----------|----------------------|---------|
| `UI.CurrentPrimaryTab` | `Get-GuiCurrentPrimaryTab` / `Set-GuiCurrentPrimaryTab` | Currently selected primary tab object |
| `UI.LastStandardPrimaryTab` | `Get-GuiLastStandardPrimaryTab` / `Set-GuiLastStandardPrimaryTab` | Last non-Game-Mode primary tab (for restoring on Game Mode exit) |
| `Theme.CurrentTone` | `Get-GuiCurrentStatusTone` / `Set-GuiCurrentStatusTone` | Active status bar tone (`'muted'`, `'accent'`, `'success'`, etc.) |
| `State.UndoSnapshot` | *(direct Ctx access for now)* | Snapshot of selections before a destructive operation (preset load, mode switch) |
| `State.LastRunProfile` | *(direct Ctx access for now)* | Profile name or metadata from the most recent execution run |

---

## Late-bind function captures

These `$Script:` variables hold references to functions that are captured after all `Module/GUI/*.ps1` files are dot-sourced. They exist because extracted files cannot call functions defined later in the load order. Set in `GUI.psm1` initialization; consumed by `StateTransitions.ps1`, `ModeState.ps1`, `SearchFilterHandlers.ps1`, and event handlers throughout the GUI layer.

| Variable | Captures | Used by |
|----------|----------|---------|
| `$ClearTabContentCacheScript` | `Clear-TabContentCache` | StateTransitions, ModeState, filter updates |
| `$UpdateCurrentTabContentScript` | `Update-CurrentTabContent` | StateTransitions, ModeState, filter updates |
| `$SaveGuiUndoSnapshotScript` | `Save-GuiUndoSnapshot` | StateTransitions (preset/mode changes) |
| `$SyncUxActionButtonTextScript` | `Sync-UxActionButtonText` | StateTransitions, ModeState |
| `$ClearInvisibleSelectionStateScript` | `Clear-InvisibleSelectionState` | ModeState (safe/expert toggle) |
| `$UpdateHeaderModeStateTextScript` | `Update-HeaderModeStateText` | StateTransitions, ModeState |
| `$ShowGuiRuntimeFailureScript` | `Show-ScopedGuiRuntimeFailure` | ActionHandlers, PresetUI, event handlers |
| `$SetSearchInputStyleScript` | `Set-SearchInputStyle` | SearchFilterHandlers |
| `$SetSafeModeStateScript` | `Set-SafeModeState` | SearchFilterHandlers |
| `$SetAdvancedModeStateScript` | `Set-AdvancedModeState` | SearchFilterHandlers |
| `$SetGameModeStateScript` | `Set-GameModeState` | SearchFilterHandlers |
| `$SaveCurrentTabScrollOffsetScript` | `Save-CurrentTabScrollOffset` | SearchFilterHandlers |

These are called via `& $Script:ClearTabContentCacheScript` — never by function name in the extracted files.

---

## What must stay as direct `$Script:` access

These cannot be gated behind accessors without breaking something:

| Variable | Why |
|----------|-----|
| `$RunState` | Synchronized hashtable shared with the background execution runspace. Wrapping it breaks thread safety. |
| `$Controls` | WPF control array indexed by manifest position. Wrapping would add overhead to every tweak card read. |
| `$TweakManifest` | Loaded once at startup, read universally. Immutable after load. |
| `$CurrentTheme` | Read by all UI construction code. Immutable during a theme session. |
| `$MainForm`, `$ContentScroll`, `$PrimaryTabs`, `$HeaderBorder`, `$ActionButtonBar`, `$BtnPreviewRun`, `$BtnRun`, `$BtnDefaults`, `$StatusText`, `$RunPathContextLabel`, `$ChkScan`, `$ChkTheme`, `$Form` | WPF shell controls accessed from dot-sourced event handlers and execution transitions. |

---

## Mode and filter state

**Mode toggles** — these four drive everything:

| Variable | Purpose |
|----------|---------|
| `$SafeMode` | Safe mode on — simplified UX, high-risk tweaks hidden |
| `$AdvancedMode` | Expert mode on — full visibility |
| `$GameMode` | Game Mode active |
| `$ScanEnabled` | Environment scan enabled |

**Filter state** — written by filter controls, read by content builders:

`$CategoryFilter`, `$RiskFilter`, `$SelectedOnlyFilter`, `$HighRiskOnlyFilter`, `$RestorableOnlyFilter`, `$GamingOnlyFilter`, `$FilterUiUpdating`, `$SearchText` are the ones that matter.

`$FilterUiUpdating` is the important one — see Known Traps below.

---

## Game Mode state

Now gated behind accessor functions in `GameModeState.ps1`. Use the accessors:
- `Get-GameModeProfile`, `Get-GameModePlan`, `Get-GameModeDecisionOverrides`, `Get-ExecutionGameModeContext`

Don't read `$Script:GameModeProfile`, `$Script:GameModePlan` etc. directly in new code — the context object duplicates these and gets out of sync if you bypass the accessors.

---

## Execution state

What you actually need during a run:

| Variable | Purpose |
|----------|---------|
| `$RunInProgress` | Main guard — checked before starting a run, set during it |
| `$ExecutionSummaryRecords` | ArrayList of per-tweak result records (see MODELS.md) |
| `$ExecutionSummaryLookup` | Hashtable lookup of the same records by key — use this for O(1) access |
| `$AbortRequested` | Set by the abort button; checked by the execution worker between tweaks |
| `$ExecutionMode` | `'Run'` or `'Defaults'` — set at run start |
| `$ExecutionGameModeContext` | Game Mode context captured at run start; cleared by `Clear-GuiWindowRuntimeState` |

---

## Known traps

**`$FilterUiUpdating`** — must be `$true` while you're programmatically updating filter controls. If you miss it, filter events fire during the update and trigger a cascade of content rebuilds. This has caused hard-to-reproduce blank-tab bugs.

**`$RunState`** — synchronized hashtable. Crosses thread boundaries to the background runspace. Don't replace it with a plain hashtable; the `[hashtable]::Synchronized()` wrapper is what makes it safe.

**`Set-GuiStatusText` has two paths** — through `$Script:GuiState` (normal) and a direct WPF write (early init). The fallback exists because early-init status updates fire before ObservableState is wired. Don't remove it.

**`$ExecutionGameModeContext`** — set at run start, cleared at cleanup. If you see stale game mode data persisting after a run, check `Clear-GuiWindowRuntimeState`.

**Observable dispatch direction** — `New-ObservableState` dispatches synchronously when already on the UI thread and asynchronously (`DataBind` priority) when off it. If you're calling `.Set` from the UI thread and expecting synchronous propagation, that's already what happens — but don't add a `.Invoke()` wrapper thinking you need it.
