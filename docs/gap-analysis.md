# Documentation Gap Analysis: iSCSI-Initiator-Entwicklungsplan.md

## Overview

The development plan at `docs/iSCSI-Initiator-Entwicklungsplan.md` is a German-language document covering architecture, protocol specs, phases, and tooling for a native macOS iSCSI Initiator (DriverKit + Swift + Network.framework). No code exists yet.

**Document version analyzed:** v1.2 (updated from v1.0 → v1.1 → v1.2)

**Current status (v1.2):** All 10 P0 gaps and 8 of 10 P1 gaps have been resolved. The document now contains ~4285 lines with detailed implementation specifications covering DriverKit, IPC, data flow, network layer, protocol engine, and build system. The document is now ~70% implementation-ready for Phase 1 code generation.

**Previous verdict (v1.1):** The document covers the "what" and "why" well (~85%) but provides only ~10-15% of the "how" detail needed for actual code generation. **52 specific gaps** were identified across 13 categories.

### v1.1 Changes (vs v1.0)

The v1.1 update added useful framing but resolved **zero technical gaps**:

| New in v1.1 | Value | Gaps Resolved |
|---|---|---|
| Section 2: Goals / Non-Goals / Assumptions | Clarifies scope (no iSER, no boot-from-iSCSI, no iSNS in v1.0) | 0 — framing only |
| Section 3.3: Data path vs. control path | Names the two paths conceptually | 0 — no implementation detail for E1/E2 |
| Section 4.3: Auth basics (CHAP, Keychain, TLS) | Acknowledges auth requirements | 0 — no CHAP protocol detail (C6), no Keychain schema (J2) |
| Section 9: Security & Compliance | Security principles (no plaintext secrets, minimal privileges, secure logging) | 0 — no sandbox config (J1), no access groups (J2), no hardened runtime (J3) |
| Section 12: Definition of Done (MVP) | Explicit acceptance criteria for MVP | 0 — validation criteria, not implementation detail |
| Minor: removed iOS 12+ from Network.framework, removed macOS 15.4+ from FSKit | Corrects misleading version pinning | 0 |

All 10 P0 and 10 P1 gaps remain fully open. The recommended action (add 10 new detailed sections) is unchanged.

---

## Gap Summary Table

| Category | Gaps | P0 | P1 | P2 | P3 |
|----------|------|----|----|----|----|
| A: DriverKit Extension | 5 | 3 | 1 | 0 | 0 |
| B: XPC/IPC Communication | 3 | 1 | 2 | 0 | 0 |
| C: iSCSI Protocol Engine | 8 | 3 | 2 | 2 | 1 |
| D: Network Layer | 5 | 0 | 1 | 2 | 2 |
| E: DriverKit ↔ User-Space Data Flow | 4 | 2 | 1 | 0 | 1 |
| F: Configuration/Persistence | 3 | 0 | 0 | 1 | 2 |
| G: GUI/CLI | 4 | 0 | 0 | 0 | 4 |
| H: Build System | 4 | 0 | 2 | 1 | 1 |
| I: Testing Strategy | 3 | 0 | 0 | 1 | 2 |
| J: Security Model | 4 | 0 | 0 | 3 | 1 |
| K: FSKit Integration | 2 | 0 | 1 | 0 | 1 |
| L: Error Handling | 3 | 0 | 0 | 1 | 2 |
| M: Performance/Concurrency | 4 | 0 | 0 | 1 | 3 |
| **Total** | **52** | **10** | **10** | **12** | **20** |

---

## P0 Gaps (Blockers — Must Resolve Before Any Code Generation)

### A1: Incorrect DriverKit Method Signatures (lines 201-211)
The C++ skeleton uses `SCSIParallelTaskStart` which does not exist. The correct API is `UserProcessParallelTask`. Additionally, 8 other required pure-virtual overrides are missing entirely:
- `UserInitializeController`, `UserStartController`, `UserStopController`
- `UserDoesHBASupportSCSIParallelFeature`, `UserReportHBAHighestLogicalUnitNumber`
- `UserReportInitiatorIdentifier`, `UserReportMaximumTaskCount`, `UserReportHBAConstraints`

Must also use `.iig` file format (not `.hpp`) for DriverKit interface definitions.

**Needed:** Complete `.iig` interface file with all pure virtual method signatures and their parameter types.

### A2: No Info.plist Configuration for dext Bundle (line 487)
File is listed in repo structure but has zero content. This is the most critical configuration file — without it, the dext never loads. Must include `CFBundleIdentifier`, `CFBundlePackageType=DEXT`, `IOKitPersonalities` with matching dictionary, `IOUserClass`, `IOProviderClass`.

**Critical sub-gap:** Since this is a VIRTUAL HBA (no physical hardware), the matching strategy is undefined. Must decide: `IOResources` match? Companion nub? Manual instantiation?

**Needed:** Complete Info.plist XML and explicit matching strategy decision.

### A3: No IOUserClient Subclass Specification (lines 485-486)
The IOUserClient is the ONLY communication path between dext and daemon. Missing:
- External method selector enumeration (kCreateSession, kCompleteSCSITask, kGetPendingTask, etc.)
- `IOUserClientMethodDispatch` table
- `CopyClientMemoryForType` memory type enumeration
- Notification mechanism (IODataQueueDispatchSource vs. polling vs. callback)
- Connection lifecycle

**Needed:** Complete selector enum, dispatch table, memory type constants, notification mechanism selection.

### A5: No Virtual HBA Loading/Activation Strategy
Not mentioned anywhere. How does a software-only SCSI HBA get instantiated by the system? This is prerequisite for Info.plist (A2), daemon startup, and user-facing installation flow.

**Needed:** Selection of activation mechanism with full rationale and implementation sketch.

### B1: No XPC Protocol Definitions (line 48)
Entire XPC layer is one word on an arrow in the architecture diagram. Three channels need full protocol definitions:
1. GUI App → Daemon (discovery, login/logout, session list, configuration, credentials)
2. CLI → Daemon (same or subset)
3. Daemon → GUI App (callbacks: session state changes, connection lost, target discovered)

**Needed:** Complete `@objc` protocol definitions for all three channels, data serialization format, Mach service name.

### C1: No Per-PDU Binary Layout Specification (lines 222-238)
The `BasicHeaderSegment` struct has structural errors (`dataSegmentLength` is 24-bit, not 32-bit). The `opcodeSpecific` field is shown as a generic blob but has entirely different layouts per PDU type. All 14+ PDU types need exact byte-offset tables.

**Needed:** Per-opcode byte-offset tables with field name, offset, size, type, byte order, and bit-field definitions.

### C2: No Login State Machine Definition (line 217, 517)
Mentioned as checklist item and filename but no definition of states, transitions, conditions, or PDU fields (CSG, NSG, T-bit, C-bit, Status-Class, ISID, TSIH).

**Needed:** State enumeration, transition table, per-state key-value pairs, error handling, timeout values.

### C3: No Session Negotiation Parameters
Not mentioned anywhere in 650 lines. RFC 7143 Section 13 defines ~30 operational parameters (MaxRecvDataSegmentLength, MaxBurstLength, FirstBurstLength, InitialR2T, ImmediateData, etc.) that MUST be negotiated during login. Without these, login cannot complete.

**Needed:** Complete parameter table with negotiation functions, defaults, ranges, scopes. Negotiation algorithm per type (Minimum, Maximum, OR, AND). Result structs.

### E1: No Shared Memory Layout (lines 98-100)
The dext↔daemon data path for SCSI commands is specified in three bullet points. Critical missing detail: how are SCSI commands and their data transferred? Options: IOConnectCallStructMethod per I/O (simple, slow), shared memory ring buffers (complex, fast), IODataQueueDispatchSource (Apple-provided).

**Needed:** Memory approach selection, command/completion descriptor structs, ring buffer layout, notification mechanism, data buffer pool design.

### E2: No Completion Signaling Mechanism
After the daemon receives an iSCSI response, how does it signal the dext to call `CompleteParallelTask`? No mechanism is defined.

**Needed:** Selected mechanism (external method call, shared memory ring, OSAction callback), implementation details for both sides.

---

## P1 Gaps (Required for MVP)

### A4: No Dispatch Queue Architecture
DriverKit dexts need separate queues for I/O processing and user client calls to avoid deadlocks. Methods must be annotated with `QUEUENAME()` in the `.iig` file.

### B2: No LaunchDaemon plist Content (line 498)
File listed but empty. Needs Label, ProgramArguments, MachServices, KeepAlive, RunAtLoad, install path decision.

### B3: No IOUserClient Communication Protocol from Daemon Side
Daemon-side IOKit C API calls (`IOServiceGetMatchingService`, `IOServiceOpen`, `IOConnectMapMemory64`, `IOConnectCallStructMethod`) are entirely undocumented.

### C4: No Sequence Number Management
Six sequence numbers (CmdSN, ExpCmdSN, MaxCmdSN, StatSN, ExpStatSN, DataSN) with initialization, increment, window, and wrap-around rules are missing.

### C5: No R2T (Ready to Transfer) Protocol Detail (line 259)
Write operations require R2T handling. Missing: R2T PDU parsing, Data-Out sequence generation, DataSN tracking, multiple outstanding R2Ts, interaction with negotiated parameters.

### D2: No Network.framework PDU Framing Pattern (lines 112-118)
TCP is a byte stream; iSCSI PDUs need framing. Must choose: NWProtocolFramer (recommended) or manual buffer accumulation. Neither is described.

### E3: No Task Tag Mapping
Two independent tag spaces (kernel SCSITaggedTaskIdentifier vs. iSCSI ITT) must be mapped. No data structure or algorithm defined.

### H1: No Xcode Project Structure (line 190)
5+ targets (dext, daemon, protocol lib, app, CLI) with inter-dependencies, DriverKit-specific build settings, target types, and bundle IDs are undefined.

### H2: SPM vs. Xcode Target Relationship (lines 478, 559)
DriverKit cannot be built with SPM. Must clarify which targets are SPM packages vs. Xcode targets.

### K1: FSKit Integration May Be Architectural Error (lines 85-87)
FSKit is for implementing NEW file systems. This project exposes a block device; existing file systems (APFS, HFS+) mount it via DiskArbitration. FSKit is likely unnecessary and should either be removed from the architecture or justified.

---

## P2 Gaps (Required for v1.0)

- **C6:** No CHAP protocol exchange detail (key-value pairs, MD5/SHA-256 computation)
- **C7:** No error recovery level specification (Level 0/1/2 decisions per phase)
- **D1:** No connection state machine definition
- **D3:** No reconnection strategy (backoff, retry count, session reinstatement)
- **F1:** No configuration file format or schema
- **H3:** No code signing configuration per target
- **I1:** No mock infrastructure for testing (MockISCSITarget, protocol abstractions)
- **J1:** No sandbox/App Group configuration for IPC
- **J2:** No Keychain access group specification
- **J4:** No System Extension approval flow (OSSystemExtensionRequest API)
- **L1:** No error code taxonomy
- **M3:** No Swift 6.0 concurrency model (actors, Sendable, async/await bridging)

---

## P3 Gaps (Polish/Future — 20 items)

C8 (task mgmt functions), D4 (TCP tuning), D5 (multipath detail), E4 (large I/O data path), F2 (auto-connect impl), F3 (discovery persistence), G1 (GUI views beyond example), G2 (app lifecycle), G3 (CLI argument parser), G4 (CLI interactive mode), H4 (CI/CD pipeline), I2 (test target environment), I3 (perf benchmarks), J3 (hardened runtime), K2 (DiskArbitration detail), L2 (user-facing error messages), L3 (recovery procedures per error), M1 (throughput targets), M2 (buffer sizes), M4 (memory management)

---

## Recommended Action — COMPLETED (v1.2)

The development plan document has been expanded with 11 new detailed specification sections. The v1.2 document at `docs/iSCSI-Initiator-Entwicklungsplan.md` now contains 4285 lines (up from 650 in v1.0).

### New Sections Added in v1.2

| Section | Title | Gaps Resolved | Lines |
|---------|-------|---------------|-------|
| 3.4 | DriverKit Extension - Detaillierte Spezifikation | A1, A2, A3, A4, A5 | ~886 |
| 3.5 | IPC-Architektur | B1, B2, B3 | ~424 |
| 3.6 | DriverKit ↔ Daemon Datenpfad | E1, E2, E3 | ~449 |
| 3.7 | Netzwerkschicht-Design | D2 (+D1, D3 partially) | ~193 |
| 3.8 | FSKit-Entscheidung | K1 | ~80 |
| 4.4 | PDU Binärlayout | C1 | ~467 |
| 4.5 | Login-Zustandsmaschine | C2 | ~225 |
| 4.6 | Session-Verhandlungsparameter | C3 | ~207 |
| 4.7 | Sequenznummern-Verwaltung | C4 | ~186 |
| 4.8 | R2T und Datentransfer-Protokoll | C5 | ~303 |
| 11.1 | Build-System-Konfiguration | H1, H2 | ~171 |

### P0/P1 Resolution Status

**P0 (10 gaps):** All 10 resolved
- A1: Correct `.iig` method signatures with `UserProcessParallelTask`
- A2: Complete Info.plist with IOResources matching for virtual HBA
- A3: IOUserClient subclass with 7 selectors, dispatch table, IODataQueueDispatchSource
- A5: IOResources matching strategy with OSSystemExtensionRequest flow
- B1: Three XPC protocol definitions with full Swift code
- C1: Per-opcode byte-offset tables for all 17 PDU types
- C2: 5-state login state machine with transition table and Swift actor
- C3: 14 negotiated + 7 declarative parameters with algorithms
- E1: Shared memory layout (Command Queue 64KB, Completion Queue 64KB, Data Buffer Pool 64MB)
- E2: Completion signaling via IOConnectCallStructMethod with ExternalMethod handler

**P1 (10 gaps):** 8 resolved, 2 partially addressed
- A4: Three-queue dispatch architecture (Default, I/O, Auxiliary)
- B2: Complete LaunchDaemon plist
- B3: DextConnector class with IOKit C API calls
- C4: All 7 sequence numbers with RFC 1982 arithmetic
- C5: R2T protocol with Data-Out generation and ISCSITaskState actor
- D2: NWProtocolFramer implementation for PDU framing
- E3: TaskTagMap actor with bidirectional ITT <-> kernel tag mapping
- H1: 7-target Xcode project structure with dependency graph
- H2: SPM vs Xcode decision matrix with Package.swift
- K1: FSKit removed, DiskArbitration data path documented

### All P2 gaps resolved

| Gap | Description | Resolution |
|-----|-------------|------------|
| C6 | CHAP protocol exchange | Section 4.9 — CHAP_A/I/C/N/R flow, response computation, bidirectional CHAP |
| C7 | Error recovery levels | Section 4.10 — Level 0 procedure, timeout values, escalation logic |
| D1 | Connection state machine | Section 3.7 — 9 states, 17 transitions |
| D3 | Reconnection strategy | Section 3.7 — exponential backoff |
| F1 | Configuration file format | Section 9.2 — targets.json schema, DaemonConfiguration |
| H3 | Code signing / entitlements | Section 11.1 — per-target entitlements |
| I1 | Mock infrastructure | testing-plan.md Section 11 — MockISCSITarget, MockTransport, TestFixtures |
| J1 | Sandbox/App Group config | Section 9.1 — App Group com.opensource.iscsi |
| J2 | Keychain access groups | Section 9.1 — kSecAttrAccessGroup, KeychainManager actor |
| J4 | System Extension approval | Section 3.4.5 — OSSystemExtensionRequest flow |
| L1 | Error code taxonomy | Section 10.1 — ISCSIError enum (6 categories, 30+ error codes) |
| M3 | Swift 6.0 concurrency | Partially — actors in 4.7, 3.6, 4.9; full Sendable conformance |

### P3 gaps resolved or partially addressed

| Gap | Description | Status |
|-----|-------------|--------|
| I2 | Test target environment | Partially — Testmatrix dimensions (Section 13) + testing-plan.md |
| I3 | Performance benchmarks | Partially — Performance targets (Section 13) + testing-plan.md FIO profiles |
| M1 | Throughput targets | Partially — Quantitative targets in Section 13 Performance-Ziele |

### Remaining gaps (P3 — polish/future, not blocking implementation)
- C8: Task management functions
- D4: TCP tuning details
- D5: Multipath detail
- E4: Large I/O data path optimization
- F2: Auto-connect implementation
- F3: Discovery persistence
- G1-G4: GUI/CLI polish
- H4: CI/CD pipeline
- J3: Hardened runtime details
- K2: DiskArbitration detail
- L2: User-facing error messages
- L3: Recovery procedures per error
- M2: Buffer size tuning
- M4: Memory management details

## Verification (Recommended before code generation)

1. Validate DriverKit method signatures against Apple's current IOUserSCSIParallelInterfaceController documentation
2. Validate PDU layouts against RFC 7143 Section 12
3. Verify the virtual HBA matching strategy works by creating a minimal test dext
4. Confirm XPC protocol compiles with NSXPCInterface requirements (@objc, Foundation types)
5. Verify the selected shared memory approach works with a DriverKit IOUserClient prototype
