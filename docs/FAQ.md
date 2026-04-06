# Frequently Asked Questions

> **Status:** Current — maintained FAQ

Common questions about Baseline, including antivirus false positives, preset selection, undo and recovery, and telemetry.

Baseline is recommended for advanced users and careful enthusiasts who want explicit control over Windows configuration. If this is your first time, start with the Safe Mode beginner guide and the Minimal preset.

---

### Windows Defender or another antivirus flags Baseline as malicious

This is a known false positive and is expected behavior for any system configuration tool that operates at this level.

**Why it happens.** Baseline is a PowerShell toolkit that modifies registry values, disables or reconfigures Windows services, applies Group Policy settings via LGPO.exe, and removes built-in packages. These are exactly the kinds of operations that heuristic and behavioral antivirus engines are designed to flag. The detection is not based on a known malware signature; it is based on the pattern of system changes the scripts perform.

**It is not malware.** Baseline is fully open-source. Every line of code is published on GitHub and is available for review before you run anything. There is no obfuscation, no network callbacks, no payload delivery, and no bundled binaries beyond Microsoft's own LGPO.exe.

**How to add an exclusion in Windows Defender.**

1. Open **Windows Security** and go to **Virus & threat protection**.
2. Under **Virus & threat protection settings**, click **Manage settings**.
3. Scroll down to **Exclusions** and click **Add or remove exclusions**.
4. Click **Add an exclusion**, select **Folder**, and browse to the directory where you extracted Baseline.

After adding the exclusion, Defender will stop flagging files inside that folder.

**Other antivirus products.** If you use a third-party security suite, check its documentation for adding a folder or process exclusion. The general approach is the same: exclude the Baseline directory so the AV engine does not interfere with script execution.

**If you prefer not to add exclusions.** You can review the source code on GitHub and run individual tweak functions manually through the Interactive session or headless execution. This lets you inspect and execute only the specific changes you are comfortable with.

---

### Which preset should I start with?

For most users, **Basic** is the recommended starting point. It applies low-risk cleanup and usability improvements without touching deeper system behavior.

If you are running Baseline in **Safe Mode** for the first time, start with **Minimal**. It is the most conservative preset and limits changes to small quality-of-life and maintenance tweaks.

**Balanced** is appropriate for enthusiasts who accept moderate tradeoffs across privacy, performance, and system configuration. A restore point is recommended before running Balanced.

**Advanced** is the expert preset. It includes feature removals, harder-to-reverse changes, and aggressive tuning. Only use Advanced after reviewing Preview Run output carefully, and only when you are comfortable with manual recovery if something conflicts with your setup.

| Preset | Recommended for | Summary |
| --- | --- | --- |
| Minimal | Safe Mode beginners | Most conservative first run |
| Basic | Most users and shared PCs | Low-risk cleanup and usability |
| Balanced | Enthusiasts who accept moderate tradeoffs | Broader privacy, performance, and system changes |
| Advanced | Experienced users only | Expert tuning, debloat, and hardening |

---

### Can I undo changes?

It depends on the change. Baseline provides several recovery mechanisms, but not every tweak is fully reversible.

- **Restore Snapshot** rolls back to the previous captured GUI state. This affects GUI selections only and does not undo any system changes that were already applied.
- **Restore to Windows Defaults** restores supported default values for tweaks that have a known default state. Not all tweaks have a documented Windows default.
- **Export Rollback Profile** is available from the post-run summary for tweaks that expose direct undo commands. This gives you a script you can run to reverse specific changes.
- **System Restore** is always an option if you created a restore point before running Baseline. This is strongly recommended before Balanced or Advanced runs.

Some changes, particularly uninstall and remove actions, do not have a direct undo path and may require manual recovery or a clean Windows installation. Preview Run surfaces this information before anything is applied, so review it carefully.

---

### What does Preview Run do?

Preview Run opens a structured review dialog that shows you exactly what will happen before any changes are made. It summarizes:

- how many tweaks are selected
- how many are already in the desired state
- how many will actually change
- how many are high-risk
- how many require a restart
- direct-undo coverage and which items are not restorable
- whether a restore point is recommended
- which categories are affected

No system changes are made during Preview Run. It is a read-only analysis of your current selections against the current system state.

---

### Does Baseline phone home or collect telemetry?

No. Baseline runs entirely locally. No analytics, telemetry, crash reports, or usage data are transmitted anywhere.

The only network requests Baseline can make are for optional package downloads (such as the Visual C++ Redistributable or .NET Desktop Runtime) that you explicitly trigger. Those downloads go directly to Microsoft's official distribution endpoints.

All log files are written to your local machine and stay there.

---

### A tweak failed. What should I try first?

1. Re-run Baseline as administrator. Many tweaks require elevated privileges.
2. Reboot and try again. Some changes depend on system state that only resets after a restart.
3. Review the Preview Run output to confirm the tweak is appropriate for your system.
4. Check the detailed log (accessible via **Open Log** in the GUI) for specific error messages.

If the issue persists, you can run the individual tweak function manually through the Interactive session to isolate the problem.

---

### Is Baseline safe to use on work, school, or domain-managed devices?

Baseline is designed for devices where you have local admin control. On managed, domain-enrolled, or organization-owned devices, Group Policy, MDM, or security software may conflict with Baseline's changes or revert them silently.

Review any planned changes with your IT administrator before running Baseline on a managed device.
