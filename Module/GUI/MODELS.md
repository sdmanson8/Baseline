# Shared Object Models

Object shapes used across the GUI and helper modules.
These cover what you need when working with preview/execution/summary code.
For the tweak manifest shape, read `Manifest.Helpers.ps1` — it's defined there and not worth duplicating here.

---

## 1. Preview Run List Item

Source: `PreviewBuilders.ps1` → `Get-SelectedTweakRunList`

This is the shape that flows into execution. Fields you add here are available in the execution
summary record (see `New-ExecutionSummaryRecord` in `ExecutionSummary.ps1`).

**Fields that actually matter:**

| Field | Type | Notes |
|-------|------|-------|
| Key | string | Manifest index as string. Treat as opaque — don't assume numeric even though it looks it. |
| Name | string | Display name |
| Function | string | PowerShell function to call |
| Type | string | `'Toggle'`, `'Action'`, or `'Choice'` |
| TypeKind | string | Semantic subtype — drives how the execution engine calls the function. Wrong TypeKind = wrong call. |
| Risk | string | `'Low'`, `'Medium'`, `'High'` |
| Selection | string | The selected value or parameter |
| MatchesDesired | bool | Already at desired state — execution skips these. If detection is wrong, items silently no-op. |
| Restorable | bool | Can be directly undone |
| RecoveryLevel | string | `'Direct'`, `'DefaultsOnly'`, `'RestorePoint'`, `'Manual'` |
| RequiresRestart | bool | |
| PresetTier | string | `'Minimal'`, `'Basic'`, `'Balanced'`, `'Advanced'` |
| IsRemoval | bool | Package removal — affects confirmation and summary wording |
| BlastRadius | string | User-facing impact description |
| FromGameMode | bool | Added by the Game Mode plan builder |

---

## 2. Execution Summary Record

Source: `ExecutionSummary.ps1` → `Initialize-ExecutionSummary`

Created from run list items at run start, then updated during execution.

**Fields set at initialization:** everything from the run list item (see above), plus `Status = 'Pending'`.

**Fields updated during/after execution:**

| Field | Type | Notes |
|-------|------|-------|
| Status | string | `'Pending'` → `'Success'` / `'Failed'` / `'Skipped'` / `'AlreadyApplied'` / etc. |
| OutcomeState | string | Classification from `Get-ExecutionSummaryClassification` |
| OutcomeReason | string | Human-readable outcome explanation |
| FailureCategory | string | Failure bucket — used for retry decisions and summary grouping |
| IsRecoverable | bool | Whether a retry makes sense |
| RecoveryHint | string | What to tell the user if it failed |

**Where drift happens:**

`OutcomeState` and `FailureCategory` come from `Get-ExecutionSummaryClassification`, which
pattern-matches on Status + Detail text strings. If you change the wording of a failure message
in the execution engine, classification can silently break — the item still shows as failed but
lands in the wrong bucket. Test `Get-ExecutionSummaryClassification` when changing execution output strings.

---

## 3. Execution Pipeline

All GUI modes run through one pipeline:

```
Selection → Plan → Preview → Run → Summary
```

| Mode | How selection is built | Plan builder | Choke point |
|------|------------------------|-------------|-------------|
| Manual | User toggles/choices in GUI controls | `Get-SelectedTweakRunList` | `Get-ActiveTweakRunList` |
| Preset | `Set-TabPreset` updates controls, then re-read | `Get-SelectedTweakRunList` | `Get-ActiveTweakRunList` |
| Game Mode | Profile + decision overrides build a plan | `Build-GameModePlan` → `$Script:GameModePlan` | `Get-ActiveTweakRunList` |
| Defaults | Restorable tweaks with their default values | `Get-WindowsDefaultRunList` | Direct → `Start-GuiExecutionRun` |

`Get-ActiveTweakRunList` is the choke point for the first three modes — safe mode filtering,
run-state checks, and game mode plan injection all happen there.

Defaults bypass it entirely and go straight to execution. Keep that in mind if you're adding
pre-run logic — it won't apply to Defaults runs unless you add it explicitly.

---

## 4. Game Mode Plan Entry

Source: `GameModeUI.ps1` → `New-GameModePlanEntry`

Same shape as a Preview Run List Item, with `FromGameMode = $true`, `GameModeProfile` set,
and `GameModeOperation` (`'Apply'` or `'Undo'`). Advanced panel entries also have `IsAdvanced = $true`.

Not worth a separate table — just treat it as a run list item with those extra fields present.
