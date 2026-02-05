# Session Transfer Protocol — iSCSI Initiator for macOS

**Purpose:** This document captures the complete project state, architectural decisions, and context needed to continue development in a new Claude Code session. It serves as the authoritative handoff document.

**Last updated:** 2026-02-04

---

## 1. Project Identity

| Field | Value |
|-------|-------|
| **Project** | Native macOS iSCSI Initiator |
| **Path** | `/Volumes/turgay/projekte/iSCSITC/` |
| **Language** | German (docs), English (code) |
| **Code status** | No code exists yet — planning/specification phase only |
| **Target platforms** | macOS 14+ (Sonoma), Apple Silicon primary, Intel secondary |
| **Architecture** | DriverKit (C++20) + Swift 6.0 + Network.framework |

---

## 2. Document Inventory

### Primary Documents

| File | Description | Status |
|------|-------------|--------|
| `docs/iSCSI-Initiator-Entwicklungsplan.md` | Main development plan (v1.2, ~4285 lines) | Current — implementation-ready for Phase 1 |
| `docs/iSCSI-Initiator-Entwicklungsplan-v1.1.md` | Previous version (v1.1, ~650 lines) | Archived |
| `docs/iSCSI-Initiator-Entwicklungsplan-v1.2.md` | Backup copy of v1.2 | Archived |
| `docs/gap-analysis.md` | 52-gap analysis across 13 categories (P0-P3) | Current |
| `docs/testing-plan.md` | Testing strategy document | Current |
| `docs/session-transfer-protocol.md` | This file | Current |

### Implementation Guides (New - Feb 2026)

| File | Description | Lines | Status |
|------|-------------|-------|--------|
| `docs/development-environment-setup.md` | Complete dev environment setup guide | 1,304 | ✅ Complete |
| `docs/implementation-cookbook.md` | Code examples for all components (11 chapters) | 3,671 | ✅ Complete |
| `docs/testing-validation-guide.md` | Comprehensive testing strategy | 1,335 | ✅ Complete |
| `docs/deployment-distribution-guide.md` | Build, sign, notarize, distribute | 1,084 | ✅ Complete |

**Total Documentation**: ~11,679 lines across all guides

### Key Document Sections (v1.2 Entwicklungsplan)

| Section | Content | Lines (approx) |
|---------|---------|----------------|
| 1 | Project overview | 1-30 |
| 2 | Goals, Non-Goals, Assumptions | 31-80 |
| 3.1-3.3 | Architecture overview, components, data/control paths | 81-200 |
| **3.4** | DriverKit Extension — Detailed Specification (A1-A5) | 201-1086 |
| **3.5** | IPC Architecture — XPC + IOUserClient (B1-B3) | 1087-1510 |
| **3.6** | DriverKit ↔ Daemon Data Path (E1-E3) | 1511-1959 |
| **3.7** | Network Layer Design — NWProtocolFramer (D2) | 1960-2152 |
| **3.8** | FSKit Decision — Removed, DiskArbitration instead (K1) | 2153-2232 |
| 4.1-4.3 | PDU types table, SCSI commands enum, auth basics | 2233-2290 |
| **4.4** | PDU Binary Layout — All 17 types (C1) | 2291-2757 |
| **4.5** | Login State Machine — 5 states (C2) | 2758-2982 |
| **4.6** | Session Negotiation Parameters (C3) | 2983-3189 |
| **4.7** | Sequence Number Management (C4) | 3190-3375 |
| **4.8** | R2T and Data Transfer Protocol (C5) | ~3376-3638 |
| **4.9** | CHAP-Authentifizierung (C6) | ~3640-3780 |
| **4.10** | Fehler-Recovery Level 0 (C7) | ~3781-3840 |
| 5 | Development phases (4 phases, 24-32 weeks) | ~3842-3960 |
| 6 | Technology stack table | ~3961-4010 |
| 7 | Effort estimates | ~4011-4060 |
| 8 | Risks and mitigations (High/Medium/Low) | ~4061-4110 |
| 9 | Security and compliance | ~4111-4140 |
| **9.1** | Keychain-Zugriffskonfiguration (J2) | ~4141-4210 |
| **9.2** | Konfigurationsschema (F1) | ~4211-4280 |
| 10 | Apple Developer requirements, entitlements | ~4281-4310 |
| **10.1** | Fehlerkategorien und Fehlerbehandlung (L1) | ~4311-4420 |
| 11 | Repository structure | ~4421-4500 |
| **11.1** | Build System Configuration (H1, H2) | ~4501-4670 |
| 12 | Definition of Done (MVP) | ~4671-4680 |
| **13** | Testmatrix / QA (I2, I3, M1) | ~4682-4750 |
| 14 | Meilenstein-Checkliste | ~4752-4790 |
| 15 | Ressourcen und Referenzen | ~4792-4820 |
| 16 | Kontakt und Community | ~4822-4830 |

Sections in **bold** were added or extended in v1.2 to resolve P0/P1/P2 gaps.

---

## 3. Architectural Decisions (Finalized)

### 3.1 Core Architecture

```
┌─────────────────────────────────────────────────────┐
│                    GUI App (SwiftUI)                 │
│                    CLI Tool (Swift)                  │
└──────────────────┬──────────────────────────────────┘
                   │ XPC (NSXPCConnection)
┌──────────────────▼──────────────────────────────────┐
│              iscsid Daemon (Swift)                   │
│  ┌──────────┐ ┌────────────┐ ┌───────────────────┐  │
│  │ Session  │ │  Protocol  │ │  Network Layer    │  │
│  │ Manager  │ │  Engine    │ │  (NWProtocolFramer)│  │
│  └──────────┘ └────────────┘ └───────────────────┘  │
└──────────────────┬──────────────────────────────────┘
                   │ IOUserClient (shared memory + ExternalMethod)
┌──────────────────▼──────────────────────────────────┐
│         iSCSIVirtualHBA.dext (DriverKit/C++20)      │
│    IOUserSCSIParallelInterfaceController subclass    │
└─────────────────────────────────────────────────────┘
                   │ SCSI subsystem
              Block device → DiskArbitration → Finder
```

### 3.2 Key Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Driver framework | DriverKit (not kext) | Apple's forward-looking approach, user-space safety |
| SCSI controller class | IOUserSCSIParallelInterfaceController | Only DriverKit class for SCSI HBAs |
| Virtual HBA matching | IOResources (not hardware match) | No physical hardware; IOResources always matches |
| Dext activation | OSSystemExtensionRequest from App | Standard Apple flow for system extensions |
| IPC: App/CLI ↔ Daemon | XPC via NSXPCConnection | Apple-recommended for inter-process communication |
| IPC: Daemon ↔ Dext | IOUserClient (ExternalMethod + shared memory) | Only way to communicate with dexts |
| Data path | Shared memory ring buffers | Performance: avoids per-I/O kernel transitions |
| Completion signaling | IODataQueueDispatchSource (dext→daemon), ExternalMethod (daemon→dext) | Apple-provided mechanisms |
| Network API | Network.framework with NWProtocolFramer | Modern, TLS-capable, no raw sockets needed |
| PDU framing | NWProtocolFramer custom implementation | Integrates with NWConnection lifecycle |
| FSKit | **Removed** — not needed | FSKit is for new filesystems; we expose a block device |
| File system mounting | DiskArbitration framework | Standard macOS block device → mount flow |
| Build system | Xcode project (7 targets) + SPM for libraries | DriverKit requires Xcode; SPM for pure Swift libs |
| Concurrency model | Swift actors (TaskTagMap, ISCSITaskState, etc.) | Swift 6.0 structured concurrency |
| Credential storage | macOS Keychain | Apple-recommended for secrets |

### 3.3 Performance Decisions

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Command Queue | 64KB shared memory (1024 × 64-byte descriptors) | Sufficient for typical I/O depth |
| Completion Queue | 64KB shared memory (1024 × 64-byte descriptors) | Matches command queue capacity |
| Data Buffer Pool | 64MB (256 × 256KB buffers) | Covers MaxBurstLength with room for concurrent I/O |
| MaxRecvDataSegmentLength | 65536 bytes | Balance between throughput and memory |
| TCP_NODELAY | true | Latency-sensitive protocol |
| TCP send/receive buffers | 256KB each | Adequate for high-throughput iSCSI |
| Dispatch queues (dext) | 3: Default, I/O (high priority), Auxiliary | WWDC 2020 recommended pattern |

---

## 4. Gap Resolution Status

### P0 (Blockers) — ALL 10 RESOLVED

| Gap | Description | Resolved In |
|-----|-------------|-------------|
| A1 | DriverKit method signatures | Section 3.4 — correct `.iig` with `UserProcessParallelTask` |
| A2 | Info.plist for dext | Section 3.4 — complete plist with IOResources matching |
| A3 | IOUserClient specification | Section 3.4 — 7 selectors, dispatch table, IODataQueueDispatchSource |
| A5 | Virtual HBA activation strategy | Section 3.4 — IOResources + OSSystemExtensionRequest |
| B1 | XPC protocol definitions | Section 3.5 — three `@objc` protocols with full Swift code |
| C1 | PDU binary layouts | Section 4.4 — byte-offset tables for all 17 PDU types |
| C2 | Login state machine | Section 4.5 — 5 states, transition table, Swift actor |
| C3 | Negotiation parameters | Section 4.6 — 14 negotiated + 7 declarative params |
| E1 | Shared memory layout | Section 3.6 — ring buffer design, descriptor structs |
| E2 | Completion signaling | Section 3.6 — ExternalMethod + IODataQueueDispatchSource |

### P1 (MVP Required) — 10/10 RESOLVED

| Gap | Description | Status |
|-----|-------------|--------|
| A4 | Dispatch queue architecture | Resolved — Section 3.4 |
| B2 | LaunchDaemon plist | Resolved — Section 3.5 |
| B3 | IOUserClient from daemon side | Resolved — Section 3.5 (DextConnector) |
| C4 | Sequence number management | Resolved — Section 4.7 |
| C5 | R2T protocol | Resolved — Section 4.8 |
| D2 | NWProtocolFramer | Resolved — Section 3.7 |
| E3 | Task tag mapping | Resolved — Section 3.6 (TaskTagMap actor) |
| H1 | Xcode project structure | Resolved — Section 11.1 |
| H2 | SPM vs Xcode | Resolved — Section 11.1 |
| K1 | FSKit decision | Resolved — Section 3.8 (removed, use DiskArbitration) |

### P2 (v1.0 Required) — 12/12 RESOLVED

| Gap | Description | Status |
|-----|-------------|--------|
| C6 | CHAP protocol exchange | Resolved — Section 4.9 |
| C7 | Error recovery levels | Resolved — Section 4.10 |
| D1 | Connection state machine | Resolved — Section 3.7 |
| D3 | Reconnection strategy | Resolved — Section 3.7 |
| F1 | Configuration file format | Resolved — Section 9.2 |
| H3 | Code signing / entitlements | Resolved — Section 11.1 |
| I1 | Mock infrastructure | Resolved — testing-plan.md Section 11 |
| J1 | Sandbox/App Group config | Resolved — Section 9.1 (via App Group) |
| J2 | Keychain access group | Resolved — Section 9.1 |
| J4 | System Extension approval | Resolved — Section 3.4.5 |
| L1 | Error code taxonomy | Resolved — Section 10.1 |
| M3 | Swift 6.0 concurrency | Partially — actors in 4.7, 3.6, 4.9 |

### Remaining Gaps (P3 — polish/future, not blocking)

C8, D4, D5, E4, F2, F3, G1-G4, H4, I2 (partial), I3 (partial), J3, K2, L2, L3, M1 (partial), M2, M4

---

## 5. Build Targets (7 Xcode Targets)

| # | Target | Type | Language | Bundle ID |
|---|--------|------|----------|-----------|
| 1 | iSCSIVirtualHBA | DriverKit System Extension | C++20 | com.opensource.iscsi.driver |
| 2 | iscsid | LaunchDaemon (command-line) | Swift | com.opensource.iscsi.daemon |
| 3 | ISCSIProtocol | SPM Library | Swift | — |
| 4 | ISCSINetwork | SPM Library | Swift | — |
| 5 | iSCSI Initiator | macOS App (SwiftUI) | Swift | com.opensource.iscsi.app |
| 6 | iscsiadm | CLI Tool | Swift | com.opensource.iscsi.cli |
| 7 | iSCSITests | XCTest Bundle | Swift | — |

**Dependency graph:** App → {ISCSIProtocol, Daemon via XPC}; Daemon → {ISCSIProtocol, ISCSINetwork, Dext via IOKit}; CLI → {Daemon via XPC}

---

## 6. Repository Structure

```
/Volumes/turgay/projekte/iSCSITC/
├── docs/
│   ├── iSCSI-Initiator-Entwicklungsplan.md  (v1.2, 4285 lines)
│   ├── iSCSI-Initiator-Entwicklungsplan-v1.1.md
│   ├── iSCSI-Initiator-Entwicklungsplan-v1.2.md
│   ├── gap-analysis.md
│   ├── testing-plan.md
│   └── session-transfer-protocol.md  (this file)
├── .claude/
│   └── settings.local.json  (tool permissions)
└── (no source code yet)
```

**Planned source structure** (from Section 11 of Entwicklungsplan):
```
Driver/iSCSIVirtualHBA/     — .iig, .cpp, Info.plist, Entitlements.plist
Daemon/iscsid/              — Swift daemon sources
Protocol/Sources/           — PDU/, SCSI/, Auth/, Session/, DataTransfer/
Protocol/Tests/             — Unit tests for protocol engine
Network/Sources/            — NWProtocolFramer, connection management
Network/Tests/              — Framer tests
App/iSCSI Initiator/        — SwiftUI app
CLI/iscsiadm/               — CLI tool with ArgumentParser
Installer/                  — pkg scripts, Distribution.xml
```

---

## 7. Development Phase Readiness

| Phase | Description | Doc Readiness | Next Step |
|-------|-------------|---------------|-----------|
| **Phase 1: Foundation** (8-10 weeks) | DriverKit dext, protocol engine basics, network layer | ~70% ready | Validate DriverKit APIs, then generate code |
| Phase 2: Core Functionality (8-10 weeks) | Full login, SCSI commands, CHAP, error handling | ~40% ready | Resolve P2 gaps (C6, C7, L1) first |
| Phase 3: Integration (6-8 weeks) | DiskArbitration, GUI, CLI | ~20% ready | Resolve P3 gaps (G1-G4, K2) |
| Phase 4: Release (2-4 weeks) | Docs, signing, distribution | ~15% ready | Resolve H3, H4, J3 |

---

## 8. Pre-Code-Generation Verification Checklist

Before starting Phase 1 implementation, verify these against current Apple documentation:

- [ ] **DriverKit API validation:** Confirm `IOUserSCSIParallelInterfaceController` method signatures match current SDK headers (`UserProcessParallelTask`, `UserInitializeController`, etc.)
- [ ] **Virtual HBA matching:** Verify `IOResources` matching works for a software-only dext (create minimal test dext)
- [ ] **IOUserClient prototype:** Verify `IOConnectMapMemory64` + `IODataQueueDispatchSource` works between dext and daemon
- [ ] **XPC compilation:** Confirm `@objc` protocol definitions compile with `NSXPCInterface` requirements
- [ ] **PDU layouts:** Cross-reference byte-offset tables against RFC 7143 Section 12
- [ ] **DriverKit entitlements:** Confirm Apple has granted the required entitlements (`com.apple.developer.driverkit`, `com.apple.developer.driverkit.transport.scsi`, etc.)
- [ ] **Xcode project:** Verify the 7-target structure builds with DriverKit SDK selection

---

## 9. Key References

| Reference | URL |
|-----------|-----|
| RFC 7143 (iSCSI Consolidated) | https://tools.ietf.org/html/rfc7143 |
| RFC 3720 (iSCSI Original) | https://tools.ietf.org/html/rfc3720 |
| DriverKit Documentation | https://developer.apple.com/documentation/driverkit |
| IOUserSCSIParallelInterfaceController | https://developer.apple.com/documentation/driverkit/iouserscsiparallelinterfacecontroller |
| Network.framework | https://developer.apple.com/documentation/network |
| DiskArbitration | https://developer.apple.com/documentation/diskarbitration |
| open-iscsi (Linux reference) | https://github.com/open-iscsi/open-iscsi |
| libiscsi | https://github.com/sahlberg/libiscsi |
| WWDC 2020: Modernize PCI and SCSI drivers | Apple Developer Videos |

---

## 10. Session Continuation Instructions

When starting a new Claude Code session for this project:

### Quick Start (For Contributors)

1. **Read this file first** to get full project context
2. **Follow the implementation guides in order:**
   - `docs/development-environment-setup.md` - Set up your development environment
   - `docs/implementation-cookbook.md` - Start implementing components with code examples
   - `docs/testing-validation-guide.md` - Test your implementation
   - `docs/deployment-distribution-guide.md` - Package and distribute

### Deep Dive (For Architects)

1. **Read `docs/gap-analysis.md`** for detailed gap descriptions and resolution status
2. **Read relevant sections of `docs/iSCSI-Initiator-Entwicklungsplan.md`** based on the task at hand (use the section index in this document's Section 2)
3. **Check the verification checklist** (Section 8) — items should be completed before writing production code
4. **Consult the planned repository structure** (Section 6) when creating source files

### Suggested First Implementation Tasks (Phase 1)

**Follow the Implementation Cookbook** (`docs/implementation-cookbook.md`):

1. **Environment Setup** (Chapter 1 of dev guide)
   - Create Xcode project with 7 targets
   - Configure build settings and entitlements
   - Install required tools (fio, iperf3, etc.)

2. **DriverKit Extension** (Chapter 2 of cookbook)
   - Implement `iSCSIVirtualHBA.iig` + `.cpp` skeleton
   - Implement `iSCSIUserClient.iig` + `.cpp`
   - Test extension loading

3. **XPC Communication** (Chapter 3 of cookbook)
   - Implement XPC protocols and daemon skeleton
   - Test daemon startup and XPC connectivity

4. **Protocol Engine** (Chapter 4 of cookbook)
   - Implement PDU parser/builder
   - Add unit tests

5. **Network Layer** (Chapter 5 of cookbook)
   - Implement NWProtocolFramer
   - Test TCP connectivity

6. **Login Flow** (Chapter 6 of cookbook)
   - Implement login state machine
   - Test login against MockISCSITarget

7. **Integration Testing** (testing-validation-guide.md)
   - Set up MockISCSITarget
   - Run integration tests
   - Test against real iSCSI target
