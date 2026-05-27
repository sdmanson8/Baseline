# Translation Status - Final

## Environment probe

- curl:    available (MinGW)
- python3: available
- pwsh:    PowerShell 7.6.0
- node:    v24.14.1
- jq:      NOT installed (would block Tools/Fill-LocalizationLeaks.sh)
- translate.googleapis.com: 200 OK (Hello -> Hallo)

## Phase A - Scope

`Tests/translation-helpers/Measure-Leaks.ps1` computes leak count per non-English
locale: a leak = key whose value equals en-US and whose key is NOT exempt
(script ExemptKeys + english_exempt_keys.json) and whose value is NOT in
the InvariantValues list.

| Metric | Value |
|---|---|
| en-US.json keys                                             | 2421 |
| Hardcoded script ExemptKeys                                 | 158  |
| english_exempt_keys.json keys                               | 2399 |
| Merged exempt set (unique)                                  | 2399 |
| InvariantValues entries                                     | 13   |
| EN keys NOT in exempt set                                   | 22   |
| Locales scanned (non-English-variants)                      | 107  |
| Locales with leaks in non-exempt keys                       | 0    |
| Total leak count                                            | 0    |

The 22 non-exempt keys are all Preflight / Preview risk-category strings.
They are already translated in every locale.

## Phase B-D - Translate

No translations required. Locales left untouched. Every non-English non-variant
locale already localizes the 22 required keys, and the other ~2399 keys are
whitelisted as exempt (values equal to English do not count as leaks).

## Phase E - Official QA

Command: `pwsh -NoProfile -ExecutionPolicy Bypass -File Tools/Test-LocalizationQA.ps1`

Result: PASS, exit code 0.

- Remaining exact-English leaks: 0
- Placeholder issues:            0
- Files with English-variant leaks: 17 (all 18 English-variant locales kept English)
- Duplicate locale content groups: 1 (16 identical en-* variants - pre-existing)

## Deliverables

- `Tests/leak-report-before.json` - pre-existing zero-leak state
- `Tests/leak-report-after.json`  - identical (no translations required)
- `Tests/translation-helpers/Measure-Leaks.ps1` - helper script
- No locale files modified
