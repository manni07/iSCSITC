# iSCSI Initiator für macOS (Apple Silicon)
## Entwicklungsplan - Option B: Swift/DriverKit Native Implementation

**Version:** 1.2
**Datum:** 4. Februar 2026
**Autor:** Open Source Projekt
**Lizenz:** MIT (vorgeschlagen)

---

## 1. Executive Summary

Entwicklung eines vollständig nativen iSCSI-Initiators für macOS mit Fokus auf Apple Silicon (M1/M2/M3/M4). Die Lösung nutzt moderne Apple-Frameworks (DriverKit, FSKit, Network.framework) und wird als Open-Source-Projekt veröffentlicht.

### Warum dieses Projekt?

| Problem | Lösung |
|---------|--------|
| Keine kostenlosen iSCSI-Initiatoren für Apple Silicon | Open-Source-Alternative |
| Alte Kext-basierte Lösungen funktionieren nicht mehr | Moderne DriverKit/FSKit-Architektur |
| ATTO Xtend SAN kostet $195 | Kostenlose Community-Lösung |
| libiscsi kompiliert nicht auf macOS 15+ | Native Swift-Implementierung |

### Zielbild (Kurz)
- Ein System-Extension-basierter iSCSI-Initiator (kein Kext)
- CLI + GUI + Daemon als vollständiges Tooling
- Fokus auf Stabilität, Interoperabilität und einfache Installation

---

## 2. Ziele, Nicht-Ziele und Annahmen

### Ziele
- Vollständig native iSCSI-Implementierung in Swift (Protokoll + Session-Management)
- DriverKit-basierte virtuelle SCSI-HBA
- Benutzerfreundliche Konfiguration (GUI + CLI)
- Solide Interoperabilität mit gängigen NAS/Targets

### Nicht-Ziele (Version 1.0)
- iSER (RDMA)
- Boot from iSCSI
- Vollständige iSNS-Unterstützung
- Hochverfügbarkeit über komplexes Multipath-Policy-Management

### Annahmen
- Apple DriverKit Entitlements sind erhältlich
- Netzwerkzugriff erfolgt über User Space (Network.framework)
- Der Projektfokus liegt auf macOS 13+ mit Best-Effort für macOS 12

---

## 3. Technische Architektur

### 3.1 Architektur-Übersicht

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Space                                │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │   GUI App       │    │   CLI Tool      │    │  Preferences│ │
│  │   (SwiftUI)     │◄──►│   (iscsiadm)    │◄──►│  Daemon     │ │
│  └────────┬────────┘    └────────┬────────┘    └──────┬──────┘ │
│           │                      │                     │        │
│           └──────────────────────┼─────────────────────┘        │
│                                  ▼                              │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              iSCSI Control Daemon (iscsid)                 │ │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐   │ │
│  │  │ Discovery   │  │ Session Mgmt │  │ Error Handling  │   │ │
│  │  │ (SendTarget)│  │ Login/Logout │  │ Reconnection    │   │ │
│  │  └─────────────┘  └──────────────┘  └─────────────────┘   │ │
│  └───────────────────────────┬───────────────────────────────┘ │
│                              │ XPC                              │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │           Network Extension / Helper                       │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │         iSCSI Protocol Engine (Swift)                │  │ │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐  │  │ │
│  │  │  │ PDU     │  │ SCSI    │  │ Task    │  │ CHAP   │  │  │ │
│  │  │  │ Layer   │  │ Layer   │  │ Mgmt    │  │ Auth   │  │  │ │
│  │  │  └─────────┘  └─────────┘  └─────────┘  └────────┘  │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  │                           │                                │ │
│  │                           ▼                                │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │         Network.framework (TCP/IP)                   │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │ IOUserClient                     │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              DriverKit Extension (dext)                    │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │    IOUserSCSIParallelInterfaceController            │  │ │
│  │  │    - SCSI Command Processing                        │  │ │
│  │  │    - LUN Management                                 │  │ │
│  │  │    - Virtual HBA Emulation                          │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                        Kernel Space                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐ │
│  │    IOSCSIParallelFamily (Apple Kernel Framework)          │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              FSKit / DiskArbitration                       │ │
│  │              (Block Device & Filesystem Mount)             │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Komponentenbeschreibung

#### A) DriverKit Extension (dext) - Kern des Systems
- **Zweck:** Stellt virtuelle SCSI-HBA für das System bereit
- **Framework:** `IOUserSCSIParallelInterfaceController`
- **Sprache:** C++ (DriverKit-Anforderung)
- **Funktionen:**
  - SCSI-Befehle entgegennehmen
  - An User-Space-Daemon weiterleiten
  - Antworten zurück an Kernel liefern

#### B) iSCSI Control Daemon (iscsid)
- **Zweck:** Zentrale Steuerung aller iSCSI-Operationen
- **Sprache:** Swift
- **Funktionen:**
  - Target Discovery (SendTargets)
  - Session Management
  - Login/Logout-Verarbeitung
  - Fehlerbehandlung & Reconnection
  - Konfigurationsverwaltung

#### C) Network Layer
- **Zweck:** TCP/IP-Kommunikation mit iSCSI-Target (Standardport 3260)
- **Framework:** Network.framework (Apple)
- **Funktionen:**
  - TCP-Verbindungsmanagement
  - TLS-Unterstützung (optional)
  - Multipath I/O (optional)

#### D) iSCSI Protocol Engine
- **Zweck:** RFC 3720 Implementierung
- **Sprache:** Swift
- **Funktionen:**
  - PDU Encoding/Decoding
  - SCSI CDB Verarbeitung
  - Task Management
  - CHAP-Authentifizierung

#### E) GUI Application
- **Zweck:** Benutzerfreundliche Konfiguration
- **Framework:** SwiftUI
- **Funktionen:**
  - Target-Verwaltung
  - Verbindungsstatus
  - Automatische Verbindung bei Login

### 3.3 Datenpfad vs. Steuerpfad
- **Datenpfad:** SCSI I/O (READ/WRITE) über DriverKit -> User Space -> TCP
- **Steuerpfad:** Discovery, Login, Session-Management über `iscsid`

---

## 4. iSCSI Protokoll-Implementierung (RFC 3720)

### 4.1 PDU-Typen (Protocol Data Units)

| PDU Type | Code | Richtung | Priorität |
|----------|------|----------|-----------|
| NOP-Out | 0x00 | I→T | Phase 1 |
| NOP-In | 0x20 | T→I | Phase 1 |
| SCSI Command | 0x01 | I→T | Phase 1 |
| SCSI Response | 0x21 | T→I | Phase 1 |
| Task Mgmt Request | 0x02 | I→T | Phase 2 |
| Task Mgmt Response | 0x22 | T→I | Phase 2 |
| Login Request | 0x03 | I→T | Phase 1 |
| Login Response | 0x23 | T→I | Phase 1 |
| Text Request | 0x04 | I→T | Phase 1 |
| Text Response | 0x24 | T→I | Phase 1 |
| Data-Out | 0x05 | I→T | Phase 1 |
| Data-In | 0x25 | T→I | Phase 1 |
| Logout Request | 0x06 | I→T | Phase 1 |
| Logout Response | 0x26 | T→I | Phase 1 |
| SNACK Request | 0x10 | I→T | Phase 3 |
| Reject | 0x3f | T→I | Phase 2 |
| Async Message | 0x32 | T→I | Phase 2 |

### 4.2 SCSI-Befehle (Mindestumfang)

```swift
enum SCSICommand: UInt8 {
    case testUnitReady     = 0x00
    case requestSense      = 0x03
    case read6             = 0x08
    case write6            = 0x0A
    case inquiry           = 0x12
    case modeSelect6       = 0x15
    case modeSense6        = 0x1A
    case readCapacity10    = 0x25
    case read10            = 0x28
    case write10           = 0x2A
    case read16            = 0x88
    case write16           = 0x8A
    case reportLuns        = 0xA0
}
```

### 4.3 Sicherheits- und Auth-Details (Basis)
- CHAP (uni- und bidirektional)
- Keychain als Credential Store
- Optional: TLS (wenn Target dies unterstützt)

---

## 5. Entwicklungsphasen

### Phase 1: Foundation (8-10 Wochen)

#### Milestone 1.1: Projekt-Setup (1 Woche)
- [ ] Xcode-Projekt mit allen Targets erstellen
- [ ] DriverKit Entitlements beantragen (Apple Developer Account)
- [ ] CI/CD Pipeline (GitHub Actions)
- [ ] Dokumentations-Framework aufsetzen

#### Milestone 1.2: DriverKit Extension Grundgerüst (3 Wochen)
- [ ] IOUserSCSIParallelInterfaceController Subklasse
- [ ] IOUserClient für User-Space-Kommunikation
- [ ] Basic SCSI Command Routing
- [ ] Installation/Aktivierung testen

```cpp
// Beispiel: DriverKit Extension Header
class iSCSIVirtualHBA : public IOUserSCSIParallelInterfaceController {
public:
    virtual bool init() override;
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;
    virtual void SCSIParallelTaskStart(
        IOUserSCSIParallelTaskReference task,
        OSAction* completion) override;
};
```

#### Milestone 1.3: iSCSI Protocol Engine (4 Wochen)
- [ ] PDU Parser/Builder
- [ ] Basic Header Segment (BHS) Handling
- [ ] Login Phase Implementation
- [ ] Text Negotiation (SendTargets)

```swift
// Beispiel: PDU Structure
struct ISCSIPdu {
    var bhs: BasicHeaderSegment  // 48 Bytes
    var ahs: [AdditionalHeaderSegment]?
    var headerDigest: UInt32?
    var dataSegment: Data?
    var dataDigest: UInt32?
}

struct BasicHeaderSegment {
    var opcode: UInt8
    var flags: UInt8
    var totalAHSLength: UInt8
    var dataSegmentLength: UInt32  // 24-bit
    var lun: UInt64
    var initiatorTaskTag: UInt32
    var opcodeSpecific: Data  // 28 Bytes
}
```

#### Milestone 1.4: Network Layer (2 Wochen)
- [ ] TCP-Verbindung mit Network.framework
- [ ] Connection State Machine
- [ ] Reconnection Logic

### Phase 2: Core Functionality (8-10 Wochen)

#### Milestone 2.1: Full Login Sequence (2 Wochen)
- [ ] Security Negotiation
- [ ] Operational Negotiation
- [ ] Full Feature Phase Transition
- [ ] Multi-Connection Session (optional)

#### Milestone 2.2: SCSI Command Processing (4 Wochen)
- [ ] READ/WRITE Commands
- [ ] INQUIRY, READ CAPACITY
- [ ] Request Sense
- [ ] Data-In/Data-Out Handling
- [ ] R2T (Ready to Transfer) Support

#### Milestone 2.3: CHAP Authentication (2 Wochen)
- [ ] Unidirectional CHAP
- [ ] Bidirectional CHAP
- [ ] Secure Credential Storage (Keychain)

#### Milestone 2.4: Error Handling (2 Wochen)
- [ ] Connection Recovery
- [ ] Session Recovery
- [ ] Task Retry Logic
- [ ] Timeout Management

### Phase 3: Integration & Polish (6-8 Wochen)

#### Milestone 3.1: System Integration (2 Wochen)
- [ ] DiskArbitration Integration
- [ ] Automount bei Login
- [ ] Spotlight/Time Machine Kompatibilität

#### Milestone 3.2: GUI Application (3 Wochen)
- [ ] SwiftUI Hauptfenster
- [ ] Target Discovery UI
- [ ] Connection Status Dashboard
- [ ] Preferences Panel
- [ ] Menu Bar App (optional)

```swift
// Beispiel: SwiftUI Target View
struct TargetListView: View {
    @ObservedObject var manager: ISCSIManager

    var body: some View {
        List(manager.targets) { target in
            TargetRow(target: target)
                .contextMenu {
                    Button("Connect") { manager.connect(target) }
                    Button("Disconnect") { manager.disconnect(target) }
                }
        }
    }
}
```

#### Milestone 3.3: CLI Tool (1 Woche)
- [ ] iscsiadm-kompatible Syntax
- [ ] Discovery Mode
- [ ] Node Mode
- [ ] Session Mode

```bash
# Geplante CLI-Syntax
iscsiadm -m discovery -t sendtargets -p 192.168.1.109
iscsiadm -m node -T iqn.2024-01.com.nas:macmini -p 192.168.1.109 --login
iscsiadm -m session
```

#### Milestone 3.4: Testing & QA (2 Wochen)
- [ ] Unit Tests für Protocol Engine
- [ ] Integration Tests mit echtem Target
- [ ] Performance Benchmarks
- [ ] Stress Tests

### Phase 4: Release Preparation (2-4 Wochen)

#### Milestone 4.1: Dokumentation (1 Woche)
- [ ] README.md
- [ ] Installation Guide
- [ ] API Documentation
- [ ] Troubleshooting Guide

#### Milestone 4.2: Distribution (1 Woche)
- [ ] Notarization bei Apple
- [ ] DMG Installer
- [ ] Homebrew Formula
- [ ] GitHub Release

#### Milestone 4.3: Community (2 Wochen)
- [ ] Contributing Guidelines
- [ ] Issue Templates
- [ ] Community Engagement

---

## 6. Technologie-Stack

### Entwicklung

| Komponente | Technologie | Version |
|------------|-------------|---------|
| IDE | Xcode | 16.0+ |
| Sprache (App) | Swift | 6.0 |
| Sprache (Driver) | C++ | C++20 |
| UI Framework | SwiftUI | 6.0 |
| Network | Network.framework | - |
| Driver | DriverKit | - |
| Filesystem | FSKit | - |
| Build | Swift Package Manager | - |
| CI/CD | GitHub Actions | - |

### Unterstützte Plattformen

| macOS Version | Unterstützung | Anmerkung |
|---------------|---------------|-----------|
| macOS 15 (Sequoia) | ✅ Voll | FSKit + DriverKit |
| macOS 14 (Sonoma) | ✅ Voll | DriverKit |
| macOS 13 (Ventura) | ⚠️ Eingeschränkt | Ältere APIs |
| macOS 12 (Monterey) | ❓ Experimentell | Minimale Unterstützung |

### Hardware

| Architektur | Unterstützung |
|-------------|---------------|
| Apple Silicon (arm64) | ✅ Primär |
| Intel (x86_64) | ✅ Sekundär |

---

## 7. Aufwandsschätzung

### Zeitaufwand (Einzelentwickler, Vollzeit)

| Phase | Wochen | Stunden |
|-------|--------|---------|
| Phase 1: Foundation | 8-10 | 320-400 |
| Phase 2: Core Functionality | 8-10 | 320-400 |
| Phase 3: Integration | 6-8 | 240-320 |
| Phase 4: Release | 2-4 | 80-160 |
| **Gesamt** | **24-32** | **960-1280** |

### Aufwand nach Komponente

```
DriverKit Extension     ████████████████████ 25%
iSCSI Protocol Engine   ████████████████████████████ 35%
Network Layer           ████████ 10%
GUI Application         ████████████ 15%
CLI Tool                ████ 5%
Testing & QA            ████████ 10%
```

### Team-Szenario (3 Entwickler)

| Phase | Wochen |
|-------|--------|
| Phase 1-2 parallel | 6-8 |
| Phase 3 | 4-6 |
| Phase 4 | 2-3 |
| **Gesamt** | **12-17** |

---

## 8. Risiken und Herausforderungen

### Hohe Risiken

| Risiko | Beschreibung | Mitigation |
|--------|--------------|------------|
| **DriverKit Socket-Limitation** | DriverKit hat keinen direkten Socket-Zugriff | User-Space Helper mit Network.framework |
| **Apple Developer Entitlements** | DriverKit erfordert spezielle Entitlements | Frühzeitig beantragen, Fallback planen |
| **Signierung & Notarization** | Unsigned Drivers werden nicht geladen | Apple Developer Program ($99/Jahr) |

### Mittlere Risiken

| Risiko | Beschreibung | Mitigation |
|--------|--------------|------------|
| **Performance User-Space** | Overhead durch User/Kernel-Transition | Optimiertes Buffer-Management |
| **iSCSI Interoperabilität** | Verschiedene NAS-Implementierungen | Breites Testing (Synology, QNAP, TrueNAS) |
| **macOS Updates** | API-Änderungen in neuen Versionen | Beta-Testing, modulare Architektur |

### Niedrige Risiken

| Risiko | Beschreibung | Mitigation |
|--------|--------------|------------|
| **RFC 3720 Komplexität** | Umfangreiche Spezifikation | Inkrementelle Implementierung |
| **Community Adoption** | Wenig Interesse | Marketing, Dokumentation |

---

## 9. Sicherheits- und Compliance-Anforderungen

### Sicherheitsziele
- Geheimnisse nie im Klartext speichern
- Minimale Angriffsfläche (kleinere Privilegien, klare Grenzen)
- Sicheres Logging (keine Credentials in Logs)

### Credential Handling
- Speicherung in der macOS Keychain
- Zugriff nur über den Daemon
- GUI/CLI kommunizieren ausschließlich über XPC

### Code Signing & Notarization
- Signierte System Extensions
- Notarization in CI/CD
- Prüfsummen/Signaturen für Releases

---

## 10. Apple Developer Anforderungen

### Erforderliche Entitlements

```xml
<!-- DriverKit Entitlements -->
<key>com.apple.developer.driverkit</key>
<true/>
<key>com.apple.developer.driverkit.transport.scsi</key>
<true/>
<key>com.apple.developer.driverkit.family.scsi-parallel</key>
<true/>
<key>com.apple.developer.driverkit.userclient-access</key>
<true/>

<!-- Network Extension (falls benötigt) -->
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>app-proxy-provider</string>
</array>
```

### Beantragungsprozess

1. Apple Developer Program beitreten ($99/Jahr)
2. DriverKit Entitlement beantragen (Formular)
3. Warten auf Apple-Genehmigung (1-4 Wochen)
4. Provisioning Profile erstellen
5. Code signieren und notarisieren

---

## 11. Projekt-Repository-Struktur

```
iscsi-initiator-macos/
├── README.md
├── LICENSE (MIT)
├── CONTRIBUTING.md
├── CHANGELOG.md
├── Package.swift
├── Makefile
│
├── Driver/
│   ├── iSCSIVirtualHBA/
│   │   ├── iSCSIVirtualHBA.cpp
│   │   ├── iSCSIVirtualHBA.hpp
│   │   ├── iSCSIUserClient.cpp
│   │   ├── iSCSIUserClient.hpp
│   │   ├── Info.plist
│   │   └── Entitlements.plist
│   └── iSCSIVirtualHBA.dext/
│
├── Daemon/
│   ├── iscsid/
│   │   ├── main.swift
│   │   ├── ISCSIDaemon.swift
│   │   ├── SessionManager.swift
│   │   ├── DiscoveryService.swift
│   │   └── ConfigurationStore.swift
│   └── com.opensource.iscsid.plist
│
├── Protocol/
│   ├── Sources/
│   │   ├── PDU/
│   │   │   ├── BasicHeaderSegment.swift
│   │   │   ├── PDUParser.swift
│   │   │   ├── PDUBuilder.swift
│   │   │   └── PDUTypes.swift
│   │   ├── SCSI/
│   │   │   ├── SCSICommand.swift
│   │   │   ├── SCSIResponse.swift
│   │   │   └── SCSIStatus.swift
│   │   ├── Auth/
│   │   │   ├── CHAPAuthenticator.swift
│   │   │   └── KeychainManager.swift
│   │   └── Session/
│   │       ├── ISCSISession.swift
│   │       ├── ISCSIConnection.swift
│   │       └── LoginStateMachine.swift
│   └── Tests/
│       ├── PDUTests.swift
│       ├── SCSITests.swift
│       └── SessionTests.swift
│
├── Network/
│   ├── Sources/
│   │   ├── TCPConnection.swift
│   │   ├── ConnectionPool.swift
│   │   └── NetworkMonitor.swift
│   └── Tests/
│
├── App/
│   ├── iSCSI Initiator/
│   │   ├── iSCSI_InitiatorApp.swift
│   │   ├── Views/
│   │   │   ├── MainView.swift
│   │   │   ├── TargetListView.swift
│   │   │   ├── DiscoveryView.swift
│   │   │   ├── SettingsView.swift
│   │   │   └── StatusBarView.swift
│   │   ├── ViewModels/
│   │   │   ├── ISCSIManager.swift
│   │   │   └── TargetViewModel.swift
│   │   ├── Models/
│   │   │   ├── Target.swift
│   │   │   └── Connection.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Localizable.strings
│   └── Info.plist
│
├── CLI/
│   ├── iscsiadm/
│   │   ├── main.swift
│   │   ├── Commands/
│   │   │   ├── DiscoveryCommand.swift
│   │   │   ├── NodeCommand.swift
│   │   │   └── SessionCommand.swift
│   │   └── Output/
│   │       └── Formatter.swift
│   └── Package.swift
│
├── Installer/
│   ├── Scripts/
│   │   ├── postinstall
│   │   └── preinstall
│   ├── Resources/
│   └── Distribution.xml
│
└── Docs/
    ├── architecture.md
    ├── installation.md
    ├── configuration.md
    ├── troubleshooting.md
    └── api/
```

---

## 12. Definition of Done (MVP)

- [ ] DriverKit Extension lädt zuverlässig und übersteht Reboots
- [ ] Discovery & Login gegen mindestens ein reales Target
- [ ] READ/WRITE erfolgreich bei einem Blockdevice
- [ ] Volume erscheint stabil in Finder/Disk Utility
- [ ] CLI unterstützt Discovery, Login, Session-Status
- [ ] Basisdokumentation vorhanden

---


## 13. Testmatrix (Qualitätssicherung)

### Ziel
Sicherstellen, dass der Initiator stabil, interoperabel und performant über relevante Zielplattformen hinweg funktioniert.

### Dimensionen der Testabdeckung
- Betriebssystem: macOS 15, 14, 13, 12
- Hardware: Apple Silicon (M1, M2, M3, M4) und Intel (x86_64)
- Targets: Synology, QNAP, TrueNAS, Linux LIO, Windows iSCSI Target
- Auth: Keine, CHAP unidirektional, CHAP bidirektional
- Netzwerk: 1 GbE, 2.5 GbE, 10 GbE, Latenz/Packet Loss Simulation
- Features: Discovery, Login, READ/WRITE, Reconnect, Automount

### Basis-Testmatrix (MVP)

| Bereich | Variationen | Erwartung | Priorität |
|---------|-------------|-----------|-----------|
| Discovery | SendTargets gegen 3 Targets | Targets werden korrekt gefunden | Hoch |
| Login | Ohne Auth und mit CHAP | Session wird stabil aufgebaut | Hoch |
| I/O | READ/WRITE mit 4K/64K/1M | Konsistente Daten, keine Timeouts | Hoch |
| Reconnect | Link Drop / Interface Switch | Automatisches Recovery | Mittel |
| Sleep/Wake | macOS Sleep/Wake | Session-Recovery, keine Kernel-Hänger | Mittel |
| Filesystem | APFS, HFS+ | Mount/Unmount stabil | Mittel |
| Performance | Sequentiell vs. Random | Baseline-Performance dokumentiert | Niedrig |

### Interoperabilitäts-Suite (Empfohlen)

| Target | Auth | Erwartung |
|--------|------|-----------|
| Synology DSM 7.x | CHAP | Stabile Session + I/O |
| QNAP QTS 5.x | CHAP | Stabile Session + I/O |
| TrueNAS SCALE | Keine/CHAP | Stabile Session + I/O |
| Linux LIO | Keine/CHAP | Stabile Session + I/O |
| Windows iSCSI | Keine/CHAP | Stabile Session + I/O |

### Negative Tests
- Falsche CHAP Credentials
- Target nicht erreichbar / Port 3260 blockiert
- Abbruch während Data-Out
- Simulierter Session-Timeout

### Tooling und Automatisierung
- Unit-Tests: PDU-Parser, State-Machine, CHAP
- Integration-Tests: Scripted I/O gegen Test-Targets
- Performance: FIO-Profile (sequentiell/random)
- Logging: strukturierte Logs, anonymisierte Dumps

## 14. Meilenstein-Checkliste

### MVP (Minimum Viable Product) - 16 Wochen

- [ ] DriverKit Extension lädt erfolgreich
- [ ] Target Discovery funktioniert
- [ ] Login zu einem Target möglich
- [ ] READ/WRITE Befehle funktionieren
- [ ] Volume wird im Finder angezeigt
- [ ] CLI-Tool für Basis-Operationen

### Version 1.0 - 24-32 Wochen

- [ ] Alles aus MVP
- [ ] CHAP-Authentifizierung
- [ ] GUI-Anwendung
- [ ] Automatische Verbindung
- [ ] Error Recovery
- [ ] Dokumentation
- [ ] Notarized Installer

### Version 2.0 (Zukunft)

- [ ] Multipath I/O
- [ ] iSER (iSCSI Extensions for RDMA)
- [ ] Boot from iSCSI
- [ ] Header/Data Digest
- [ ] Multiple Connections per Session

---

## 15. Ressourcen und Referenzen

### Spezifikationen

- [RFC 3720 - iSCSI](https://tools.ietf.org/html/rfc3720)
- [RFC 3721 - iSCSI Naming](https://tools.ietf.org/html/rfc3721)
- [RFC 3722 - iSCSI String Profile](https://tools.ietf.org/html/rfc3722)
- [RFC 3723 - iSCSI Security](https://tools.ietf.org/html/rfc3723)
- [RFC 7143 - iSCSI Consolidated](https://tools.ietf.org/html/rfc7143)

### Apple Dokumentation

- [DriverKit Documentation](https://developer.apple.com/documentation/driverkit)
- [IOUserSCSIParallelInterfaceController](https://developer.apple.com/documentation/driverkit/iouserscsiparallelinterfacecontroller)
- [Network.framework](https://developer.apple.com/documentation/network)
- [FSKit Framework](https://developer.apple.com/documentation/fskit)

### Open Source Referenzen

- [open-iscsi (Linux)](https://github.com/open-iscsi/open-iscsi)
- [libiscsi](https://github.com/sahlberg/libiscsi)
- [iSCSI-OSX (veraltet)](https://github.com/iscsi-osx/iSCSIInitiator)

### WWDC Sessions

- WWDC 2019: System Extensions and DriverKit
- WWDC 2022: What's new in DriverKit
- WWDC 2024: Meet FSKit

---

## 16. Kontakt und Community

- **GitHub:** [TBD - Repository URL]
- **Discussions:** GitHub Discussions
- **Issues:** GitHub Issues
- **Discord/Slack:** [TBD]

---

*Dieses Dokument wird kontinuierlich aktualisiert. Letzte Änderung: 4. Februar 2026*
