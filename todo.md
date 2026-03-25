# Baseline

Detailed release-readiness, product strategy, preset governance, UX, gaming mode, and GitHub launch recommendations

Current GUI reference

Prepared for GitHub release planning

## 1. Executive summary

Current position: Baseline is not just a debloat script. It is a modular Windows configuration platform with manifests, presets, helper libraries, GUI execution, logging, and a growing safety model. That puts it above most one-file scripts immediately.

Release recommendation: Public beta for advanced users is realistic now. A broad public launch aimed at normal users should wait until the preset model, warning flow, restore guidance, and failure handling are tightened.

How to stand out: WinUtil wins on audience, Sophia wins on depth, and most debloat repos win only on simplicity. Baseline can win on trust, clarity, and controlled opinionation: a cleaner preset system, stronger recovery UX, a legitimate gaming mode, and a polished GitHub release package.

## 2. What Baseline should be in the market

Recommended one-line product description:

- Baseline is a modular Windows debloater, optimizer, and hardening utility for Windows 10, Windows 11, and Windows Server.
- Baseline helps users clean up Windows, apply privacy and UX improvements, enable sensible performance tweaks, and optionally apply advanced hardening changes through a guided GUI or headless automation.
- Baseline should emphasize that presets, warnings, and restore recommendations exist to make powerful changes understandable, not to pretend the tool is risk-free.

### Baseline should compete on four attributes:

- Trust: manifest-backed metadata, warnings, preview, restore guidance, and transparent descriptions.
- Clarity: the user should understand what a preset will do and why it exists.
- Coverage: cleanup, privacy, UI, gaming, security, and maintenance from one interface.
- Control: headless execution, preset export/import, and module-driven organization.

## 3. Preset redesign: the highest-priority release task

Why this matters: The biggest risk before release is not code quality. It is preset semantics. If the “Safe” and “Balanced” experiences do not feel exactly like their names imply, users will lose trust quickly.

### Recommended preset ladder

### Rules to enforce in code

1. Use manifest metadata as the source of truth. Preset JSON should not silently contradict the manifest tier model.
1. If an item is marked high risk, not restorable, or strongly workflow-sensitive, it should never appear in Safe.
1. Balanced may include moderate-risk items, but it should still avoid destructive debloat, invasive hardening, or anything likely to break normal Office, OneDrive, gaming, or network sharing workflows.
1. Advanced should be renamed from Aggressive and presented as an expert preset, not as the “best” preset.
1. Preset generation should become automated: build presets from metadata tags and a small allowlist/denylist rule system instead of maintaining multiple manual sources of truth forever.

## 4. Advanced preset warning and normal-user guidance

### Rename Aggressive to Advanced and make the warning smarter, not just scarier.

- The word “Aggressive” sounds like the best performance choice. The word “Advanced” sounds like a power-user option with tradeoffs.
- The warning dialog should explain categories of impact, not just say “high risk.”
- The dialog should recommend creating a restore point before continuing, and for Advanced it should strongly recommend it.

### Recommended modal structure

- Title: Advanced preset warning
- Body: This preset is intended for experienced users and may remove or disable Windows features, change update/network/security behavior, affect compatibility, and include changes that are difficult to undo.
- Summary panel: selected count, medium-risk count, high-risk count, restart-required count, and not-fully-restorable count.
- Buttons: Cancel, Create Restore Point, Preview Run, Continue Anyway.

### Preset card copy for normal users

- Minimal — Small quality-of-life changes with minimal behavior changes.
- Safe — Recommended for most users. Low-risk cleanup and usability improvements.
- Balanced — More privacy and system tuning with moderate tradeoffs.
- Advanced — Experienced users only. Higher-risk, opinionated system changes.

## 5. GUI and UX recommendations

### The GUI is already one of Baseline’s strongest assets. The goal is not a redesign; it is refinement.

- Make the preset explanation panel clearer. When a user chooses a preset, show what it prioritizes, what it avoids, and who it is for.
- Add a compact “impact summary” bar above Preview Run: selected tweaks, high-risk, restart-required, restorable, and categories touched.
- Add visual differentiation between toggles, one-time actions, and uninstall/remove operations.
- Use stronger grouping inside categories: privacy, cleanup, compatibility, performance, hardening, and troubleshooting.
- Add “Show only selected”, “Show high-risk”, “Show restorable only”, and “Show gaming-related” filters.
- Expose a restore recommendation banner whenever Balanced or Advanced is selected.
- Add a “Why this preset includes this” section in Preview Run so users can understand the intent behind each batch.

### Recommended UX additions

## 6. Add a real Gaming Mode

Why Gaming Mode matters: Gaming is one of the cleanest ways for Baseline to stand out. A dedicated mode is easier to market than generic “performance tweaks,” and your manifests already include a gaming category with solid starting points.

### What Gaming Mode should be

- A focused mode for gaming systems, not a “disable everything” preset.
- Built around lower latency, clean overlays, optional Xbox adjustments, GPU-related compatibility settings, and conservative background reductions.
- Context-aware: keep it friendly for gamers who use Game Bar, overlays, Xbox services, or anti-cheat sensitive setups.

### Recommended Gaming Mode structure

- Core gaming baseline: GPU Scheduling, optional visual/latency tweaks, conservative background cleanup, and user-chosen Game Bar behavior.
- Troubleshooting bucket: Fullscreen Optimizations, Multiplane Overlay, network adapter power savings, and other “only if needed” fixes.
- Competitive mode bucket: stronger latency/performance tweaks with explicit warnings.
- Streaming/content mode bucket: preserve overlays, microphone, notifications, capture features, and Xbox integrations if desired.

### Rules for Gaming Mode

1. Do not automatically disable Game Bar or Xbox features inside Gaming Mode. Make these choices explicit because many users rely on them.
1. Keep Fullscreen Optimizations in a troubleshooting group because your manifest already treats disabling it as high risk.
1. Offer profile variants such as Casual, Competitive, and Troubleshoot.
1. Add a “Detect installed gaming apps / GPU vendors / Xbox components” step later if you want smarter defaults.

## 7. Execution, logging, and recovery: the trust layer

- Normalize failures into clear categories: access denied, reboot required, already in desired state, missing dependency, unsupported OS/build, not applicable, network/download failure, partial success.
- Add per-item recovery hints and retry actions where safe.
- Separate “failed” from “skipped” and “not applicable.” This reduces false alarm fatigue.
- Add an end-of-run remediation panel with “Retry failed items” and “Open detailed log.”
- If restore point creation is available, link it before large or expert runs.

### Recommended failure summary output

- Successful changes
- Already in desired state
- Skipped by preset policy or unsupported environment
- Failed and recoverable
- Failed and manual intervention required
- Restart required to complete or verify

## 8. GitHub release package and README strategy

- Lead with Baseline as the product name and keep “Windows debloater / optimizer / hardening utility” in the subtitle.
- Open the README with a polished hero screenshot and a very short value statement.
- Add a compatibility table: Windows 10 2019-current x86/x64/arm64, Windows 11 current x64/arm64, Server 2016-2025, PowerShell 5.1.
- Explain preset philosophy early. Most README readers will decide whether they trust the project based on that section alone.
- Include a “Recommended for normal users: Safe” statement high on the page.
- Add a dedicated “Before you run Advanced” warning block in the README.
- Include examples for GUI launch, headless execution, manifest validation, bootstrap, and preset import/export.

### What the first screen of your README should communicate

- What Baseline is.
- What operating systems and architectures it supports.
- Why it is different from one-off debloat scripts.
- Which preset normal users should choose.
- Why advanced users may still want it over older tools.

## 9. How Baseline stands out on top

### To win attention in a crowded space, Baseline needs a sharper identity than “another Windows tweak script.”

1. Own the phrase “modular Windows configuration utility.” This sounds more serious than “debloater” alone.
1. Win on preset trust. If users believe Safe really is safe, that becomes a major differentiator.
1. Win on transparency. Preview Run, detailed descriptions, restart indicators, and restore recommendations should feel first-class.
1. Win on scenario modes. Gaming Mode is the obvious first one; later you can add Workstation, Privacy, and Recovery profiles.
1. Win on quality of documentation. Most repos in this category undersell or oversell themselves. A clean README, screenshots, warning model, and change log will make Baseline look more mature immediately.

## 10. Recommended roadmap before GitHub release

## 11. Release readiness checklist

- [ ] Pass: Safe preset contains only low-regret items and is the recommended default.
- [ ] Pass: Advanced warning clearly explains what may happen and recommends a restore point.
- [ ] Pass: README presents Baseline as a polished product, not a raw script dump.
- [ ] Pass: Preset JSON and manifest tiers no longer contradict each other silently.
- [ ] Pass: Gaming Mode exists or is clearly on the near-term roadmap.
- [ ] Pass: Users can distinguish toggle vs action vs uninstall behavior easily.
- [ ] Pass: Log output is supplemented by recovery guidance, not just raw status lines.
- [ ] Fail: Safe includes medium/high-friction networking, update, uninstall, or hardening behavior without clear justification.
- [ ] Fail: Advanced is still marketed as the best or fastest option instead of the expert option.
- [ ] Fail: The project launches publicly without a restore-point recommendation or clear preset philosophy.

## 12. Final recommendation
