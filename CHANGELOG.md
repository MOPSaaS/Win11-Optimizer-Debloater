# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-04

### Added
- Initial release.
- WPF GUI with five tabs: Debloat, Performance, Gaming, Dev Tools, Privacy, plus live Log tab.
- One-click `Optimize Now` and granular `Apply Selected`.
- Snapshot-based revert system writing JSON to `C:\ProgramData\Win11Optimizer\backups`.
- Worker runspace keeps UI responsive; live colored log via Dispatcher.
- Idempotent registry / service / Appx / feature operations.
- Hard-coded protected-package guard prevents removing Gaming Services, Defender, Store, runtimes, or anti-cheat dependencies.
- Self-elevating `Launch.bat`.
- Build pipelines: PS2EXE wrapper and Inno Setup installer.
- GitHub Actions CI: parse-check + PSScriptAnalyzer.
