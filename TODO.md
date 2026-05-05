# Win11Optimizer Roadmap

Current status: **Beta** (v0.9.x). Core functionality is stable, directory structure is normalized, and state detection is functional.

## 🏁 Phase 1: v1.0 Polish (Current Focus)

- [ ] **Real Progress Tracking**: Replace the indeterminate progress bar with a granular percentage based on the number of selected tweaks.
- [ ] **Snapshot Management**:
  - [ ] Add a snapshot picker UI to the Restore tab.
  - [ ] Allow users to delete old snapshots to save space.
- [ ] **Dry Run Mode**: Implement a "Check for Issues" button that runs all logic with a `-WhatIf` equivalent, logging what *would* happen.
- [ ] **UI Refinement**:
  - [ ] Add a "Select All / Deselect All" button for each category tab.
  - [ ] Right-click context menu in Log for "Copy Line" and "Open Log Folder".
  - [ ] Information icons next to complex tweaks with tooltips explaining the risk/reward.

## 🛠️ Phase 2: Advanced Features

- [ ] **Export/Import Profiles**: Save current checkbox state to a JSON file and allow loading it later (useful for multi-machine deployments).
- [ ] **System Summary Panel**: Display OS version, Build number, RAM, and GPU info on the home tab.
- [ ] **New Tweak Candidates (Pending Safety Review)**:
  - [ ] MSI Mode for GPU IRQ (Gaming).
  - [ ] Disable Activity History / Timeline (Privacy).
  - [ ] Toggle Long Path support (DevTools).
  - [ ] Disable Windows Search indexing (Performance - Opt-in).

## 🏗️ Phase 3: Infrastructure & Distribution

- [ ] **Testing Suite**:
  - [ ] Add Pester tests for `Common.ps1` helper functions.
  - [ ] Add Pester tests for `StateDetector.ps1` to ensure accurate probing.
- [ ] **Signing & Release**:
  - [ ] Implement a GitHub Actions workflow to auto-build and attach a signed EXE to releases.
  - [ ] Create a dedicated `docs/` site using GitHub Pages for tweak explanations.

## 🚫 Won't Do (Non-Goals)

- ❌ Disable Windows Update / Defender (Safety violation).
- ❌ Remove Microsoft Store (Dependency violation).
- ❌ Touch Provisioned Appx packages (Update integrity risk).
- ❌ Auto-reboot without user confirmation.
- ❌ Include any form of telemetry or analytics.
