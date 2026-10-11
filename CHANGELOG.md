# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- ui-backend: remove shell/`exec` request paths; read Argo/Flux CRDs via `@kubernetes/client-node`
- Validate DNS-1123 names, namespace/repo/path allowlists; restrict CORS; add helmet + rate limiting
- Replace `git clone` shell-out with allowlisted HTTPS GitHub Contents fetch
- Read-only ServiceAccount RBAC for the UI backend

### Changed
- Benchmarks: N=3 median/min/max, `equal-10s` and `defaults` reconcile profiles, commit→ready metric
- Deletion recovery naming clarified (formerly labeled rollback)

### Added
- ui-backend unit tests for malicious input rejection, wired into CI

## [1.0.0] - 2026-10-10

### Added
- Side-by-side Argo CD v3 (Helm chart 9.0.0) and Flux 2 on a kind cluster
- CI benchmark for time-to-ready, self-heal, and recovery, with results in `docs/results.md`
- MIT license

### Changed
- Repository cleanup: no committed Terraform state or binaries
