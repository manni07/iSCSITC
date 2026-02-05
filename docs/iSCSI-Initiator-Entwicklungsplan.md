# iSCSI Initiator für macOS (Apple Silicon)
## Entwicklungsplan - Option B: Swift/DriverKit Native Implementation

**Version:** 1.2
**Datum:** 4. Februar 2026
**Autor:** Open Source Projekt
**Lizenz:** MIT (vorgeschlagen)

---

## 1. Executive Summary

Entwicklung eines vollständig nativen iSCSI-Initiators für macOS mit Fokus auf Apple Silicon (M1/M2/M3/M4). Die Lösung nutzt moderne Apple-Frameworks (DriverKit, Network.framework) und wird als Open-Source-Projekt veröffentlicht.

### Warum dieses Projekt?

| Problem | Lösung |
|---------|--------|
| Keine kostenlosen iSCSI-Initiatoren für Apple Silicon | Open-Source-Alternative |
| Alte Kext-basierte Lösungen funktionieren nicht mehr | Moderne DriverKit-Architektur |
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
│  │              DiskArbitration                               │ │
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
- **Zweck:** TCP/IP-Kommunikation mit iSCSI-Target
- **Framework:** Network.framework (Apple)
- **Funktionen:**
  - TCP-Verbindungsmanagement
  - TLS-Unterstützung (optional)
  - Multipath I/O (optional)

#### D) iSCSI Protocol Engine
- **Zweck:** RFC 3720/7143 Implementierung
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

### 3.4 DriverKit Extension - Detaillierte Spezifikation

Dieser Abschnitt beschreibt die technische Implementierung der DriverKit Extension (dext) im Detail. Die dext ist die zentrale Kernkomponente, die als virtuelle SCSI-HBA fungiert und dem macOS-Kernel ein SCSI-Parallel-Interface bereitstellt, obwohl keine physische Hardware vorhanden ist.

> **Wichtiger Hinweis:** DriverKit-Interfaces werden in `.iig`-Dateien (Interface Definition Files) definiert, **nicht** in `.hpp`-Dateien. Der DriverKit-Compiler (`iig`) generiert daraus die C++-Header und Implementierungsgerüste. Die in früheren Abschnitten gezeigten `.hpp`-Beispiele sind vereinfacht dargestellt.

#### 3.4.1 IOUserSCSIParallelInterfaceController - Korrekte Methodensignaturen

Die Klasse `iSCSIVirtualHBA` erbt von `IOUserSCSIParallelInterfaceController`. Apple definiert folgende **pure virtual** Methoden, die zwingend überschrieben werden müssen:

| Methode | Typ | Beschreibung |
|---------|-----|--------------|
| `UserInitializeController` | Pure Virtual | Controller initialisieren, Dispatch Queues erstellen, Datenstrukturen aufbauen |
| `UserStartController` | Pure Virtual | Controller aktivieren, Bereitschaft signalisieren |
| `UserProcessParallelTask` | Pure Virtual | Einzelne SCSI-I/O-Anfrage verarbeiten |
| `UserDoesHBAPerformAutoSense` | Pure Virtual | Auto-Sense-Fähigkeit melden |
| `UserDoesHBASupportSCSIParallelFeature` | Pure Virtual | Unterstützung von SCSI-Parallel-Features melden |
| `UserMapHBAData` | Pure Virtual | Controller-spezifische Task-Daten erstellen |

Zusätzlich stehen folgende **non-pure virtual** Methoden zur Verfügung, die von der dext aktiv aufgerufen werden:

| Methode | Beschreibung |
|---------|--------------|
| `CreateSCSITarget` | SCSI-Target mit eindeutiger ID erzeugen |
| `SetTargetProperties` | Target-Eigenschaften konfigurieren (Vendor, Product, etc.) |
| `ParallelTaskCompletion` | I/O-Abschluss an das Kernel-Framework signalisieren |

**Vollständige Interface-Definition (iSCSIVirtualHBA.iig):**

```cpp
// Datei: iSCSIVirtualHBA.iig
// DriverKit Interface Definition für die virtuelle iSCSI-HBA
// HINWEIS: .iig-Dateien werden vom iig-Compiler verarbeitet

#ifndef iSCSIVirtualHBA_iig
#define iSCSIVirtualHBA_iig

#include <Availability.h>
#include <DriverKit/IOService.iig>
#include <SCSIControllerDriverKit/IOUserSCSIParallelInterfaceController.iig>

class iSCSIVirtualHBA : public IOUserSCSIParallelInterfaceController
{
public:

    // =========================================================================
    // Lifecycle-Methoden (Default Queue)
    // =========================================================================

    virtual bool init() override;
    virtual void free() override;

    virtual kern_return_t Start(IOService * provider) override;
    virtual kern_return_t Stop(IOService * provider) override;

    // Neuen IOUserClient erzeugen (Daemon-Verbindung)
    virtual kern_return_t NewUserClient(
        uint32_t type,
        IOUserClient ** userClient) override;

    // =========================================================================
    // Pure Virtual Overrides - HBA Controller Interface
    // =========================================================================

    // Controller-Initialisierung: Queues erstellen, Strukturen aufbauen
    virtual kern_return_t UserInitializeController() override;

    // Controller starten und Bereitschaft signalisieren
    virtual kern_return_t UserStartController() override;

    // SCSI-I/O-Anfrage verarbeiten (wird pro I/O aufgerufen)
    // QUEUENAME: IOQueue
    virtual void UserProcessParallelTask(
        IOUserSCSIParallelTask * parallelTask,
        OSAction * completion
        TARGET IOUserSCSIParallelInterfaceController
    ) QUEUENAME(IOQueue) override;

    // Meldet ob Auto-Sense unterstützt wird (wir geben true zurück)
    virtual bool UserDoesHBAPerformAutoSense() override;

    // Feature-Support abfragen (Wide, QAS, etc.)
    virtual bool UserDoesHBASupportSCSIParallelFeature(
        uint32_t feature) override;

    // Controller-spezifische Daten pro Task allokieren
    virtual kern_return_t UserMapHBAData(
        IOUserSCSIParallelTask * parallelTask,
        bool map) override;

    // =========================================================================
    // Interne Hilfsmethoden
    // =========================================================================

    // Target bei Kernel registrieren (Auxiliary Queue)
    // QUEUENAME: AuxQueue
    virtual kern_return_t RegisterTarget(
        uint32_t targetID,
        uint64_t lun
    ) QUEUENAME(AuxQueue);

    // Target abmelden
    virtual kern_return_t DeregisterTarget(
        uint32_t targetID
    ) QUEUENAME(AuxQueue);
};

#endif /* iSCSIVirtualHBA_iig */
```

**Implementierungsbeispiel (Auszug aus iSCSIVirtualHBA.cpp):**

```cpp
// Datei: iSCSIVirtualHBA.cpp
#include "iSCSIVirtualHBA_Impl.h"

// Vom iig-Compiler generierte Header einbinden

kern_return_t IMPL(iSCSIVirtualHBA, UserInitializeController)
{
    kern_return_t ret = kIOReturnSuccess;

    // I/O-Queue mit hoher Priorität erstellen
    ret = IODispatchQueue::Create("IOQueue",
        kIODispatchQueueReentrant,
        kIODispatchQueuePriorityHigh,
        &ivars->fIOQueue);
    if (ret != kIOReturnSuccess) return ret;

    // Auxiliary Queue für Verwaltungsaufgaben
    ret = IODispatchQueue::Create("AuxQueue",
        kIODispatchQueueReentrant,
        kIODispatchQueuePriorityNormal,
        &ivars->fAuxQueue);
    if (ret != kIOReturnSuccess) return ret;

    // Interne Datenstrukturen initialisieren
    ivars->fMaxTargets = 256;
    ivars->fMaxLUNs = 64;
    ivars->fPendingTaskCount = 0;

    return kIOReturnSuccess;
}

kern_return_t IMPL(iSCSIVirtualHBA, UserStartController)
{
    // Controller ist bereit, auf I/O-Anfragen zu reagieren
    os_log(OS_LOG_DEFAULT,
        "iSCSIVirtualHBA: Controller gestartet, bereit fuer I/O");
    return kIOReturnSuccess;
}

void IMPL(iSCSIVirtualHBA, UserProcessParallelTask)
{
    // SCSI-CDB aus dem ParallelTask extrahieren
    uint8_t cdb[16] = {};
    uint8_t cdbLength = 0;
    parallelTask->GetCommandDescriptorBlock(cdb, &cdbLength);

    uint32_t transferSize = 0;
    parallelTask->GetRequestedDataTransferCount(&transferSize);

    uint64_t lun = 0;
    parallelTask->GetLogicalUnitNumber(&lun);

    // Task in die Shared-Memory-Queue fuer den Daemon schreiben
    // Der Daemon verarbeitet den SCSI-Befehl ueber iSCSI
    EnqueueTaskForDaemon(parallelTask, cdb, cdbLength,
                         transferSize, lun, completion);
}

bool IMPL(iSCSIVirtualHBA, UserDoesHBAPerformAutoSense)
{
    // Wir liefern Auto-Sense-Daten mit jeder SCSI-Response
    return true;
}

bool IMPL(iSCSIVirtualHBA, UserDoesHBASupportSCSIParallelFeature)
{
    // Keine physischen SCSI-Parallel-Features noetig
    // (Wide Transfer, QAS, etc. sind fuer physische Busse)
    return false;
}

kern_return_t IMPL(iSCSIVirtualHBA, UserMapHBAData)
{
    if (map) {
        // Pro-Task-Datenstruktur allokieren
        iSCSITaskData *taskData = new iSCSITaskData();
        taskData->initiatorTaskTag = ivars->fNextTaskTag++;
        taskData->state = kTaskStatePending;
        parallelTask->SetHBAData(taskData);
    } else {
        // Pro-Task-Datenstruktur freigeben
        iSCSITaskData *taskData = nullptr;
        parallelTask->GetHBAData(reinterpret_cast<void**>(&taskData));
        if (taskData) {
            delete taskData;
            parallelTask->SetHBAData(nullptr);
        }
    }
    return kIOReturnSuccess;
}
```

#### 3.4.2 Info.plist fuer die Virtuelle HBA

Da es sich um eine **virtuelle HBA ohne physische Hardware** handelt, muss das IOKit-Matching gegen `IOResources` erfolgen. `IOResources` ist ein stets vorhandener IOKit-Nub, der beim Systemstart geladen wird.

**Kritische Konfigurationshinweise:**
- `IOProviderClass` muss `IOResources` sein (nicht etwa `IOPCIDevice`)
- `IOResourceMatch: IOKit` garantiert sofortiges Matching
- `IOMatchCategory` **muss** einen eindeutigen Wert haben, um andere IOResources-Treiber nicht zu blockieren
- `IOClass` definiert die Kernel-Proxy-Klasse (nicht unsere User-Space-Klasse)
- `CFBundlePackageType: DEXT` kennzeichnet das Bundle als DriverKit Extension

**Vollstaendige Info.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Bundle-Identifikation -->
    <key>CFBundleIdentifier</key>
    <string>com.opensource.iscsi.virtualHBA</string>

    <key>CFBundleName</key>
    <string>iSCSI Virtual HBA</string>

    <key>CFBundleDisplayName</key>
    <string>iSCSI Virtual HBA DriverKit Extension</string>

    <key>CFBundleVersion</key>
    <string>1.0.0</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <!-- DEXT-spezifisch: Pakettyp als DriverKit Extension -->
    <key>CFBundlePackageType</key>
    <string>DEXT</string>

    <key>CFBundleExecutable</key>
    <string>com.opensource.iscsi.virtualHBA</string>

    <!-- Datenschutz-Beschreibung (App Store / Notarization) -->
    <key>OSBundleUsageDescription</key>
    <string>Diese DriverKit Extension stellt eine virtuelle SCSI-HBA
fuer iSCSI-Targets bereit und ermoeglicht den Zugriff auf
Netzwerk-Speichergeraete.</string>

    <!-- IOKit Personalities: Matching-Konfiguration -->
    <key>IOKitPersonalities</key>
    <dict>
        <key>iSCSIVirtualHBA</key>
        <dict>
            <!-- Kernel-Proxy-Klasse (Apple Framework) -->
            <key>IOClass</key>
            <string>IOUserSCSIParallelInterfaceController</string>

            <!-- Provider: IOResources fuer virtuelle (hardwarelose) HBA -->
            <key>IOProviderClass</key>
            <string>IOResources</string>

            <!-- Matching-Kriterium: IOKit ist immer verfuegbar -->
            <key>IOResourceMatch</key>
            <string>IOKit</string>

            <!-- User-Space-Klasse (unsere Implementierung) -->
            <key>IOUserClass</key>
            <string>iSCSIVirtualHBA</string>

            <!-- Server-Name: muss mit Bundle-Identifier uebereinstimmen -->
            <key>IOUserServerName</key>
            <string>com.opensource.iscsi.virtualHBA</string>

            <!--
                WICHTIG: IOMatchCategory muss eindeutig sein!
                Ohne eindeutige Kategorie blockiert unser Treiber alle
                anderen IOResources-Matches im System.
            -->
            <key>IOMatchCategory</key>
            <string>com.opensource.iscsi.virtualHBA</string>

            <!-- Matching-Score (niedrig, da virtuell) -->
            <key>IOProbeScore</key>
            <integer>1000</integer>
        </dict>
    </dict>
</dict>
</plist>
```

| Info.plist-Schluessel | Wert | Erlaeuterung |
|-----------------------|------|--------------|
| `CFBundlePackageType` | `DEXT` | Kennzeichnung als DriverKit Extension |
| `IOProviderClass` | `IOResources` | Virtueller Provider (kein Geraet) |
| `IOResourceMatch` | `IOKit` | Immer-verfuegbares Matching-Kriterium |
| `IOUserClass` | `iSCSIVirtualHBA` | Unsere User-Space-Implementierung |
| `IOUserServerName` | `com.opensource.iscsi.virtualHBA` | Eindeutige dext-Server-Kennung |
| `IOMatchCategory` | `com.opensource.iscsi.virtualHBA` | Verhindert Blockade anderer Treiber |
| `IOClass` | `IOUserSCSIParallelInterfaceController` | Kernel-Proxy-Klasse |

#### 3.4.3 IOUserClient - Kommunikation zwischen dext und Daemon

Die Kommunikation zwischen der DriverKit Extension und dem User-Space-Daemon (`iscsid`) erfolgt ueber eine `IOUserClient`-Subklasse. Der Daemon oeffnet eine Verbindung zum dext und nutzt External Methods sowie Shared Memory fuer den Datenaustausch.

**External Method Selectors:**

```cpp
// Datei: iSCSIUserClientShared.h
// Gemeinsam genutzte Definitionen fuer dext und Daemon

#ifndef iSCSIUserClientShared_h
#define iSCSIUserClientShared_h

// =========================================================================
// External Method Selectors
// =========================================================================

enum iSCSIUserClientSelector : uint64_t {
    kCreateSession      = 0,   // Neue iSCSI-Session registrieren
    kDestroySession     = 1,   // iSCSI-Session abmelden
    kCompleteSCSITask   = 2,   // SCSI-Task-Ergebnis an dext zurueckliefern
    kGetPendingTask     = 3,   // Naechsten ausstehenden Task abholen
    kMapSharedMemory    = 4,   // Shared-Memory-Region einrichten
    kSetHBAStatus       = 5,   // HBA-Status setzen (Online/Offline)
    kGetHBAStatus       = 6,   // Aktuellen HBA-Status abfragen
};

static const uint64_t kNumMethods = 7;

// =========================================================================
// Shared Memory Types (fuer CopyClientMemoryForType)
// =========================================================================

enum iSCSISharedMemoryType : uint32_t {
    kCommandQueue       = 0,   // Ring-Buffer: dext -> Daemon (SCSI-Befehle)
    kCompletionQueue    = 1,   // Ring-Buffer: Daemon -> dext (Ergebnisse)
    kDataBufferPool     = 2,   // Grosser Pool fuer SCSI-Datentransfers
};

// =========================================================================
// Strukturen fuer die Command/Completion Queues
// =========================================================================

struct iSCSICommandEntry {
    uint32_t taskTag;          // Eindeutiger Task-Identifier
    uint32_t targetID;         // Ziel-Target-ID
    uint64_t lun;              // Logical Unit Number
    uint8_t  cdb[16];          // SCSI Command Descriptor Block
    uint8_t  cdbLength;        // Laenge des CDB
    uint32_t transferLength;   // Angeforderte Transfergroesse
    uint8_t  dataDirection;    // 0=None, 1=Read, 2=Write
    uint64_t dataBufferOffset; // Offset im DataBufferPool
};

struct iSCSICompletionEntry {
    uint32_t taskTag;          // Zugehoeriger Task-Identifier
    uint8_t  scsiStatus;       // SCSI-Status (GOOD, CHECK CONDITION, etc.)
    uint32_t dataTransferred;  // Tatsaechlich uebertragene Bytes
    uint8_t  senseData[64];    // Auto-Sense-Daten
    uint8_t  senseLength;      // Laenge der Sense-Daten
    uint8_t  serviceResponse;  // Service-Response-Code
};

#endif /* iSCSIUserClientShared_h */
```

**IOUserClient Interface-Definition (iSCSIUserClient.iig):**

```cpp
// Datei: iSCSIUserClient.iig

#ifndef iSCSIUserClient_iig
#define iSCSIUserClient_iig

#include <Availability.h>
#include <DriverKit/IOUserClient.iig>
#include <DriverKit/IODataQueueDispatchSource.iig>

class iSCSIUserClient : public IOUserClient
{
public:
    virtual bool init() override;
    virtual void free() override;

    virtual kern_return_t Start(IOService * provider) override;
    virtual kern_return_t Stop(IOService * provider) override;

    // External Method Dispatch
    virtual kern_return_t ExternalMethod(
        uint64_t selector,
        IOUserClientMethodArguments * arguments,
        const IOUserClientMethodDispatch * dispatch,
        OSObject * target,
        void * reference) override;

    // Shared Memory bereitstellen
    virtual kern_return_t CopyClientMemoryForType(
        uint64_t type,
        uint64_t * options,
        IOMemoryDescriptor ** memory) override;

    // Notification-Queue (IODataQueueDispatchSource)
    virtual kern_return_t CreateActionKernelNotification(
        OSAction ** action) TYPE(IODataQueueDispatchSource::DataAvailable);
};

#endif /* iSCSIUserClient_iig */
```

**Dispatch Table Implementierung:**

```cpp
// Datei: iSCSIUserClient.cpp (Auszug)

#include "iSCSIUserClient_Impl.h"
#include "iSCSIUserClientShared.h"

// =========================================================================
// IOUserClientMethodDispatch Tabelle
// =========================================================================
// Definiert das Mapping von Selektoren zu Handler-Funktionen
// sowie die erwarteten Input/Output-Strukturgroessen.

static const IOUserClientMethodDispatch sMethods[kNumMethods] = {

    // [0] kCreateSession
    // Input:  targetID (scalar), portalGroupTag (scalar)
    // Output: sessionHandle (scalar)
    [kCreateSession] = {
        .function = &iSCSIUserClient::StaticHandleCreateSession,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 2,
        .checkScalarOutputCount = 1,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = 0,
    },

    // [1] kDestroySession
    // Input:  sessionHandle (scalar)
    // Output: keine
    [kDestroySession] = {
        .function = &iSCSIUserClient::StaticHandleDestroySession,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 1,
        .checkScalarOutputCount = 0,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = 0,
    },

    // [2] kCompleteSCSITask
    // Input:  Completion-Daten als Struktur
    // Output: keine
    [kCompleteSCSITask] = {
        .function = &iSCSIUserClient::StaticHandleCompleteSCSITask,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 0,
        .checkScalarOutputCount = 0,
        .checkStructureInputSize  = sizeof(iSCSICompletionEntry),
        .checkStructureOutputSize = 0,
    },

    // [3] kGetPendingTask
    // Input:  keine
    // Output: Naechster ausstehender Task als Struktur
    [kGetPendingTask] = {
        .function = &iSCSIUserClient::StaticHandleGetPendingTask,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 0,
        .checkScalarOutputCount = 0,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = sizeof(iSCSICommandEntry),
    },

    // [4] kMapSharedMemory
    // Input:  memoryType (scalar), size (scalar)
    // Output: keine (Memory Mapping via CopyClientMemoryForType)
    [kMapSharedMemory] = {
        .function = &iSCSIUserClient::StaticHandleMapSharedMemory,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 2,
        .checkScalarOutputCount = 0,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = 0,
    },

    // [5] kSetHBAStatus
    // Input:  status (scalar: 0=offline, 1=online)
    // Output: keine
    [kSetHBAStatus] = {
        .function = &iSCSIUserClient::StaticHandleSetHBAStatus,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 1,
        .checkScalarOutputCount = 0,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = 0,
    },

    // [6] kGetHBAStatus
    // Input:  keine
    // Output: status (scalar)
    [kGetHBAStatus] = {
        .function = &iSCSIUserClient::StaticHandleGetHBAStatus,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 0,
        .checkScalarOutputCount = 1,
        .checkStructureInputSize  = 0,
        .checkStructureOutputSize = 0,
    },
};

kern_return_t IMPL(iSCSIUserClient, ExternalMethod)
{
    if (selector >= kNumMethods) {
        return kIOReturnBadArgument;
    }
    return super::ExternalMethod(selector, arguments,
                                 &sMethods[selector], this, nullptr);
}
```

**Notification-Mechanismus mit IODataQueueDispatchSource:**

Fuer die asynchrone Benachrichtigung des Daemons ueber neue ausstehende Tasks wird ein `IODataQueueDispatchSource` (Ring-Buffer mit Mach-Port-Notification) verwendet:

```cpp
// In UserInitializeController():

// Notification-Queue erstellen (4096 Eintraege)
kern_return_t ret = IODataQueueDispatchSource::Create(
    sizeof(iSCSICommandEntry),  // Eintraggroesse
    4096,                        // Anzahl Eintraege
    &ivars->fNotificationQueue);

// Bei NewUserClient() dem Client uebergeben:
// Der Daemon wartet auf DataAvailable-Events via Mach Port
```

#### 3.4.4 Dispatch Queue Architektur

Gemaess Apple-Empfehlung (WWDC 2020: "Modernize PCI and SCSI drivers with DriverKit") verwendet die dext **drei dedizierte Dispatch Queues** fuer die Trennung von Lifecycle-, I/O- und Verwaltungsoperationen:

| Queue | Name | Prioritaet | Zugeordnete Methoden |
|-------|------|------------|---------------------|
| **Default Queue** | (System-Standard) | Normal | `Start`, `Stop`, `NewUserClient`, `init`, `free` |
| **I/O Queue** | `IOQueue` | Hoch (`kIODispatchQueuePriorityHigh`) | `UserProcessParallelTask` |
| **Auxiliary Queue** | `AuxQueue` | Normal | `CreateSCSITarget`, External Method Calls, `RegisterTarget` |

**Queue-Erstellung in UserInitializeController:**

```cpp
kern_return_t IMPL(iSCSIVirtualHBA, UserInitializeController)
{
    kern_return_t ret;

    // =====================================================================
    // 1. I/O Queue (hohe Prioritaet)
    //    Verarbeitet alle SCSI-I/O-Anfragen.
    //    Reentrant, damit mehrere Tasks gleichzeitig verarbeitet werden.
    // =====================================================================
    ret = IODispatchQueue::Create(
        "IOQueue",                            // Name (muss mit QUEUENAME() uebereinstimmen)
        kIODispatchQueueReentrant,            // Optionen: reentrant fuer parallele I/O
        kIODispatchQueuePriorityHigh,         // Hohe Prioritaet fuer I/O-Pfad
        &ivars->fIOQueue                      // Ergebnis-Queue
    );
    if (ret != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT,
            "iSCSIVirtualHBA: IOQueue-Erstellung fehlgeschlagen: 0x%x", ret);
        return ret;
    }

    // =====================================================================
    // 2. Auxiliary Queue (normale Prioritaet)
    //    Fuer Verwaltungsaufgaben: Target-Erstellung, UserClient-Methoden.
    //    Serialisiert, um Race Conditions bei Target-Verwaltung zu vermeiden.
    // =====================================================================
    ret = IODispatchQueue::Create(
        "AuxQueue",                           // Name
        0,                                    // Optionen: serialisiert (Standard)
        kIODispatchQueuePriorityNormal,       // Normale Prioritaet
        &ivars->fAuxQueue                     // Ergebnis-Queue
    );
    if (ret != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT,
            "iSCSIVirtualHBA: AuxQueue-Erstellung fehlgeschlagen: 0x%x", ret);
        return ret;
    }

    // =====================================================================
    // 3. Default Queue
    //    Wird vom System automatisch bereitgestellt.
    //    Lifecycle-Methoden (Start, Stop, NewUserClient) laufen hier.
    //    Keine manuelle Erstellung notwendig.
    // =====================================================================

    os_log(OS_LOG_DEFAULT,
        "iSCSIVirtualHBA: Dispatch Queues initialisiert "
        "(Default + IOQueue + AuxQueue)");

    return kIOReturnSuccess;
}
```

**Queue-Zuordnung in der .iig-Datei:**

Die Zuordnung von Methoden zu Queues erfolgt durch die `QUEUENAME()`-Annotation direkt in der `.iig`-Interface-Definition:

```cpp
// In iSCSIVirtualHBA.iig:

// I/O-Pfad: Hohe Prioritaet auf IOQueue
virtual void UserProcessParallelTask(
    IOUserSCSIParallelTask * parallelTask,
    OSAction * completion
    TARGET IOUserSCSIParallelInterfaceController
) QUEUENAME(IOQueue) override;

// Verwaltung: Normale Prioritaet auf AuxQueue
virtual kern_return_t RegisterTarget(
    uint32_t targetID,
    uint64_t lun
) QUEUENAME(AuxQueue);

// Lifecycle: Default Queue (keine QUEUENAME-Annotation)
virtual kern_return_t Start(IOService * provider) override;
virtual kern_return_t Stop(IOService * provider) override;
```

**Designbegruendung der Drei-Queue-Architektur:**

```
┌──────────────────────────────────────────────────────────┐
│                    dext Prozess                           │
│                                                          │
│  ┌─────────────────┐                                     │
│  │  Default Queue   │  Start(), Stop(), NewUserClient()  │
│  │  (serialisiert)  │  Lifecycle-Management               │
│  └────────┬─────────┘                                     │
│           │                                               │
│  ┌────────▼─────────┐                                     │
│  │  I/O Queue        │  UserProcessParallelTask()         │
│  │  (reentrant,      │  Maximaler Durchsatz fuer          │
│  │   hohe Prioritaet)│  SCSI-I/O-Operationen              │
│  └────────┬──────────┘                                     │
│           │                                               │
│  ┌────────▼──────────┐                                     │
│  │  Auxiliary Queue   │  CreateSCSITarget(),              │
│  │  (serialisiert,    │  ExternalMethod(),                │
│  │   normale Prior.)  │  RegisterTarget()                 │
│  └───────────────────┘                                     │
└──────────────────────────────────────────────────────────┘
```

#### 3.4.5 Lade- und Aktivierungsstrategie fuer die Virtuelle HBA

Da die dext als virtuelle HBA ohne physische Hardware implementiert ist, wird das **IOResources-Matching** verwendet. Dies stellt sicher, dass die dext beim Systemstart (bzw. nach der Benutzerfreigabe der System Extension) automatisch geladen wird.

**Entscheidung:** IOResources-Matching (laed beim Boot/Login sobald die System Extension genehmigt ist).

**Aktivierungsablauf (Sequenzdiagramm):**

```
┌─────────┐    ┌──────────────┐    ┌───────────┐    ┌──────────┐    ┌────────┐
│  GUI App │    │ SysExtMgr    │    │  Benutzer │    │  macOS    │    │ iscsid │
│          │    │ (Apple API)  │    │           │    │  Kernel   │    │ Daemon │
└────┬─────┘    └──────┬───────┘    └─────┬─────┘    └────┬─────┘    └───┬────┘
     │                 │                  │               │              │
     │ 1. Installations-Request          │               │              │
     │ submitRequest() │                  │               │              │
     │────────────────>│                  │               │              │
     │                 │                  │               │              │
     │                 │ 2. Freigabe-Dialog               │              │
     │                 │ anzeigen         │               │              │
     │                 │─────────────────>│               │              │
     │                 │                  │               │              │
     │                 │   3. Benutzer genehmigt          │              │
     │                 │   in Systemeinstellungen         │              │
     │                 │   (Datenschutz & Sicherheit)     │              │
     │                 │<─────────────────│               │              │
     │                 │                  │               │              │
     │  4. Delegate:   │                  │               │              │
     │  needsApproval()│                  │               │              │
     │<────────────────│                  │               │              │
     │                 │                  │               │              │
     │  5. Delegate:   │                  │               │              │
     │  didFinish      │                  │               │              │
     │  (willReboot)   │                  │               │              │
     │<────────────────│                  │               │              │
     │                 │                  │               │              │
     │                 │   6. dext wird geladen           │              │
     │                 │   (IOResources-Match)            │              │
     │                 │───────────────────────────────>  │              │
     │                 │                  │               │              │
     │                 │                  │  7. IOUserSCSI-│              │
     │                 │                  │  ParallelInterface           │
     │                 │                  │  Controller   │              │
     │                 │                  │  wird instanziiert           │
     │                 │                  │               │              │
     │                 │                  │               │ 8. Daemon    │
     │                 │                  │               │ erkennt dext │
     │                 │                  │               │ via IOService│
     │                 │                  │               │ Matching     │
     │                 │                  │               │<─────────────│
     │                 │                  │               │              │
     │                 │                  │               │ 9. IOUser-   │
     │                 │                  │               │ Client oeffnen
     │                 │                  │               │<─────────────│
     │                 │                  │               │              │
     │                 │                  │               │ 10. Bereit   │
     │                 │                  │               │ fuer iSCSI   │
     │                 │                  │               │ Sessions     │
     │                 │                  │               │<────────────>│
```

**OSSystemExtensionRequest-Verwendung in der Container-App:**

```swift
// Datei: App/SystemExtensionInstaller.swift

import SystemExtensions

class SystemExtensionInstaller: NSObject,
                                OSSystemExtensionRequestDelegate {

    private let dextIdentifier = "com.opensource.iscsi.virtualHBA"

    /// dext-Installation anfordern
    func installDriverExtension() {
        let request = OSSystemExtensionRequest
            .activationRequest(
                forExtensionWithIdentifier: dextIdentifier,
                queue: .main
            )
        request.delegate = self
        OSSystemExtensionManager.shared
            .submitRequest(request)
    }

    /// dext-Deinstallation anfordern
    func uninstallDriverExtension() {
        let request = OSSystemExtensionRequest
            .deactivationRequest(
                forExtensionWithIdentifier: dextIdentifier,
                queue: .main
            )
        request.delegate = self
        OSSystemExtensionManager.shared
            .submitRequest(request)
    }

    // =====================================================================
    // OSSystemExtensionRequestDelegate Callbacks
    // =====================================================================

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Bei Update: alten Treiber ersetzen
        return .replace
    }

    func requestNeedsUserApproval(
        _ request: OSSystemExtensionRequest
    ) {
        // Benutzer muss in Systemeinstellungen genehmigen
        // UI-Hinweis anzeigen: "Bitte genehmigen Sie die
        // System Extension in Systemeinstellungen >
        // Datenschutz & Sicherheit"
        NotificationCenter.default.post(
            name: .dextNeedsApproval, object: nil)
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result:
            OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            // dext erfolgreich installiert und geladen
            NotificationCenter.default.post(
                name: .dextInstalled, object: nil)
        case .willCompleteAfterReboot:
            // Neustart erforderlich
            NotificationCenter.default.post(
                name: .dextNeedsReboot, object: nil)
        @unknown default:
            break
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        // Fehlerbehandlung
        let nsError = error as NSError
        os_log(.error,
            "dext Installation fehlgeschlagen: %{public}@",
            nsError.localizedDescription)
        NotificationCenter.default.post(
            name: .dextInstallFailed,
            object: nsError)
    }
}
```

**Daemon-seitige dext-Erkennung via IOKit:**

```swift
// Datei: Daemon/DriverKitConnector.swift

import IOKit

class DriverKitConnector {

    private let matchingDict: CFDictionary

    init() {
        // Matching-Dictionary fuer unsere dext erstellen
        matchingDict = IOServiceMatching(
            "IOUserSCSIParallelInterfaceController"
        ) as CFDictionary
    }

    /// dext im IOKit-Registry finden und IOUserClient oeffnen
    func connectToDriver() -> io_connect_t? {
        var iterator: io_iterator_t = 0

        let kr = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict,
            &iterator
        )
        guard kr == KERN_SUCCESS else { return nil }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(
            service,
            mach_task_self_,
            0,  // Type
            &connection
        )
        guard openResult == KERN_SUCCESS else { return nil }

        return connection
    }
}
```

#### 3.4.6 Korrigierte Repository-Struktur fuer den Driver

Basierend auf der `.iig`-Anforderung ergibt sich folgende korrigierte Dateistruktur fuer das Driver-Verzeichnis:

```
Driver/
├── iSCSIVirtualHBA/
│   ├── iSCSIVirtualHBA.iig          <- Interface-Definition (NICHT .hpp)
│   ├── iSCSIVirtualHBA.cpp          <- Implementierung
│   ├── iSCSIVirtualHBA_Impl.h       <- Vom iig-Compiler generiert
│   ├── iSCSIUserClient.iig          <- UserClient Interface
│   ├── iSCSIUserClient.cpp          <- UserClient Implementierung
│   ├── iSCSIUserClient_Impl.h       <- Vom iig-Compiler generiert
│   ├── iSCSIUserClientShared.h      <- Gemeinsame Definitionen (dext + Daemon)
│   ├── Info.plist                    <- IOKit-Matching-Konfiguration
│   └── Entitlements.plist            <- DriverKit-Entitlements
└── iSCSIVirtualHBA.dext/            <- Build-Output
```

> **Hinweis:** Die vom `iig`-Compiler generierten `_Impl.h`-Dateien werden automatisch beim Build erstellt und sollten nicht in die Versionskontrolle eingecheckt werden. In `.gitignore` aufnehmen: `*_Impl.h`
---

### 3.5 IPC-Architektur (Gaps B1, B2, B3)

Die gesamte Inter-Process-Kommunikation zwischen GUI/CLI, Daemon und DriverKit Extension wird
ueber drei klar definierte Kanaele realisiert. Dieser Abschnitt spezifiziert die XPC-Protokolle,
die LaunchDaemon-Konfiguration sowie die IOUserClient-Anbindung an die DriverKit Extension.

#### Gap B1: XPC-Protokolldefinitionen

Es werden drei XPC-Kommunikationskanaele definiert:

**Kanal 1 -- GUI/CLI zum Daemon (`ISCSIDaemonXPCProtocol`)**

Dieser Kanal stellt die primaere Steuerungsschnittstelle dar. Alle Anfragen von GUI und CLI
werden ueber dieses Protokoll an den Daemon gesendet.

```swift
@objc protocol ISCSIDaemonXPCProtocol {
    /// Target-Discovery via SendTargets an einem Portal ausfuehren
    func discoverTargets(portal: String,
                         port: UInt16,
                         reply: @escaping ([Data]?, NSError?) -> Void)

    /// Login zu einem spezifischen Target initiieren
    func loginTarget(iqn: String,
                     portal: String,
                     port: UInt16,
                     reply: @escaping (Bool, NSError?) -> Void)

    /// Aktive Session abmelden
    func logoutSession(sessionId: String,
                       reply: @escaping (Bool, NSError?) -> Void)

    /// Alle aktiven Sessions auflisten
    func listSessions(reply: @escaping ([Data]) -> Void)

    /// Detailinformationen einer spezifischen Session abrufen
    func getSessionDetail(sessionId: String,
                          reply: @escaping (Data?, NSError?) -> Void)

    /// Statisches Target zur Konfiguration hinzufuegen
    func addStaticTarget(config: Data,
                         reply: @escaping (Bool, NSError?) -> Void)

    /// Target aus der Konfiguration entfernen
    func removeTarget(iqn: String,
                      portal: String,
                      reply: @escaping (Bool, NSError?) -> Void)

    /// Auto-Connect fuer ein Target aktivieren/deaktivieren
    func setAutoConnect(iqn: String,
                        portal: String,
                        enabled: Bool,
                        reply: @escaping (Bool, NSError?) -> Void)

    /// CHAP-Credentials fuer ein Target setzen
    func setCHAPCredentials(iqn: String,
                            username: String,
                            secret: String,
                            reply: @escaping (Bool, NSError?) -> Void)
}
```

**Kanal 2 -- Daemon zu GUI (Callbacks, `ISCSIDaemonCallbackProtocol`)**

Asynchrone Benachrichtigungen vom Daemon an die GUI werden ueber ein separates
Callback-Protokoll realisiert. Die GUI registriert ihre Endpoint-Verbindung beim Daemon.

```swift
@objc protocol ISCSIDaemonCallbackProtocol {
    /// Session-Zustandsaenderung (z.B. "active" -> "reconnecting")
    func sessionStateChanged(sessionId: String, newState: String)

    /// Verbindung zu einem Target verloren
    func connectionLost(sessionId: String, error: NSError)

    /// Neues Target wurde bei Discovery gefunden
    func targetDiscovered(target: Data)

    /// DriverKit Extension Status hat sich geaendert
    func driverStatusChanged(isLoaded: Bool)
}
```

**Kanal 3 -- Mach Service Registrierung**

| Parameter | Wert |
|-----------|------|
| Mach Service Name | `com.opensource.iscsid.xpc` |
| XPC Interface | `NSXPCInterface(with: ISCSIDaemonXPCProtocol.self)` |
| Callback Interface | `NSXPCInterface(with: ISCSIDaemonCallbackProtocol.self)` |
| Verbindungstyp | `NSXPCConnection(machServiceName:)` |

**XPC-Verbindungsaufbau (Daemon-Seite)**

```swift
// Beispiel: XPC Listener im Daemon
class ISCSIDaemonXPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Daemon-seitiges Interface exportieren
        let daemonInterface = NSXPCInterface(with: ISCSIDaemonXPCProtocol.self)
        connection.exportedInterface = daemonInterface
        connection.exportedObject = ISCSIDaemonService.shared

        // Callback-Interface fuer GUI-Benachrichtigungen
        let callbackInterface = NSXPCInterface(with: ISCSIDaemonCallbackProtocol.self)
        connection.remoteObjectInterface = callbackInterface

        connection.invalidationHandler = { [weak self] in
            self?.removeCallbackClient(connection)
        }
        connection.resume()
        return true
    }
}
```

**XPC-Verbindungsaufbau (Client-Seite: GUI/CLI)**

```swift
// Beispiel: XPC-Verbindung aus GUI oder CLI
class ISCSIXPCClient {
    private var connection: NSXPCConnection

    init() {
        connection = NSXPCConnection(machServiceName: "com.opensource.iscsid.xpc")
        connection.remoteObjectInterface = NSXPCInterface(
            with: ISCSIDaemonXPCProtocol.self
        )
        // Callback-Interface fuer asynchrone Benachrichtigungen (nur GUI)
        connection.exportedInterface = NSXPCInterface(
            with: ISCSIDaemonCallbackProtocol.self
        )
        connection.exportedObject = self  // implementiert ISCSIDaemonCallbackProtocol
        connection.resume()
    }

    var daemon: ISCSIDaemonXPCProtocol {
        connection.remoteObjectProxyWithErrorHandler { error in
            os_log(.error, "XPC-Verbindung fehlgeschlagen: %{public}@", error.localizedDescription)
        } as! ISCSIDaemonXPCProtocol
    }
}
```

#### Gap B2: LaunchDaemon-Konfiguration

Die vollstaendige `com.opensource.iscsid.plist` fuer die Daemon-Installation unter
`/Library/LaunchDaemons/`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Eindeutiger Label fuer den Daemon -->
    <key>Label</key>
    <string>com.opensource.iscsid</string>

    <!-- Pfad zum Daemon-Binary -->
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/iscsid</string>
        <string>--daemon</string>
    </array>

    <!-- XPC Mach Service registrieren -->
    <key>MachServices</key>
    <dict>
        <key>com.opensource.iscsid.xpc</key>
        <true/>
    </dict>

    <!-- Daemon permanent laufen lassen -->
    <key>KeepAlive</key>
    <true/>

    <!-- Beim Systemstart automatisch laden -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Logging-Pfade -->
    <key>StandardOutPath</key>
    <string>/var/log/iscsid/iscsid.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/iscsid/iscsid_error.log</string>

    <!-- Sicherheitskontext -->
    <key>UserName</key>
    <string>root</string>

    <key>GroupName</key>
    <string>wheel</string>

    <!-- Prozess-Limits -->
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>1024</integer>
    </dict>
</dict>
</plist>
```

**Installations- und Verwaltungsbefehle**

```bash
# Daemon installieren
sudo cp iscsid /Library/PrivilegedHelperTools/
sudo cp com.opensource.iscsid.plist /Library/LaunchDaemons/
sudo mkdir -p /var/log/iscsid

# Daemon laden und starten
sudo launchctl load /Library/LaunchDaemons/com.opensource.iscsid.plist

# Daemon stoppen und entladen
sudo launchctl unload /Library/LaunchDaemons/com.opensource.iscsid.plist

# Status pruefen
sudo launchctl list | grep iscsid
```

#### Gap B3: IOUserClient-Anbindung (Daemon-Seite)

Der Daemon verbindet sich ueber IOKit-Aufrufe mit der DriverKit Extension (dext).
Dies ermoeglicht die Weiterleitung von SCSI-Befehlen und Completion-Daten.

**Schritt 1: DriverKit Extension finden**

```swift
import IOKit

class DextConnector {
    private var connection: io_connect_t = 0
    private var service: io_service_t = IO_OBJECT_NULL
    private var commandQueueAddress: mach_vm_address_t = 0
    private var commandQueueSize: mach_vm_size_t = 0
    private var completionQueueAddress: mach_vm_address_t = 0
    private var completionQueueSize: mach_vm_size_t = 0

    /// DriverKit Extension im IORegistry finden und oeffnen
    func connect() throws {
        // Matching Dictionary fuer die dext erstellen
        guard let matchingDict = IOServiceMatching("iSCSIVirtualHBA") else {
            throw DextError.matchingFailed
        }

        // Service im IORegistry suchen
        service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        guard service != IO_OBJECT_NULL else {
            throw DextError.serviceNotFound
        }

        // IOUserClient-Verbindung oeffnen (Type 0 = Standard)
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else {
            throw DextError.openFailed(kr)
        }

        os_log(.info, "Verbindung zur dext hergestellt (connect_t: %d)", connection)
    }
```

**Schritt 2: Shared Memory Regionen mappen**

```swift
    // Memory-Type-Konstanten (muessen mit dext uebereinstimmen)
    private let kCommandQueueType: UInt32 = 0
    private let kCompletionQueueType: UInt32 = 1
    private let kDataBufferPoolType: UInt32 = 2

    /// Shared Memory fuer Command Queue, Completion Queue und Datenpuffer mappen
    func mapSharedMemory() throws {
        // Command Queue mappen
        var kr = IOConnectMapMemory64(
            connection,
            kCommandQueueType,
            mach_task_self_,
            &commandQueueAddress,
            &commandQueueSize,
            UInt32(kIOMapAnywhere)
        )
        guard kr == KERN_SUCCESS else {
            throw DextError.mapFailed("CommandQueue", kr)
        }

        // Completion Queue mappen
        kr = IOConnectMapMemory64(
            connection,
            kCompletionQueueType,
            mach_task_self_,
            &completionQueueAddress,
            &completionQueueSize,
            UInt32(kIOMapAnywhere)
        )
        guard kr == KERN_SUCCESS else {
            throw DextError.mapFailed("CompletionQueue", kr)
        }

        os_log(.info, "Shared Memory gemappt: CMD=%llu bytes, CMPL=%llu bytes",
               commandQueueSize, completionQueueSize)
    }
```

**Schritt 3: External Methods aufrufen (SCSI Task Completion)**

```swift
    // Selector-Konstanten fuer ExternalMethod-Aufrufe
    private let kCompleteSCSITask: UInt32 = 0
    private let kAbortSCSITask: UInt32 = 1
    private let kReportDriverStatus: UInt32 = 2

    /// SCSI Task Completion an die dext zurueckmelden
    func completeSCSITask(_ completion: SCSICompletionDescriptor) throws {
        var completionData = completion
        let inputSize = MemoryLayout<SCSICompletionDescriptor>.size

        let kr = IOConnectCallStructMethod(
            connection,
            kCompleteSCSITask,
            &completionData,
            inputSize,
            nil,   // kein Output
            nil    // keine Output-Groesse
        )
        guard kr == KERN_SUCCESS else {
            throw DextError.externalMethodFailed("CompleteSCSITask", kr)
        }
    }

    /// Einzelnen SCSI Task abbrechen
    func abortSCSITask(taskTag: UInt64) throws {
        var tag = taskTag
        let inputSize = MemoryLayout<UInt64>.size

        let kr = IOConnectCallStructMethod(
            connection,
            kAbortSCSITask,
            &tag,
            inputSize,
            nil,
            nil
        )
        guard kr == KERN_SUCCESS else {
            throw DextError.externalMethodFailed("AbortSCSITask", kr)
        }
    }

    /// Verbindung sauber trennen
    func disconnect() {
        if commandQueueAddress != 0 {
            IOConnectUnmapMemory64(connection, kCommandQueueType,
                                   mach_task_self_, commandQueueAddress)
        }
        if completionQueueAddress != 0 {
            IOConnectUnmapMemory64(connection, kCompletionQueueType,
                                   mach_task_self_, completionQueueAddress)
        }
        if connection != 0 {
            IOServiceClose(connection)
        }
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
        }
    }
}
```

**Fehlerbehandlung**

```swift
enum DextError: Error, LocalizedError {
    case matchingFailed
    case serviceNotFound
    case openFailed(kern_return_t)
    case mapFailed(String, kern_return_t)
    case externalMethodFailed(String, kern_return_t)

    var errorDescription: String? {
        switch self {
        case .matchingFailed:
            return "IOServiceMatching fuer iSCSIVirtualHBA fehlgeschlagen"
        case .serviceNotFound:
            return "iSCSIVirtualHBA dext nicht im IORegistry gefunden"
        case .openFailed(let kr):
            return "IOServiceOpen fehlgeschlagen (kern_return: \(kr))"
        case .mapFailed(let region, let kr):
            return "IOConnectMapMemory64 fuer \(region) fehlgeschlagen (kern_return: \(kr))"
        case .externalMethodFailed(let method, let kr):
            return "IOConnectCallStructMethod \(method) fehlgeschlagen (kern_return: \(kr))"
        }
    }
}
```

**Kommunikationsfluss-Diagramm**

```
┌──────────────┐         XPC          ┌──────────────────┐       IOUserClient       ┌────────────────┐
│   GUI App    │◄────────────────────►│   iscsid Daemon   │◄──────────────────────►│  dext (HBA)    │
│   CLI Tool   │  ISCSIDaemonXPC-     │                    │  IOServiceOpen()       │  iSCSIVirtual  │
│              │  Protocol            │  ┌──────────────┐  │  IOConnectMapMemory()  │  HBA           │
│              │                      │  │ DextConnector│  │  IOConnectCallStruct   │                │
│              │  ISCSIDaemonCallback- │  │              │  │  Method()              │                │
│              │  Protocol            │  └──────────────┘  │                        │                │
└──────────────┘                      └──────────────────┘                        └────────────────┘
       │                                       │                                          │
       │  1. discoverTargets()                 │                                          │
       │──────────────────────────────►        │                                          │
       │                                       │  2. TCP SendTargets                      │
       │                                       │─────────────────► iSCSI Target           │
       │                                       │◄─────────────────                        │
       │  3. reply([targetData])               │                                          │
       │◄──────────────────────────────        │                                          │
       │                                       │                                          │
       │  4. loginTarget()                     │                                          │
       │──────────────────────────────►        │  5. SCSI Command via Shared Memory       │
       │                                       │◄─────────────────────────────────────────│
       │                                       │  6. Completion via ExternalMethod         │
       │                                       │─────────────────────────────────────────►│
```

### 3.6 DriverKit <-> Daemon Datenpfad (Gaps E1, E2, E3)

Dieser Abschnitt spezifiziert den Hochleistungs-Datenpfad zwischen der DriverKit Extension (dext)
und dem User-Space-Daemon. Der Entwurf optimiert Latenz und Durchsatz fuer SCSI I/O-Operationen.

#### Gap E1: Shared Memory Layout

**Entwurfsentscheidung:** Kombination aus `IODataQueueDispatchSource` fuer Command/Completion-
Signalisierung und einem vorab allokierten `IOBufferMemoryDescriptor`-Pool fuer Nutzdaten.

**Architektur-Uebersicht Shared Memory**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Shared Memory Gesamtlayout                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Region 0: Command Queue (Type 0)                                       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  IODataQueueDispatchSource-basierte Queue                         │  │
│  │  Richtung: dext -> Daemon                                         │  │
│  │  Inhalt: SCSICommandDescriptor Strukturen                         │  │
│  │  Groesse: 64 KB (ca. 800 Eintraege)                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  Region 1: Completion Queue (Type 1)                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  IODataQueueDispatchSource-basierte Queue                         │  │
│  │  Richtung: Daemon -> dext                                         │  │
│  │  Inhalt: SCSICompletionDescriptor Strukturen                      │  │
│  │  Groesse: 64 KB (ca. 200 Eintraege)                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  Region 2: Data Buffer Pool (Type 2)                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Vorab allokierter IOBufferMemoryDescriptor                       │  │
│  │  Groesse: 64 MB (256 Segmente x 256 KB)                          │  │
│  │  Zugriff: Bidirektional (READ + WRITE)                            │  │
│  │                                                                    │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        ┌────────┐  │  │
│  │  │ Seg 0  │ │ Seg 1  │ │ Seg 2  │ │ Seg 3  │  ...   │ Seg255 │  │  │
│  │  │ 256 KB │ │ 256 KB │ │ 256 KB │ │ 256 KB │        │ 256 KB │  │  │
│  │  │ Off: 0 │ │Off:256K│ │Off:512K│ │Off:768K│        │Off:~64M│  │  │
│  │  └────────┘ └────────┘ └────────┘ └────────┘        └────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Command Descriptor Struktur**

Der Command Descriptor wird von der dext in die Command Queue geschrieben, wenn das Kernel-
SCSI-Framework einen neuen Task an die virtuelle HBA uebergibt.

```c
// Gepackte Struktur fuer Shared-Memory-Kompatibilitaet (80 Bytes)
#pragma pack(push, 1)
struct SCSICommandDescriptor {
    uint64_t taskTag;           // Kernel SCSI Task Tag
                                // (SCSITaggedTaskIdentifier, zugewiesen vom IOSCSIParallelFamily)

    uint64_t initiatorTaskTag;  // iSCSI ITT (Initiator Task Tag)
                                // Zugewiesen vom Daemon nach Empfang (siehe Gap E3)

    uint64_t lun;               // Logical Unit Number (LUN) des Zielgeraets

    uint8_t  cdb[16];          // SCSI Command Descriptor Block
                                // Maximale CDB-Groesse fuer SPC-4/SBC-3 Befehle

    uint32_t dataDirection;     // Datentransferrichtung:
                                //   0 = kein Datentransfer
                                //   1 = READ  (Target -> Initiator)
                                //   2 = WRITE (Initiator -> Target)

    uint32_t transferLength;    // Erwartete Datentransferlaenge in Bytes

    uint32_t dataBufferOffset;  // Offset in den Data Buffer Pool (Region 2)
                                // Gibt an, wo die Nutzdaten gelesen/geschrieben werden

    uint32_t reserved;          // Reserviert fuer zukuenftige Erweiterungen
};
#pragma pack(pop)

// Compile-Time-Pruefung der Strukturgroesse
_Static_assert(sizeof(struct SCSICommandDescriptor) == 80,
               "SCSICommandDescriptor muss exakt 80 Bytes gross sein");
```

**Completion Descriptor Struktur**

Der Completion Descriptor wird vom Daemon zurueck an die dext gesendet, nachdem der
iSCSI-Transfer zum Target abgeschlossen (oder fehlgeschlagen) ist.

```c
// Gepackte Struktur fuer Shared-Memory-Kompatibilitaet (280 Bytes)
#pragma pack(push, 1)
struct SCSICompletionDescriptor {
    uint64_t taskTag;            // Kernel SCSI Task Tag (Original aus CommandDescriptor)

    uint64_t initiatorTaskTag;   // iSCSI ITT (zur Verifizierung)

    uint8_t  scsiStatus;         // SCSI Status Byte (RFC 3720, Section 10.4.1):
                                 //   0x00 = GOOD
                                 //   0x02 = CHECK CONDITION
                                 //   0x08 = BUSY
                                 //   0x18 = RESERVATION CONFLICT
                                 //   0x28 = TASK SET FULL
                                 //   0x30 = ACA ACTIVE

    uint8_t  serviceResponse;    // SAM Service Response:
                                 //   0x00 = TASK_COMPLETE
                                 //   0x01 = LINKED_COMMAND_COMPLETE
                                 //   0x04 = SERVICE_DELIVERY_OR_TARGET_FAILURE

    uint16_t senseDataLength;    // Tatsaechliche Laenge der Sense-Daten (0-252)

    uint8_t  senseData[252];     // SCSI Sense Data (fuer CHECK CONDITION usw.)
                                 // Enthaelt Sense Key, ASC, ASCQ usw.

    uint32_t dataTransferCount;  // Tatsaechlich uebertragene Bytes
                                 // Kann kleiner als transferLength sein (Short Read/Write)
};
#pragma pack(pop)

_Static_assert(sizeof(struct SCSICompletionDescriptor) == 280,
               "SCSICompletionDescriptor muss exakt 280 Bytes gross sein");
```

**Data Buffer Pool Verwaltung**

| Parameter | Wert | Beschreibung |
|-----------|------|--------------|
| Gesamtgroesse | 64 MB | `IOBufferMemoryDescriptor` vorab allokiert |
| Segmentgroesse | 256 KB | Maximale Groesse eines einzelnen SCSI-Transfers |
| Segmentanzahl | 256 | 64 MB / 256 KB |
| Segment-Offset-Berechnung | `segmentIndex * 262144` | Offset in Bytes ab Poolbeginn |
| Groessere Transfers | Mehrere Segmente verkettet | Ueber verkettete Segment-Indizes |

**Segment-Allokation im Daemon**

```swift
/// Thread-sichere Verwaltung der Data Buffer Segmente
class DataBufferPool {
    private let segmentCount = 256
    private let segmentSize = 256 * 1024  // 256 KB
    private var freeSegments: [Int]
    private let lock = os_unfair_lock_s()

    init() {
        freeSegments = Array(0..<segmentCount)
    }

    /// Einzelnes Segment allokieren, gibt Segment-Index zurueck
    func allocateSegment() -> Int? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return freeSegments.isEmpty ? nil : freeSegments.removeFirst()
    }

    /// Mehrere Segmente fuer grosse Transfers allokieren
    func allocateSegments(count: Int) -> [Int]? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard freeSegments.count >= count else { return nil }
        let allocated = Array(freeSegments.prefix(count))
        freeSegments.removeFirst(count)
        return allocated
    }

    /// Segmente nach Abschluss zurueckgeben
    func releaseSegment(_ index: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        freeSegments.append(index)
    }

    /// Byte-Offset fuer einen Segment-Index berechnen
    func offsetForSegment(_ index: Int) -> UInt32 {
        UInt32(index * segmentSize)
    }
}
```

#### Gap E2: Completion-Signalisierung

**Entwurfsentscheidung:** Der Daemon ruft `IOConnectCallStructMethod` mit dem Selector
`kCompleteSCSITask` auf und uebergibt den ausgefuellten `SCSICompletionDescriptor`. Der
ExternalMethod-Handler in der dext sucht den originalen `IOUserSCSIParallelTask` anhand
des `taskTag` und ruft `ParallelTaskCompletion` auf.

**Signalisierungsfluss (Detailliert)**

```
┌──────────────┐                     ┌──────────────────┐                    ┌────────────────┐
│  iSCSI       │                     │   iscsid Daemon   │                    │  dext (HBA)    │
│  Target      │                     │                    │                    │                │
└──────┬───────┘                     └────────┬───────────┘                    └───────┬────────┘
       │                                      │                                        │
       │                                      │    1. Neuer SCSI Task                  │
       │                                      │◄───────────────────────────────────────│
       │                                      │    SCSICommandDescriptor via           │
       │                                      │    Command Queue (Shared Memory)       │
       │                                      │                                        │
       │  2. iSCSI SCSI Command PDU           │                                        │
       │◄─────────────────────────────────────│                                        │
       │                                      │                                        │
       │  3. iSCSI SCSI Response PDU          │                                        │
       │  (+ Data-In bei READ)                │                                        │
       │─────────────────────────────────────►│                                        │
       │                                      │                                        │
       │                                      │  4. Daten in Data Buffer Pool          │
       │                                      │     schreiben (bei READ)               │
       │                                      │                                        │
       │                                      │  5. IOConnectCallStructMethod(         │
       │                                      │     kCompleteSCSITask,                 │
       │                                      │     &completionDescriptor)             │
       │                                      │───────────────────────────────────────►│
       │                                      │                                        │
       │                                      │                                        │ 6. ExternalMethod
       │                                      │                                        │    Handler:
       │                                      │                                        │    - taskTag
       │                                      │                                        │      nachschlagen
       │                                      │                                        │    - SCSIStatus
       │                                      │                                        │      setzen
       │                                      │                                        │    - Parallel
       │                                      │                                        │      Task
       │                                      │                                        │      Completion
       │                                      │                                        │      aufrufen
```

**ExternalMethod-Handler in der dext (C++)**

```cpp
// Beispiel: ExternalMethod Dispatch in der dext
kern_return_t iSCSIVirtualHBA::ExternalMethod(
    uint64_t selector,
    IOUserClientMethodArguments* arguments,
    const IOUserClientMethodDispatch* dispatch,
    OSObject* target,
    void* reference)
{
    switch (selector) {
        case kCompleteSCSITask: {
            // Completion Descriptor aus Input-Buffer lesen
            const auto* completion = static_cast<const SCSICompletionDescriptor*>(
                arguments->structureInput->getBytesNoCopy()
            );

            // Originalen SCSI Task anhand des taskTag finden
            auto* task = findPendingTask(completion->taskTag);
            if (!task) {
                os_log(OS_LOG_DEFAULT, "Task mit Tag %llu nicht gefunden",
                       completion->taskTag);
                return kIOReturnNotFound;
            }

            // SCSI Status und Sense Data setzen
            task->SetSCSITaskStatus(completion->scsiStatus);
            task->SetServiceResponse(completion->serviceResponse);

            if (completion->senseDataLength > 0) {
                task->SetAutoSenseData(
                    completion->senseData,
                    completion->senseDataLength
                );
            }

            task->SetRealizedDataTransferCount(completion->dataTransferCount);

            // Task-Completion an das Kernel-SCSI-Framework zurueckmelden
            ParallelTaskCompletion(task, /* completionAction */ nullptr);

            return kIOReturnSuccess;
        }

        case kAbortSCSITask: {
            const auto* taskTag = static_cast<const uint64_t*>(
                arguments->structureInput->getBytesNoCopy()
            );
            return abortPendingTask(*taskTag);
        }

        case kReportDriverStatus: {
            // Driver-Statusinformationen zurueckgeben
            return reportStatus(arguments);
        }

        default:
            return kIOReturnUnsupported;
    }
}
```

**Fehlerbehandlung bei Completion**

| Fehlerszenario | Behandlung |
|----------------|------------|
| Task Tag nicht gefunden | `kIOReturnNotFound`, Warnung loggen, Daemon benachrichtigen |
| Timeout (kein Completion) | Daemon sendet Abort, dext meldet Task als fehlgeschlagen |
| Transport-Fehler | `serviceResponse = SERVICE_DELIVERY_OR_TARGET_FAILURE` |
| CHECK CONDITION | Sense Data wird an Kernel-SCSI-Framework weitergeleitet |
| Daemon-Absturz | dext erkennt IOUserClient-Disconnect, alle Tasks mit Fehler abschliessen |

#### Gap E3: Task Tag Mapping

Das Tag-Mapping stellt die bidirektionale Zuordnung zwischen Kernel-SCSI-Task-Identifiern
und iSCSI Initiator Task Tags (ITT) sicher.

**Zuordnungsebenen**

| Ebene | Bezeichnung | Typ | Zugewiesen von | Beschreibung |
|-------|-------------|-----|----------------|--------------|
| Kernel | `SCSITaggedTaskIdentifier` | `UInt64` | `IOSCSIParallelFamily` via `UserProcessParallelTask` | Eindeutiger Bezeichner innerhalb des Kernel-SCSI-Frameworks |
| iSCSI | `InitiatorTaskTag` (ITT) | `UInt32` | Daemon (sequentieller Zaehler) | Identifiziert den Task in iSCSI PDUs (RFC 3720, Section 10.2.1) |

**Tag Map Implementierung**

```swift
/// Thread-sichere bidirektionale Zuordnung zwischen ITT und Kernel Task Tag
actor TaskTagMap {
    /// ITT -> Kernel Task Tag
    private var ittToKernel: [UInt32: UInt64] = [:]

    /// Kernel Task Tag -> ITT (Rueckwaertssuche)
    private var kernelToItt: [UInt64: UInt32] = [:]

    /// Atomarer ITT-Zaehler (beginnt bei 1, Wraparound bei UInt32.max)
    private var nextITT: UInt32 = 1

    /// Neues ITT fuer einen Kernel Task Tag allokieren
    func allocateITT(forKernelTag kernelTag: UInt64) -> UInt32 {
        let itt = nextITT

        // Wraparound: 0 ist reserviert (RFC 3720 - 0xFFFFFFFF = reserved)
        if nextITT == UInt32.max {
            nextITT = 1
        } else {
            nextITT += 1
        }

        ittToKernel[itt] = kernelTag
        kernelToItt[kernelTag] = itt
        return itt
    }

    /// Kernel Task Tag fuer ein ITT nachschlagen
    func kernelTag(forITT itt: UInt32) -> UInt64? {
        ittToKernel[itt]
    }

    /// ITT fuer einen Kernel Task Tag nachschlagen
    func itt(forKernelTag kernelTag: UInt64) -> UInt32? {
        kernelToItt[kernelTag]
    }

    /// Mapping bei Completion oder Abort entfernen
    func removeMapping(forITT itt: UInt32) {
        if let kernelTag = ittToKernel.removeValue(forKey: itt) {
            kernelToItt.removeValue(forKey: kernelTag)
        }
    }

    /// Mapping bei Completion oder Abort entfernen (via Kernel Tag)
    func removeMapping(forKernelTag kernelTag: UInt64) {
        if let itt = kernelToItt.removeValue(forKey: kernelTag) {
            ittToKernel.removeValue(forKey: itt)
        }
    }

    /// Alle Mappings entfernen (z.B. bei Session-Reset)
    func removeAll() {
        ittToKernel.removeAll()
        kernelToItt.removeAll()
        nextITT = 1
    }

    /// Anzahl aktiver Mappings (fuer Monitoring)
    var activeCount: Int {
        ittToKernel.count
    }
}
```

**Lebenszyklus eines Task Tags**

```
                          Kernel SCSI Framework
                                  │
                                  │ SCSIParallelTaskStart()
                                  │ taskTag = 0x00000042ABCD
                                  ▼
┌───────────────────────────────────────────────────────────────────┐
│  1. dext empfaengt Task                                           │
│     - Schreibt SCSICommandDescriptor in Command Queue             │
│     - taskTag = 0x00000042ABCD (Kernel-Wert)                      │
└───────────────────────────────────┬───────────────────────────────┘
                                    │ Shared Memory
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│  2. Daemon liest Command Queue                                    │
│     - Empfaengt SCSICommandDescriptor                             │
│     - Allokiert ITT: TaskTagMap.allocateITT(forKernelTag:)        │
│     - ITT = 0x00000137 (naechster Zaehler-Wert)                   │
│     - Speichert Mapping: 0x00000137 <-> 0x00000042ABCD            │
└───────────────────────────────────┬───────────────────────────────┘
                                    │ Network (TCP)
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│  3. iSCSI SCSI Command PDU wird gesendet                         │
│     - InitiatorTaskTag = 0x00000137 (ITT aus Daemon)              │
│     - CDB, LUN, DataDirection aus CommandDescriptor               │
└───────────────────────────────────┬───────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│  4. iSCSI SCSI Response PDU empfangen                            │
│     - InitiatorTaskTag = 0x00000137 (vom Target zurueckgegeben)   │
│     - Daemon sucht Kernel Tag: TaskTagMap.kernelTag(forITT:)      │
│     - kernelTag = 0x00000042ABCD                                  │
└───────────────────────────────────┬───────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│  5. Completion an dext senden                                     │
│     - SCSICompletionDescriptor.taskTag = 0x00000042ABCD           │
│     - IOConnectCallStructMethod(kCompleteSCSITask, ...)           │
│     - Mapping entfernen: TaskTagMap.removeMapping(forITT:)        │
└───────────────────────────────────────────────────────────────────┘
```

**Wichtige Entwurfsregeln fuer das Tag Mapping**

- **Speicherort:** Die Tag Map liegt ausschliesslich im Daemon-Speicher (nicht im Shared Memory)
- **ITT-Allokation:** Atomarer Zaehler, beginnt bei 1, Wraparound bei `UInt32.max`
- **ITT = 0 ist ungueltig:** Wird nie vergeben (RFC 3720 reserviert bestimmte Werte)
- **Cleanup:** Mapping wird entfernt bei:
  - Erfolgreicher Completion (normaler Abschluss)
  - Task Abort (TMF ABORT TASK)
  - Session-Reset (alle Mappings geloescht)
  - Timeout (nach Ablauf der Task-Timeout-Periode)
- **Duplikaterkennung:** Vor ITT-Vergabe wird geprueft, ob der Zaehler-Wert bereits in der Map existiert (theoretisch moeglich nach ca. 4 Milliarden Wraps)
- **Monitoring:** `activeCount` ermoeglicht die Ueberwachung ausstehender Tasks fuer Diagnosezwecke

---

### 3.7 Netzwerkschicht-Design (Gap D2)

### PDU-Framing mit Network.framework

**Entscheidung:** `NWProtocolFramer` wird fuer das PDU-Framing verwendet (Apples empfohlener Ansatz fuer benutzerdefinierte Protokolle auf TCP-Basis).

### ISCSIProtocolFramer-Definition

```swift
import Network

/// NWProtocolFramer-Implementierung fuer iSCSI PDU-Framing
/// Liest 48-Byte BHS, berechnet Gesamtgroesse, liefert vollstaendige PDUs
class ISCSIProtocolFramer: NWProtocolFramerImplementation {

    static let definition = NWProtocolFramer.Definition(implementation: ISCSIProtocolFramer.self)
    static var label: String { "iSCSI" }

    required init(framer: NWProtocolFramer.Instance) {}
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func cleanup(framer: NWProtocolFramer.Instance) {}

    /// PDU-Eingang: BHS lesen, Gesamtgroesse berechnen, vollstaendige PDU liefern
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        // Schritt 1: 48 Bytes BHS lesen
        let bhsSize = 48
        var tempBuffer = Data(count: bhsSize)

        let parsed = framer.parseInput(minimumIncompleteLength: bhsSize,
                                       maximumLength: bhsSize) { buffer, isComplete in
            guard let buffer = buffer, buffer.count >= bhsSize else { return 0 }
            tempBuffer = Data(buffer.prefix(bhsSize))
            return bhsSize
        }
        guard parsed else { return bhsSize }

        // Schritt 2: TotalAHSLength und DataSegmentLength aus BHS extrahieren
        let totalAHSLength = Int(tempBuffer[4]) * 4  // Byte 4, in 4-Byte-Woertern
        let dataSegmentLength = (Int(tempBuffer[5]) << 16)
                              | (Int(tempBuffer[6]) << 8)
                              | Int(tempBuffer[7])
        let paddedDataLength = (dataSegmentLength + 3) & ~3  // 4-Byte-Alignment

        // Schritt 3: Gesamte PDU-Groesse berechnen
        let totalPDUSize = bhsSize + totalAHSLength + paddedDataLength

        // Schritt 4: Restliche Bytes lesen und vollstaendige PDU liefern
        let message = NWProtocolFramer.Message(definition: ISCSIProtocolFramer.definition)
        _ = framer.deliverInputNoCopy(length: totalPDUSize, message: message, isComplete: true)

        return 0
    }

    /// PDU-Ausgang: Vollstaendige PDU-Bytes in die Verbindung schreiben
    func handleOutput(framer: NWProtocolFramer.Instance,
                      message: NWProtocolFramer.Message,
                      messageLength: Int,
                      isComplete: Bool) {
        try? framer.writeOutputNoCopy(length: messageLength)
    }
}
```

### NWConnection-Setup mit ISCSIProtocolFramer

```swift
import Network

/// Erstellt eine NWConnection mit iSCSI-PDU-Framing und optimierten TCP-Parametern
func createISCSIConnection(host: String, port: UInt16 = 3260) -> NWConnection {

    // TCP-Parameter mit Optimierungen konfigurieren
    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.noDelay = true                          // TCP_NODELAY=true
    tcpOptions.enableKeepalive = true                  // Keepalive aktivieren
    tcpOptions.keepaliveInterval = 30                  // Keepalive-Intervall 30s
    tcpOptions.connectionTimeout = 10                  // Verbindungs-Timeout 10s

    let parameters = NWParameters(tls: nil, tcp: tcpOptions)

    // Sende-/Empfangspuffer auf 256 KB setzen
    // (wird ueber SO_SNDBUF/SO_RCVBUF in den TCP-Optionen gesteuert)

    // ISCSIProtocolFramer als Framing-Protokoll registrieren
    let iscsiOptions = NWProtocolFramer.Options(definition: ISCSIProtocolFramer.definition)
    parameters.defaultProtocolStack.applicationProtocols.insert(iscsiOptions, at: 0)

    let endpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!
    )

    return NWConnection(to: endpoint, using: parameters)
}
```

### Verbindungs-Zustandsautomat

Die Netzwerkverbindung durchlaeuft definierte Zustaende waehrend ihres Lebenszyklus:

| Zustand | Beschreibung | Erlaubte Uebergaenge |
|---------|-------------|---------------------|
| `idle` | Verbindung nicht initialisiert | `connecting` |
| `connecting` | TCP-Verbindungsaufbau laeuft | `tcpEstablished`, `failed` |
| `tcpEstablished` | TCP-Verbindung steht, iSCSI-Login beginnt | `securityNegotiation`, `operationalNegotiation`, `failed` |
| `securityNegotiation` | CHAP/Authentifizierungs-Phase | `operationalNegotiation`, `failed` |
| `operationalNegotiation` | Parameter-Aushandlung (MaxRecvDataSegmentLength, etc.) | `fullFeaturePhase`, `failed` |
| `fullFeaturePhase` | Voll funktionsfaehig, SCSI-Befehle moeglich | `loggingOut`, `disconnecting`, `failed` |
| `loggingOut` | Ordnungsgemaesser Logout laeuft | `idle`, `failed` |
| `disconnecting` | Verbindung wird getrennt | `idle` |
| `failed` | Fehler aufgetreten, Reconnection-Logik greift | `connecting`, `idle` |

```swift
/// Verbindungszustaende fuer den iSCSI-Zustandsautomaten
enum ISCSIConnectionState: String, Sendable {
    case idle
    case connecting
    case tcpEstablished
    case securityNegotiation
    case operationalNegotiation
    case fullFeaturePhase
    case loggingOut
    case disconnecting
    case failed
}
```

### Zustandsuebergangstabelle

| Von | Nach | Ausloeser |
|-----|------|-----------|
| `idle` | `connecting` | `connect()` aufgerufen |
| `connecting` | `tcpEstablished` | TCP-Handshake erfolgreich |
| `connecting` | `failed` | TCP-Timeout oder Netzwerkfehler |
| `tcpEstablished` | `securityNegotiation` | Target erfordert Authentifizierung |
| `tcpEstablished` | `operationalNegotiation` | Keine Authentifizierung noetig |
| `securityNegotiation` | `operationalNegotiation` | CHAP erfolgreich |
| `securityNegotiation` | `failed` | Authentifizierung fehlgeschlagen |
| `operationalNegotiation` | `fullFeaturePhase` | Parameter ausgehandelt, Final Login Response |
| `operationalNegotiation` | `failed` | Parameter-Verhandlung fehlgeschlagen |
| `fullFeaturePhase` | `loggingOut` | `logout()` aufgerufen |
| `fullFeaturePhase` | `failed` | Verbindungsabbruch, Timeout |
| `loggingOut` | `idle` | Logout Response erhalten |
| `loggingOut` | `failed` | Logout-Timeout |
| `disconnecting` | `idle` | TCP-Verbindung geschlossen |
| `failed` | `connecting` | Reconnection-Versuch |
| `failed` | `idle` | Max. Wiederholungen erreicht |

### Reconnection-Strategie

Die Reconnection verwendet exponentielles Backoff mit konfigurierbaren Parametern:

| Parameter | Standardwert | Beschreibung |
|-----------|-------------|-------------|
| Initiales Intervall | 1 Sekunde | Wartezeit vor erstem Wiederversuch |
| Backoff-Faktor | 2x | Verdopplung pro Fehlversuch |
| Maximales Intervall | 30 Sekunden | Obergrenze fuer Wartezeit |
| Maximale Versuche | 10 | Danach Zustand `idle`, Benutzereingriff noetig |
| Jitter | +/-25% | Zufaellige Variation zur Vermeidung von Thundering Herd |

**Backoff-Sequenz:** 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s (dann Abbruch)

```swift
/// Konfiguration fuer die Reconnection-Strategie
struct ReconnectionConfig: Sendable {
    var initialInterval: TimeInterval = 1.0
    var backoffMultiplier: Double = 2.0
    var maximumInterval: TimeInterval = 30.0
    var maximumRetries: Int = 10
    var jitterFraction: Double = 0.25

    func delay(forAttempt attempt: Int) -> TimeInterval {
        let base = min(initialInterval * pow(backoffMultiplier, Double(attempt)),
                       maximumInterval)
        let jitter = base * jitterFraction * Double.random(in: -1...1)
        return max(0, base + jitter)
    }
}
```

### TCP-Konfigurationsparameter

| Parameter | Wert | Begruendung |
|-----------|------|-------------|
| `TCP_NODELAY` | `true` | Latenzreduzierung, Nagle-Algorithmus deaktiviert |
| Keepalive-Intervall | 30 Sekunden | Erkennung von toten Verbindungen |
| Sendepuffer | 256 KB | Ausreichend fuer typische iSCSI-Workloads |
| Empfangspuffer | 256 KB | Ausreichend fuer typische iSCSI-Workloads |
| Verbindungs-Timeout | 10 Sekunden | Schnelle Fehlererkennung bei unerreichbaren Targets |

### 3.7.1 TCP-Tuning-Parameter (Gap D4)

Die Netzwerkschicht verwendet `NWProtocolTCP.Options` aus dem Network.framework fuer die vollstaendige Kontrolle ueber TCP-Socket-Parameter. Die folgende Tabelle dokumentiert alle konfigurierbaren Parameter und ihre Standardwerte:

#### Vollstaendige TCP-Socket-Optionen

| Parameter | Wert | Konstante / API | Begruendung |
|-----------|------|-----------------|-------------|
| `TCP_NODELAY` | `true` | `NWProtocolTCP.Options.noDelay` | Deaktiviert den Nagle-Algorithmus; minimale Latenz fuer iSCSI-PDUs |
| `SO_SNDBUF` | 262144 (256 KB) | Kernel-Default ueberschreiben | Ausreichend fuer MaxBurstLength (262144) ohne Fragmentierung |
| `SO_RCVBUF` | 262144 (256 KB) | Kernel-Default ueberschreiben | Symmetrischer Empfangspuffer fuer Vollduplex-SCSI-I/O |
| `TCP_KEEPALIVE` | 30 Sekunden | `NWProtocolTCP.Options.keepaliveIdle` | Erkennung von toten Verbindungen innerhalb der NOP-In/Out-Schwelle |
| `TCP_KEEPCNT` | 5 | `NWProtocolTCP.Options.keepaliveCount` | 5 fehlgeschlagene Probes = Verbindung als tot markiert |
| `TCP_KEEPINTVL` | 10 Sekunden | `NWProtocolTCP.Options.keepaliveInterval` | 10s zwischen Keepalive-Probes; Gesamterkennung: 30 + (5 x 10) = 80s |
| `TCP_RXT_CONNDROPTIME` | 60 Sekunden | `NWProtocolTCP.Options.connectionDropTime` | Maximale Retransmission-Zeit bevor TCP aufgibt |

#### NWProtocolTCP.Options-Konfiguration

```swift
/// Erstellt optimierte TCP-Optionen fuer iSCSI-Verbindungen
func createISCSITCPOptions() -> NWProtocolTCP.Options {
    let tcpOptions = NWProtocolTCP.Options()

    // Nagle-Algorithmus deaktivieren fuer minimale Latenz
    tcpOptions.noDelay = true

    // Keepalive-Parameter: Erkennung toter Verbindungen
    tcpOptions.enableKeepalive = true
    tcpOptions.keepaliveIdle = 30       // Sekunden bis erste Keepalive-Probe
    tcpOptions.keepaliveCount = 5       // Anzahl fehlgeschlagener Probes
    tcpOptions.keepaliveInterval = 10   // Sekunden zwischen Probes

    // Retransmission-Timeout: TCP gibt nach 60s auf
    tcpOptions.connectionDropTime = 60

    return tcpOptions
}
```

#### NWPathMonitor fuer Netzwerkschnittstellen-Ueberwachung

Aenderungen am Netzwerkinterface (Kabelabzug, WLAN-Wechsel, MTU-Aenderung) werden ueber `NWPathMonitor` erkannt und an die Session-Schicht weitergegeben:

```swift
/// Ueberwacht Netzwerkschnittstellen-Aenderungen und benachrichtigt die Session
actor NetworkInterfaceMonitor {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "de.iscsi-initiator.path-monitor")

    func startMonitoring(onChange: @Sendable @escaping (NWPath) -> Void) {
        monitor.pathUpdateHandler = { path in
            onChange(path)
        }
        monitor.start(queue: monitorQueue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }
}
```

#### MTU-Konfiguration

| MTU-Groesse | Bezeichnung | Einsatzgebiet | Konfiguration |
|-------------|-------------|---------------|---------------|
| 1500 Bytes | Standard-Ethernet | Allgemeine Netzwerke, Internet | Standardwert, keine Anpassung noetig |
| 9000 Bytes | Jumbo Frames | Dedizierte iSCSI-Netzwerke, SAN | Muss auf allen Netzwerkgeraeten konfiguriert sein |

> **Hinweis:** Die MTU-Groesse ist vom Benutzer konfigurierbar (`targets.json`). Jumbo Frames (9000 Bytes) reduzieren den TCP/IP-Overhead signifikant, erfordern jedoch, dass **alle** Netzwerkkomponenten (Switch, Target, Initiator) Jumbo Frames unterstuetzen. Bei Fehlkonfiguration fuehrt Path MTU Discovery zu Fragmentierung und Performanceverlust.

### 3.7.2 Multipath-Designskizze (Gap D5)

Die Multipath-Unterstuetzung wird bewusst in Phasen eingefuehrt, um die Komplexitaet der v1.0-Implementierung zu begrenzen und gleichzeitig die Erweiterbarkeit fuer v2.0 sicherzustellen.

#### v1.0: Single Connection per Session

In Version 1.0 unterstuetzt jede iSCSI-Session genau **eine** TCP-Verbindung (Connection ID = 0). Multipath und Multiple Connections per Session (MCS) sind **nicht** implementiert. Die Architektur wird jedoch so gestaltet, dass MCS in v2.0 ohne grundlegende Umstrukturierung ergaenzt werden kann.

#### v2.0: Multipath-Architektur (Designskizze)

Die folgende Designskizze beschreibt die geplante v2.0-Architektur fuer Multipath-Unterstuetzung gemaess RFC 7143 Abschnitt 7.4 (Multiple Connections per Session).

##### MultipathPolicy

```swift
/// Lastverteilungs- und Failover-Richtlinie fuer MCS
enum MultipathPolicy: String, Codable, Sendable {
    /// Round-Robin: PDUs werden abwechselnd ueber alle aktiven Pfade verteilt
    case roundRobin

    /// Failover-Only: Ein primaerer Pfad, sekundaere Pfade nur bei Ausfall
    case failoverOnly

    /// Gewichtete Pfade: Verteilung basierend auf konfigurierbaren Gewichten
    case weightedPaths
}
```

##### ISCSIPathManager Actor

```swift
/// Verwaltet mehrere TCP-Verbindungen innerhalb einer iSCSI-Session (v2.0)
actor ISCSIPathManager {
    /// Alle aktiven Pfade (Connection ID -> Verbindung)
    private var activePaths: [UInt16: ISCSIConnection] = [:]

    /// Aktuelle Multipath-Richtlinie
    private var policy: MultipathPolicy = .failoverOnly

    /// Pfadgesundheitsstatus
    private var pathHealth: [UInt16: PathHealthStatus] = [:]

    /// Naechste verfuegbare Connection ID (CID 0-65534, RFC 7143)
    private var nextCID: UInt16 = 0

    /// Fuegt einen neuen Pfad zur Session hinzu
    func addPath(connection: ISCSIConnection) throws -> UInt16 {
        guard nextCID < 65535 else {
            throw ISCSIError.maxConnectionsReached
        }
        let cid = nextCID
        activePaths[cid] = connection
        pathHealth[cid] = .healthy
        nextCID += 1
        return cid
    }

    /// Entfernt einen Pfad aus der Session
    func removePath(cid: UInt16) async {
        activePaths.removeValue(forKey: cid)
        pathHealth.removeValue(forKey: cid)
    }

    /// Waehlt den naechsten Pfad basierend auf der aktiven Richtlinie
    func selectPath(forTask taskTag: UInt32) throws -> ISCSIConnection {
        let healthyPaths = activePaths.filter { pathHealth[$0.key] == .healthy }
        guard !healthyPaths.isEmpty else {
            throw ISCSIError.noHealthyPathAvailable
        }

        switch policy {
        case .roundRobin:
            // Gleichmaessige Verteilung ueber alle gesunden Pfade
            let index = Int(taskTag) % healthyPaths.count
            return Array(healthyPaths.values)[index]

        case .failoverOnly:
            // Immer den Pfad mit der niedrigsten CID bevorzugen
            return healthyPaths.sorted(by: { $0.key < $1.key }).first!.value

        case .weightedPaths:
            // Gewichtete Auswahl (Gewichte aus Konfiguration)
            return try selectWeightedPath(from: healthyPaths)
        }
    }

    private func selectWeightedPath(
        from paths: [UInt16: ISCSIConnection]
    ) throws -> ISCSIConnection {
        // Gewichtete Auswahl-Implementierung fuer v2.0
        fatalError("Gewichtete Pfadauswahl wird in v2.0 implementiert")
    }
}
```

##### Pfadgesundheits-Ueberwachung

| Status | Bedeutung | Uebergang |
|--------|-----------|-----------|
| `healthy` | Pfad funktionsfaehig, NOP-In/Out erfolgreich | → `degraded` nach 2 fehlgeschlagenen NOP-Pings |
| `degraded` | Pfad antwortet verzoegert oder mit Fehlern | → `healthy` nach 3 erfolgreichen NOP-Pings; → `failed` nach 5 fehlgeschlagenen |
| `failed` | Pfad nicht erreichbar, kein Traffic | → `healthy` nach erfolgreicher Reconnection |

##### Failover-Sequenz

```
1. NWPathMonitor meldet Pfadausfall (oder NOP-In-Timeout)
2. ISCSIPathManager markiert Pfad als `failed`
3. Laufende Tasks auf dem ausgefallenen Pfad werden identifiziert
4. Tasks werden auf gesunde Pfade umgeleitet (Task Reassignment, RFC 7143 §7.2)
5. Reconnection-Versuch fuer den ausgefallenen Pfad startet im Hintergrund
6. Bei erfolgreicher Reconnection: Pfad wird als `healthy` reaktiviert
```

##### MCS-Anforderungen aus RFC 7143 Abschnitt 7.4

| Anforderung | Beschreibung | Implementierungs-Hinweis |
|-------------|-------------|--------------------------|
| Connection ID (CID) | Jede Verbindung hat eine eindeutige CID (0-65534) | `nextCID`-Zaehler im ISCSIPathManager |
| MaxConnections | Ausgehandelter Parameter, begrenzt Anzahl der Verbindungen | Login-Phase: `MaxConnections=1` (v1.0), konfigurierbar (v2.0) |
| Task Allegiance | Ein Task gehoert genau einer Verbindung | Task-Tag → CID-Zuordnung in der Session |
| Task Reassignment | Tasks koennen bei Verbindungsausfall umgezogen werden | Nur bei `ImmediateData=No` sicher moeglich |
| TSIH | Target Session Identifying Handle muss auf allen CIDs gleich sein | Session-weiter TSIH-Wert, beim ersten Login gesetzt |

#### v1.0: Platzhalter-Interfaces fuer zukuenftige Erweiterbarkeit

Die folgenden Protokolle werden in v1.0 definiert, aber nur mit Single-Connection-Semantik implementiert. Sie ermoeglichen eine spaetere Erweiterung auf MCS ohne API-Bruch:

```swift
/// Protokoll fuer die Pfadauswahl (v1.0: triviale Implementierung)
protocol PathSelectionStrategy: Sendable {
    func selectConnection(
        from connections: [UInt16: ISCSIConnection],
        forTask taskTag: UInt32
    ) -> ISCSIConnection?
}

/// v1.0-Implementierung: Immer die einzige Verbindung zurueckgeben
struct SingleConnectionStrategy: PathSelectionStrategy {
    func selectConnection(
        from connections: [UInt16: ISCSIConnection],
        forTask taskTag: UInt32
    ) -> ISCSIConnection? {
        return connections.values.first
    }
}

/// Protokoll fuer die Pfadgesundheitsueberwachung (v1.0: nur ein Pfad)
protocol PathHealthMonitor: Sendable {
    func checkHealth(of connection: ISCSIConnection) async -> PathHealthStatus
}

/// Pfadgesundheitsstatus
enum PathHealthStatus: String, Sendable {
    case healthy
    case degraded
    case failed
}
```

> **Designentscheidung:** Die v1.0-Implementierung verwendet `SingleConnectionStrategy` als einzige Pfadauswahl-Strategie. In v2.0 wird `ISCSIPathManager` diese Strategie durch konfigurierbare Policies ersetzen, ohne dass bestehender Code der Session- oder Transport-Schicht geaendert werden muss.

---

### 3.8 FSKit-Entscheidung (Gap K1)

### Entscheidung: FSKit wird aus der Architektur entfernt

**Status:** Abgeschlossen
**Datum:** 4. Februar 2026

### Begruendung

FSKit ist ein Framework zur Implementierung **neuer** Dateisysteme im User Space (vergleichbar mit FUSE unter Linux). Dieses Projekt benoetigt **kein** neues Dateisystem. Die folgende Analyse zeigt, warum FSKit fuer den iSCSI-Initiator nicht relevant ist:

| Aspekt | FSKit | Unser Ansatz |
|--------|-------|-------------|
| Zweck | Neues Dateisystem implementieren | Existierendes Blockgeraet bereitstellen |
| Anwendungsfall | ext4, btrfs, ZFS im User Space | SCSI-Blockgeraet ueber iSCSI |
| Dateisystem-Erkennung | Eigener FSKit-Server | DiskArbitration (automatisch) |
| Unterstuetzte Formate | Nur das implementierte Format | APFS, HFS+, ExFAT (nativ von macOS) |
| Komplexitaet | Hoch (Dateisystem-Semantik) | Nicht noetig |

### Korrekter Datenpfad (ohne FSKit)

Der DriverKit dext stellt ein virtuelles SCSI-Blockgeraet bereit. Die Kernel-Frameworks von Apple uebernehmen automatisch die Erkennung und das Mounten des Dateisystems:

```
DriverKit dext (Virtual SCSI HBA)
    |
    |  IOUserSCSIParallelInterfaceController meldet virtuellen SCSI-Bus
    v
IOSCSIParallelFamily (Kernel)
    |
    |  Erstellt automatisch SCSI-Target-Device-Nubs fuer erkannte LUNs
    v
IOSCSIBlockCommandsDevice (Kernel)
    |
    |  Stellt Block-Device-Semantik bereit (/dev/diskN)
    v
DiskArbitration (auto-discover & mount)
    |
    |  Erkennt Dateisystem (APFS, HFS+, ExFAT) und mountet automatisch
    v
Finder / Disk Utility
    Der Benutzer sieht die iSCSI-Disk wie eine lokale Festplatte
```

### Detaillierte Begruendung pro Schicht

- **IOSCSIParallelFamily:** Apple-Kernel-Framework, das automatisch SCSI-Target-Device-Nubs erzeugt, sobald der DriverKit dext einen virtuellen SCSI-Bus bereitstellt. Keine manuelle Konfiguration noetig.
- **IOSCSIBlockCommandsDevice:** Behandelt die Block-Device-Semantik (READ/WRITE/INQUIRY/READ CAPACITY). Erzeugt automatisch ein `/dev/diskN`-Geraet.
- **DiskArbitration:** macOS-Systemdienst, der neue Block-Devices automatisch erkennt, das Dateisystem identifiziert und (wenn moeglich) mountet. Unterstuetzt nativ: APFS, HFS+, ExFAT, FAT32, ISO 9660.

### Wann waere FSKit relevant?

FSKit waere **nur** relevant, wenn das Projekt Dateisysteme unterstuetzen muesste, die macOS nativ nicht kennt:

- ext4 (Linux)
- btrfs (Linux)
- XFS (Linux)
- NTFS (schreibend, ueber macOS 15+ mit FSKit moeglich)

**Dies ist kein Ziel fuer Version 1.0.** Falls zukuenftig ext4-Unterstuetzung benoetigt wird, kann FSKit als separates Modul ergaenzt werden, ohne die Kernarchitektur zu aendern.

### Erforderliche Aenderungen an der Architektur-Uebersicht

Die folgenden Anpassungen an Section 3.1 sind noetig:

| Stelle | Vorher | Nachher |
|--------|--------|---------|
| Architektur-Diagramm (Zeile "FSKit / DiskArbitration") | `FSKit / DiskArbitration` | `DiskArbitration` |
| Technologie-Stack (Section 6) | FSKit als Zeile vorhanden | Zeile entfernen |
| Plattform-Tabelle (Section 6) | macOS 15: "FSKit + DriverKit" | macOS 15: "DriverKit" |
| Komponentenbeschreibung | Verweis auf FSKit | Verweis entfernen, DiskArbitration erwaehnen |

### Zusammenfassung

```
ENTFERNT:  FSKit (nicht benoetigt, falscher Anwendungsfall)
BEHALTEN:  DiskArbitration (automatische Dateisystem-Erkennung und Mount)
ERGEBNIS:  Einfachere Architektur, weniger Abhaengigkeiten, breitere macOS-Kompatibilitaet
           (DiskArbitration existiert seit macOS 10.4, FSKit erst ab macOS 15)
```

### 3.8.1 DiskArbitration-Integration (Gap K2)

Nachdem FSKit aus der Architektur entfernt wurde (siehe 3.8), uebernimmt das DiskArbitration-Framework die vollstaendige Verantwortung fuer die automatische Erkennung und das Mounten von iSCSI-Blockgeraeten. Dieser Abschnitt beschreibt den detaillierten Integrationsablauf.

#### Schritt-fuer-Schritt-Ablauf: Vom Block-Device zum gemounteten Volume

```
Schritt 1: DriverKit dext meldet virtuellen SCSI-Bus
           IOUserSCSIParallelInterfaceController.start() erfolgreich
                |
                v
Schritt 2: IOSCSIParallelFamily erzeugt Target-Device-Nub
           Kernel erstellt automatisch IOSCSITargetDevice fuer jede erkannte LUN
                |
                v
Schritt 3: IOSCSIBlockCommandsDevice erstellt Block-Device
           /dev/diskN wird im System registriert (sichtbar via diskutil list)
                |
                v
Schritt 4: DiskArbitration erkennt neues Block-Device
           DADiskAppearedCallback wird ausgeloest
                |
                v
Schritt 5: Dateisystem-Erkennung
           DiskArbitration identifiziert das Dateisystem (APFS, HFS+, ExFAT)
                |
                v
Schritt 6: Auto-Mount (falls konfiguriert)
           Volume wird unter /Volumes/<VolumeName> eingehaengt
                |
                v
Schritt 7: Benutzerbenachrichtigung
           Finder zeigt das Volume an, iscsiadm meldet Mount-Status
```

#### DiskArbitrationManager Actor

```swift
/// Verwaltet die DiskArbitration-Integration fuer iSCSI-Blockgeraete
actor DiskArbitrationManager {
    /// Aktive DiskArbitration-Session
    private var daSession: DASession?

    /// Zuordnung: BSD-Name (/dev/diskN) -> iSCSI-Target-IQN
    private var bsdNameToTarget: [String: String] = [:]

    /// Zuordnung: BSD-Name -> Mount-Punkt
    private var mountedVolumes: [String: String] = [:]

    /// Initialisiert die DiskArbitration-Session und registriert Callbacks
    func initialize() throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw ISCSIError.diskArbitrationSessionFailed
        }
        self.daSession = session

        // Session auf dem Main-RunLoop einplanen
        DASessionScheduleWithRunLoop(
            session,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        // Callbacks fuer Disk-Ereignisse registrieren
        registerCallbacks(session: session)
    }

    /// Registriert DADiskAppearedCallback und DADiskDisappearedCallback
    private func registerCallbacks(session: DASession) {
        // Callback: Neues Block-Device erkannt
        DARegisterDiskAppearedCallback(
            session,
            nil,  // Matching-Dictionary: nil = alle Disks
            { disk, context in
                // BSD-Name extrahieren und mit iSCSI-Session abgleichen
                guard let bsdName = DADiskGetBSDName(disk) else { return }
                let name = String(cString: bsdName)
                // Weiterleitung an den Actor ueber detached Task
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .diskAppeared,
                        object: nil,
                        userInfo: ["bsdName": name]
                    )
                }
            },
            nil  // Context
        )

        // Callback: Block-Device entfernt
        DARegisterDiskDisappearedCallback(
            session,
            nil,  // Matching-Dictionary: nil = alle Disks
            { disk, context in
                guard let bsdName = DADiskGetBSDName(disk) else { return }
                let name = String(cString: bsdName)
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .diskDisappeared,
                        object: nil,
                        userInfo: ["bsdName": name]
                    )
                }
            },
            nil  // Context
        )
    }

    /// Wird aufgerufen wenn ein neues Block-Device erscheint
    func onDiskAppeared(bsdName: String, targetIQN: String) async {
        bsdNameToTarget[bsdName] = targetIQN
        // Auto-Mount pruefen (targets.json Konfiguration)
        if shouldAutoMount(targetIQN: targetIQN) {
            await mountDisk(bsdName: bsdName)
        }
    }

    /// Mountet ein iSCSI-Block-Device
    func mountDisk(bsdName: String) async {
        guard let session = daSession else { return }
        guard let disk = DADiskCreateFromBSDName(
            kCFAllocatorDefault,
            session,
            bsdName
        ) else { return }

        DADiskMount(
            disk,
            nil,  // Mount-Punkt: nil = automatisch unter /Volumes/
            DADiskMountOptions(kDADiskMountOptionDefault),
            { disk, dissenter, context in
                if let dissenter = dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    // Fehlerbehandlung: Mount fehlgeschlagen
                    print("Mount fehlgeschlagen fuer \(disk): Status \(status)")
                } else {
                    // Mount erfolgreich
                    print("Volume erfolgreich gemountet")
                }
            },
            nil  // Context
        )
    }

    /// Unmountet ein iSCSI-Block-Device sicher vor dem Logout
    func unmountDisk(bsdName: String) async throws {
        guard let session = daSession else {
            throw ISCSIError.diskArbitrationSessionFailed
        }
        guard let disk = DADiskCreateFromBSDName(
            kCFAllocatorDefault,
            session,
            bsdName
        ) else {
            throw ISCSIError.diskNotFound(bsdName)
        }

        // Force-Unmount nur als Fallback, normaler Unmount bevorzugt
        DADiskUnmount(
            disk,
            DADiskUnmountOptions(kDADiskUnmountOptionDefault),
            { disk, dissenter, context in
                if let dissenter = dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    print("Unmount fehlgeschlagen: Status \(status)")
                }
            },
            nil  // Context
        )
    }

    /// Wird bei iSCSI-Session-Logout aufgerufen: Alle Volumes sicher unmounten
    func onSessionLogout(targetIQN: String) async {
        let affectedDisks = bsdNameToTarget
            .filter { $0.value == targetIQN }
            .map { $0.key }

        for bsdName in affectedDisks {
            try? await unmountDisk(bsdName: bsdName)
            bsdNameToTarget.removeValue(forKey: bsdName)
            mountedVolumes.removeValue(forKey: bsdName)
        }
    }

    /// Pruefen ob Auto-Mount in targets.json konfiguriert ist
    private func shouldAutoMount(targetIQN: String) -> Bool {
        // Liest die Auto-Mount-Konfiguration aus targets.json
        // Standard: true (automatisches Mounten aktiviert)
        return true
    }

    /// Aufraeumen bei Deinitialisierung
    func shutdown() {
        if let session = daSession {
            DASessionUnscheduleFromRunLoop(
                session,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
        daSession = nil
    }
}
```

#### BSD-Name-Zuordnung ueber IORegistry

Die Zuordnung zwischen einem iSCSI-Target und dem resultierenden BSD-Namen (`/dev/diskN`) erfolgt ueber den IORegistry-Baum. Der DriverKit dext setzt bei der LUN-Erstellung eine benutzerdefinierte Property (z.B. `iSCSI-Target-IQN`), die spaeter im IORegistry abgefragt werden kann:

| IORegistry-Ebene | Property | Beispielwert |
|-------------------|----------|-------------|
| `IOUserSCSIParallelInterfaceController` | `iSCSI-Target-IQN` | `iqn.2025.com.example:storage` |
| `IOSCSITargetDevice` | `Target Identifier` | SCSI Target ID |
| `IOSCSIBlockCommandsDevice` | `BSD Name` | `disk4` |

#### Unterstuetzte Dateisysteme

| Dateisystem | Unterstuetzung | Lese-/Schreibzugriff | Hinweis |
|-------------|---------------|---------------------|---------|
| APFS | Vollstaendig | Lesen + Schreiben | Empfohlen fuer macOS-Volumes |
| HFS+ | Vollstaendig | Lesen + Schreiben | Kompatibilitaet mit aelteren Systemen |
| ExFAT | Vollstaendig | Lesen + Schreiben | Plattformuebergreifend (Windows/Linux) |
| FAT32 | Vollstaendig | Lesen + Schreiben | Eingeschraenkt auf 4 GB Dateigroesse |
| ext4 / XFS | Nicht nativ | Nicht verfuegbar | Erfordert FSKit-Erweiterung (v2.0+) |

#### Eject-Sicherheit: Immer Unmount vor Logout

> **Kritisch:** Vor jedem iSCSI-Logout **muss** das Volume sicher unmountet werden. Ein Logout ohne vorheriges Unmount fuehrt zu Datenverlust, da offene Dateien und ausstehende Schreibvorgaenge nicht auf das Target zurueckgeschrieben werden. Die Reihenfolge ist zwingend:

```
1. iscsiadm logout --target <IQN>
2. DiskArbitrationManager.onSessionLogout(targetIQN:) wird aufgerufen
3. Alle zugehoerigen Volumes werden ueber DADiskUnmount() unmountet
4. Warten auf erfolgreiche Unmount-Bestaetigung (Callback)
5. Erst dann: iSCSI Logout PDU an das Target senden
6. TCP-Verbindung schliessen
```

> **Fallback:** Falls der normale Unmount fehlschlaegt (z.B. offene Dateien), wird der Benutzer gewarnt. Ein Force-Unmount (`kDADiskUnmountOptionForce`) erfolgt nur auf explizite Bestaetigung, da er zu Datenverlust fuehren kann.

---

## 4. iSCSI Protokoll-Implementierung (RFC 3720/7143)

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


### 4.4 PDU Binaerlayout (Gap C1)

Alle iSCSI-PDUs basieren auf einem gemeinsamen **Basic Header Segment (BHS)** von 48 Bytes.
Alle Mehrbyte-Felder werden in **Big-Endian** (Network Byte Order) kodiert (RFC 7143, Abschnitt 11.2).

#### 4.4.1 Gemeinsame BHS-Struktur (48 Bytes)

```
 Byte 0       1         2         3
 +--------+--------+--------+--------+
 | Opcode | Flags  |   Opcode-spezifisch   |
 +--------+--------+--------+--------+
 | TotalAHSLen    | DataSegmentLength      |
 +--------+--------+--------+--------+
 |               LUN (8 Bytes)             |
 +--------+--------+--------+--------+
 |         Initiator Task Tag              |
 +--------+--------+--------+--------+
 |      Opcode-spezifische Felder          |
 |            (28 Bytes)                   |
 +--------+--------+--------+--------+
```

#### 4.4.2 SCSI Command PDU (Opcode 0x01, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x01` |
| 1 | 1 | Flags | Bit7=F(Final), Bit6=R(Read), Bit5=W(Write), Bit4-3=Reserved, Bit2-0=TaskAttr (00=Untagged, 01=Simple, 02=Ordered, 03=HeadOfQueue, 04=ACA) |
| 2-3 | 2 | Reserved | Muss `0x0000` sein |
| 4 | 1 | TotalAHSLength | Gesamtlaenge aller AHS in 4-Byte-Woertern |
| 5-7 | 3 | DataSegmentLength | Laenge des Datensegments (24-Bit, max 16 MiB) |
| 8-15 | 8 | LUN | Logical Unit Number |
| 16-19 | 4 | Initiator Task Tag | Eindeutige Task-ID vom Initiator |
| 20-23 | 4 | Expected Data Transfer Length | Erwartete Transfergroesse |
| 24-27 | 4 | CmdSN | Command Sequence Number |
| 28-31 | 4 | ExpStatSN | Erwartete Status Sequence Number |
| 32-47 | 16 | SCSI CDB | SCSI Command Descriptor Block |

#### 4.4.3 SCSI Response PDU (Opcode 0x21, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x21` |
| 1 | 1 | Flags | Bit7=Reserved, Bit6=BiRead-Residual-Overflow, Bit5=BiRead-Residual-Underflow, Bit4=Residual-Overflow, Bit3=Residual-Underflow, Bit2-0=Reserved |
| 2 | 1 | Response | iSCSI-Service-Response (0x00=Command Completed, 0x01=Target Failure) |
| 3 | 1 | Status | SCSI-Status (0x00=GOOD, 0x02=CHECK CONDITION, 0x08=BUSY, 0x18=RESERVATION CONFLICT, 0x28=TASK SET FULL) |
| 4 | 1 | TotalAHSLength | Gesamtlaenge aller AHS |
| 5-7 | 3 | DataSegmentLength | Laenge der Sense-Daten |
| 8-15 | 8 | Reserved | Muss `0` sein |
| 16-19 | 4 | Initiator Task Tag | Kopie vom SCSI Command |
| 20-23 | 4 | SNACK Tag | Reserved / SNACK-Referenz |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN (Command Window) |
| 36-39 | 4 | ExpDataSN | Erwartete DataSN |
| 40-43 | 4 | BiRead-Residual Count | Nur bei bidirektionalem Read |
| 44-47 | 4 | Residual Count | Residual-Zaehler |

#### 4.4.4 Login Request PDU (Opcode 0x03, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x03` |
| 1 | 1 | Flags | Bit7=T(Transit), Bit6=C(Continue), Bit5-4=Reserved, Bit3-2=CSG (Current Stage), Bit1-0=NSG (Next Stage) |
| 2 | 1 | VersionMax | Hoechste unterstuetzte Protokollversion (0x00) |
| 3 | 1 | VersionMin | Niedrigste unterstuetzte Protokollversion (0x00) |
| 4 | 1 | TotalAHSLength | Muss `0` sein fuer Login |
| 5-7 | 3 | DataSegmentLength | Laenge der Key-Value-Paare |
| 8-13 | 6 | ISID | Initiator Session Identifier (6 Bytes) |
| 14-15 | 2 | TSIH | Target Session Identifying Handle (0 bei neuer Session) |
| 16-19 | 4 | Initiator Task Tag | Eindeutige Task-ID |
| 20-21 | 2 | CID | Connection ID innerhalb der Session |
| 22-23 | 2 | Reserved | Muss `0` sein |
| 24-27 | 4 | CmdSN | Initiale CmdSN |
| 28-31 | 4 | ExpStatSN | Erwartete StatSN (0 beim ersten Login) |
| 32-47 | 16 | Reserved | Muss `0` sein |

#### 4.4.5 Login Response PDU (Opcode 0x23, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x23` |
| 1 | 1 | Flags | Bit7=T(Transit), Bit6=C(Continue), Bit5-4=Reserved, Bit3-2=CSG, Bit1-0=NSG |
| 2 | 1 | VersionMax | Hoechste unterstuetzte Version |
| 3 | 1 | VersionActive | Aktive Protokollversion |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge der Key-Value-Paare |
| 8-13 | 6 | ISID | Kopie vom Login Request |
| 14-15 | 2 | TSIH | Target Session Identifying Handle (vom Target zugewiesen) |
| 16-19 | 4 | Initiator Task Tag | Kopie vom Login Request |
| 20-23 | 4 | Reserved | Muss `0` sein |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36 | 1 | Status-Class | 0x00=Success, 0x01=Redirect, 0x02=Initiator Error, 0x03=Target Error |
| 37 | 1 | Status-Detail | Abhaengig von Status-Class |
| 38-47 | 10 | Reserved | Muss `0` sein |

#### 4.4.6 Data-Out PDU (Opcode 0x05, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x05` |
| 1 | 1 | Flags | Bit7=F(Final Data-Out fuer diese Sequenz), Bit6-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge des Datenblocks |
| 8-15 | 8 | LUN | Logical Unit Number |
| 16-19 | 4 | Initiator Task Tag | Referenz auf den SCSI Command |
| 20-23 | 4 | Target Transfer Tag | Vom R2T oder `0xFFFFFFFF` fuer unaufgeforderte Daten |
| 24-27 | 4 | Reserved | Muss `0` sein |
| 28-31 | 4 | ExpStatSN | Erwartete StatSN |
| 32-35 | 4 | Reserved | Muss `0` sein |
| 36-39 | 4 | DataSN | Data Sequence Number (pro R2T-Antwort ab 0) |
| 40-43 | 4 | Buffer Offset | Position innerhalb des Gesamttransfers |
| 44-47 | 4 | Reserved | Muss `0` sein |

#### 4.4.7 Data-In PDU (Opcode 0x25, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x25` |
| 1 | 1 | Flags | Bit7=F(Final), Bit6=Reserved, Bit5=A(Acknowledge), Bit4=Residual-Overflow, Bit3=Residual-Underflow, Bit2=O(Overflow), Bit1=Reserved, Bit0=S(Status, SCSI-Status im Feld Status gueltig) |
| 2 | 1 | Reserved | Muss `0` sein |
| 3 | 1 | Status | SCSI-Status (nur gueltig wenn S-Bit gesetzt) |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge des Datenblocks |
| 8-15 | 8 | LUN | Logical Unit Number |
| 16-19 | 4 | Initiator Task Tag | Referenz auf den SCSI Command |
| 20-23 | 4 | Target Transfer Tag | `0xFFFFFFFF` oder gueltig fuer SNACK |
| 24-27 | 4 | StatSN | Status Sequence Number (nur gueltig wenn S-Bit gesetzt) |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-39 | 4 | DataSN | Data Sequence Number |
| 40-43 | 4 | Buffer Offset | Position innerhalb des Gesamttransfers |
| 44-47 | 4 | Residual Count | Residual-Zaehler (wenn O-Bit oder U-Bit gesetzt) |

#### 4.4.8 R2T PDU - Ready to Transfer (Opcode 0x31, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x31` |
| 1 | 1 | Flags | Bit7=Reserved, Bit6-0=Reserved (alle `0`) |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Muss `0` sein (R2T hat kein Datensegment) |
| 8-15 | 8 | LUN | Logical Unit Number |
| 16-19 | 4 | Initiator Task Tag | Referenz auf den originalen SCSI Write Command |
| 20-23 | 4 | Target Transfer Tag | Vom Target zugewiesener Tag |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-39 | 4 | R2TSN | R2T Sequence Number (pro Task ab 0 aufsteigend) |
| 40-43 | 4 | Buffer Offset | Wo die Daten innerhalb des Gesamttransfers beginnen |
| 44-47 | 4 | Desired Data Transfer Length | Wie viele Bytes das Target erwartet |

#### 4.4.9 NOP-Out PDU (Opcode 0x00, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x00` |
| 1 | 1 | Flags | Bit7=Reserved (immer `1` fuer Immediate), Bit6-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge optionaler Ping-Daten |
| 8-15 | 8 | LUN | Nur gueltig bei Antwort auf NOP-In mit TTT |
| 16-19 | 4 | Initiator Task Tag | `0xFFFFFFFF` fuer Ping ohne Antwort, sonst gueltig |
| 20-23 | 4 | Target Transfer Tag | `0xFFFFFFFF` fuer Initiator-initiiertes NOP, sonst TTT vom NOP-In |
| 24-27 | 4 | CmdSN | Command Sequence Number |
| 28-31 | 4 | ExpStatSN | Erwartete Status Sequence Number |
| 32-47 | 16 | Reserved | Muss `0` sein |

#### 4.4.10 NOP-In PDU (Opcode 0x20, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x20` |
| 1 | 1 | Flags | Bit7=Reserved (immer `1`), Bit6-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge optionaler Ping-Daten |
| 8-15 | 8 | LUN | Kopie vom NOP-Out (falls Antwort) |
| 16-19 | 4 | Initiator Task Tag | `0xFFFFFFFF` bei Target-initiiertem NOP, sonst Kopie |
| 20-23 | 4 | Target Transfer Tag | `0xFFFFFFFF` bei Antwort auf Initiator-NOP, sonst gueltig |
| 24-27 | 4 | StatSN | Status Sequence Number (nur bei Antwort auf ITT != 0xFFFFFFFF) |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-47 | 12 | Reserved | Muss `0` sein |

#### 4.4.11 Text Request PDU (Opcode 0x04, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x04` |
| 1 | 1 | Flags | Bit7=F(Final), Bit6=C(Continue), Bit5-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge der Key-Value-Paare |
| 8-15 | 8 | LUN | Optional, abhaengig vom Kontext |
| 16-19 | 4 | Initiator Task Tag | Eindeutige Task-ID |
| 20-23 | 4 | Target Transfer Tag | `0xFFFFFFFF` beim ersten Request, sonst vom vorherigen Response |
| 24-27 | 4 | CmdSN | Command Sequence Number |
| 28-31 | 4 | ExpStatSN | Erwartete StatSN |
| 32-47 | 16 | Reserved | Muss `0` sein |

#### 4.4.12 Text Response PDU (Opcode 0x24, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x24` |
| 1 | 1 | Flags | Bit7=F(Final), Bit6=C(Continue), Bit5-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge der Key-Value-Paare |
| 8-15 | 8 | LUN | Optional |
| 16-19 | 4 | Initiator Task Tag | Kopie vom Text Request |
| 20-23 | 4 | Target Transfer Tag | `0xFFFFFFFF` wenn F=1, sonst gueltig fuer Fortsetzung |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-47 | 12 | Reserved | Muss `0` sein |

#### 4.4.13 Logout Request PDU (Opcode 0x06, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x06` |
| 1 | 1 | Flags | Bit7=F(Final, immer 1), Bit6-2=Reserved, Bit1-0=Reason Code (0=Session schliessen, 1=Connection schliessen, 2=Connection entfernen fuer Recovery) |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Muss `0` sein |
| 8-15 | 8 | Reserved | Muss `0` sein |
| 16-19 | 4 | Initiator Task Tag | Eindeutige Task-ID |
| 20-21 | 2 | CID | Connection ID (bei Reason 1 und 2) |
| 22-23 | 2 | Reserved | Muss `0` sein |
| 24-27 | 4 | CmdSN | Command Sequence Number |
| 28-31 | 4 | ExpStatSN | Erwartete StatSN |
| 32-47 | 16 | Reserved | Muss `0` sein |

#### 4.4.14 Logout Response PDU (Opcode 0x26, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x26` |
| 1 | 1 | Flags | Bit7=F(Final, immer 1), Bit6-0=Reserved |
| 2 | 1 | Response | 0x00=Session/Connection geschlossen, 0x01=CID nicht gefunden, 0x02=Recovery nicht unterstuetzt, 0x03=Cleanup fehlgeschlagen |
| 3 | 1 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Muss `0` sein |
| 8-15 | 8 | Reserved | Muss `0` sein |
| 16-19 | 4 | Initiator Task Tag | Kopie vom Logout Request |
| 20-23 | 4 | Reserved | Muss `0` sein |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-37 | 2 | Time2Wait | Sekunden bis Reconnect erlaubt |
| 38-39 | 2 | Time2Retain | Sekunden bis Session-Cleanup |
| 40-47 | 8 | Reserved | Muss `0` sein |

#### 4.4.15 Task Management Request PDU (Opcode 0x02, Initiator -> Target)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x02` |
| 1 | 1 | Flags | Bit7=F(Final, immer 1), Bit6-0=Function (1=ABORT TASK, 2=ABORT TASK SET, 3=CLEAR ACA, 4=CLEAR TASK SET, 5=LUN RESET, 6=TARGET WARM RESET, 7=TARGET COLD RESET, 8=TASK REASSIGN) |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Muss `0` sein |
| 8-15 | 8 | LUN | Logical Unit Number |
| 16-19 | 4 | Initiator Task Tag | Eindeutige Task-ID fuer diesen TMF-Request |
| 20-23 | 4 | Referenced Task Tag | Task Tag des abzubrechenden Tasks (fuer ABORT TASK) |
| 24-27 | 4 | CmdSN | Command Sequence Number |
| 28-31 | 4 | ExpStatSN | Erwartete StatSN |
| 32-35 | 4 | RefCmdSN | CmdSN des referenzierten Commands |
| 36-39 | 4 | ExpDataSN | Erwartete DataSN |
| 40-47 | 8 | Reserved | Muss `0` sein |

#### 4.4.16 Task Management Response PDU (Opcode 0x22, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x22` |
| 1 | 1 | Flags | Bit7=Reserved (immer `1`), Bit6-0=Reserved |
| 2 | 1 | Response | 0=Function Complete, 1=Task Not Exist, 2=LUN Not Exist, 3=Task Still Allegiant, 4=Task Reassignment Not Supported, 5=Not Supported, 255=Rejected |
| 3 | 1 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Muss `0` sein |
| 8-15 | 8 | Reserved | Muss `0` sein |
| 16-19 | 4 | Initiator Task Tag | Kopie vom TMF Request |
| 20-23 | 4 | Reserved | Muss `0` sein |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-47 | 12 | Reserved | Muss `0` sein |

#### 4.4.17 Reject PDU (Opcode 0x3F, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x3F` |
| 1 | 1 | Flags | Bit7=Reserved (immer `1`), Bit6-0=Reserved |
| 2 | 1 | Reason | 0x01=Reserved, 0x02=Data Digest Error, 0x03=SNACK Reject, 0x04=Protocol Error, 0x05=Command Not Supported, 0x06=Immediate Command Reject, 0x07=Task In Progress, 0x08=Invalid Data ACK, 0x09=Invalid PDU Field, 0x0A=Long Op Reject, 0x0C=Waiting For Logout |
| 3 | 1 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Immer 48 (enthaelt das BHS des abgelehnten PDUs) |
| 8-15 | 8 | Reserved | Muss `0` sein |
| 16-19 | 4 | Initiator Task Tag | `0xFFFFFFFF` oder Kopie vom abgelehnten PDU |
| 20-23 | 4 | Reserved | Muss `0` sein |
| 24-27 | 4 | StatSN | Status Sequence Number (oder `0xFFFFFFFF`) |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36-39 | 4 | DataSN/R2TSN | Abhaengig vom Kontext |
| 40-47 | 8 | Reserved | Muss `0` sein |

**Datensegment:** Enthaelt das vollstaendige BHS (48 Bytes) des abgelehnten PDUs.

#### 4.4.18 Async Message PDU (Opcode 0x32, Target -> Initiator)

| Offset | Groesse | Feld | Beschreibung |
|--------|---------|------|--------------|
| 0 | 1 | Opcode | `0x32` |
| 1 | 1 | Flags | Bit7=Reserved (immer `1`), Bit6-0=Reserved |
| 2-3 | 2 | Reserved | Muss `0` sein |
| 4 | 1 | TotalAHSLength | Muss `0` sein |
| 5-7 | 3 | DataSegmentLength | Laenge des Sense-Data oder Parameter |
| 8-15 | 8 | LUN | Logical Unit Number (abhaengig vom AsyncEvent) |
| 16-19 | 4 | Initiator Task Tag | `0xFFFFFFFF` |
| 20-23 | 4 | Reserved | Muss `0` sein |
| 24-27 | 4 | StatSN | Status Sequence Number |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN |
| 36 | 1 | AsyncEvent | 0=SCSI Async Event (UA), 1=Logout Request, 2=Connection Drop, 3=Session Drop, 4=Parameter Negotiation, 255=Vendor-specific |
| 37 | 1 | AsyncVCode | Vendor-spezifisch (0 bei Standard-Events) |
| 38-39 | 2 | Parameter1 | Event-abhaengig |
| 40-41 | 2 | Parameter2 | Event-abhaengig |
| 42-43 | 2 | Parameter3 | Event-abhaengig |
| 44-47 | 4 | Reserved | Muss `0` sein |

#### 4.4.19 Swift-Implementierung: BHS mit korrekter 24-Bit DataSegmentLength

```swift
/// Basic Header Segment - gemeinsame 48-Byte-Struktur aller iSCSI-PDUs
struct ISCSIBasicHeaderSegment {
    var opcode: UInt8           // Byte 0
    var flags: UInt8            // Byte 1
    var opcodeSpecific16: UInt16 // Byte 2-3 (opcode-abhaengig)
    var totalAHSLength: UInt8   // Byte 4

    // DataSegmentLength ist 24-Bit: Bytes 5-7
    // Gespeichert als 3 einzelne Bytes, da Swift keinen UInt24-Typ hat
    private var dataSegmentLengthBytes: (UInt8, UInt8, UInt8) // Byte 5, 6, 7

    var lun: UInt64             // Byte 8-15
    var initiatorTaskTag: UInt32 // Byte 16-19
    var opcodeSpecificFields: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    //                         Byte 20-23, 24-27, 28-31, 32-35, 36-39, 40-43, 44-47

    /// DataSegmentLength als UInt32 lesen (nur untere 24 Bit gueltig)
    var dataSegmentLength: UInt32 {
        get {
            return (UInt32(dataSegmentLengthBytes.0) << 16) |
                   (UInt32(dataSegmentLengthBytes.1) << 8)  |
                    UInt32(dataSegmentLengthBytes.2)
        }
        set {
            precondition(newValue <= 0x00FFFFFF, "DataSegmentLength darf maximal 24 Bit sein")
            dataSegmentLengthBytes.0 = UInt8((newValue >> 16) & 0xFF)
            dataSegmentLengthBytes.1 = UInt8((newValue >> 8)  & 0xFF)
            dataSegmentLengthBytes.2 = UInt8( newValue        & 0xFF)
        }
    }

    /// Serialisierung in 48 Bytes (Big-Endian, Network Byte Order)
    func serialize() -> Data {
        var data = Data(capacity: 48)
        data.append(opcode)
        data.append(flags)
        data.append(contentsOf: withUnsafeBytes(of: opcodeSpecific16.bigEndian) { Array($0) })
        data.append(totalAHSLength)
        data.append(dataSegmentLengthBytes.0)
        data.append(dataSegmentLengthBytes.1)
        data.append(dataSegmentLengthBytes.2)
        data.append(contentsOf: withUnsafeBytes(of: lun.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: initiatorTaskTag.bigEndian) { Array($0) })
        // Opcode-spezifische Felder (7 x UInt32 = 28 Bytes)
        let fields = [opcodeSpecificFields.0, opcodeSpecificFields.1,
                      opcodeSpecificFields.2, opcodeSpecificFields.3,
                      opcodeSpecificFields.4, opcodeSpecificFields.5,
                      opcodeSpecificFields.6]
        for field in fields {
            data.append(contentsOf: withUnsafeBytes(of: field.bigEndian) { Array($0) })
        }
        assert(data.count == 48, "BHS muss exakt 48 Bytes sein")
        return data
    }

    /// Deserialisierung aus 48 Bytes
    static func deserialize(from data: Data) throws -> ISCSIBasicHeaderSegment {
        guard data.count >= 48 else {
            throw ISCSIError.pduTooShort(expected: 48, actual: data.count)
        }
        var bhs = ISCSIBasicHeaderSegment(
            opcode: data[0],
            flags: data[1],
            opcodeSpecific16: UInt16(data[2]) << 8 | UInt16(data[3]),
            totalAHSLength: data[4],
            dataSegmentLengthBytes: (data[5], data[6], data[7]),
            lun: data.readUInt64BigEndian(at: 8),
            initiatorTaskTag: data.readUInt32BigEndian(at: 16),
            opcodeSpecificFields: (
                data.readUInt32BigEndian(at: 20),
                data.readUInt32BigEndian(at: 24),
                data.readUInt32BigEndian(at: 28),
                data.readUInt32BigEndian(at: 32),
                data.readUInt32BigEndian(at: 36),
                data.readUInt32BigEndian(at: 40),
                data.readUInt32BigEndian(at: 44)
            )
        )
        return bhs
    }
}
```

#### 4.4.20 Padding- und Digest-Regeln

**Padding (4-Byte-Ausrichtung):**
- Das Datensegment wird auf eine 4-Byte-Grenze aufgefuellt (Null-Bytes).
- Berechnungsformel: `paddedLength = (dataSegmentLength + 3) & ~3`
- Die Padding-Bytes zaehlen NICHT zur `DataSegmentLength`.

```swift
/// Berechnet die aufgefuellte Laenge fuer 4-Byte-Alignment
func paddedLength(_ length: UInt32) -> UInt32 {
    return (length + 3) & ~3
}
```

**PDU-Gesamtstruktur im Speicher:**

```
+--------------------+
| BHS (48 Bytes)     |  <- Immer vorhanden
+--------------------+
| AHS (variabel)     |  <- Optional, Laenge = TotalAHSLength * 4
+--------------------+
| Header Digest      |  <- Optional, 4 Bytes CRC32C (nach BHS+AHS)
| (4 Bytes CRC32C)   |
+--------------------+
| Data Segment       |  <- Optional, Laenge = DataSegmentLength
| (variabel)         |
+--------------------+
| Padding            |  <- 0-3 Bytes Null-Padding auf 4-Byte-Grenze
+--------------------+
| Data Digest        |  <- Optional, 4 Bytes CRC32C (nach Daten + Padding)
| (4 Bytes CRC32C)   |
+--------------------+
```

**Digest-Positionen:**
- **HeaderDigest:** Berechnet ueber BHS + alle AHS, steht direkt nach AHS (oder nach BHS falls kein AHS).
- **DataDigest:** Berechnet ueber das Datensegment inkl. Padding, steht nach dem aufgefuellten Datensegment.
- Beide Digests sind optional und werden waehrend der Login-Phase verhandelt (`HeaderDigest=CRC32C` / `DataDigest=CRC32C`).

---

### 4.5 Login-Zustandsmaschine (Gap C2)

Die iSCSI-Login-Phase ist eine mehrstufige Verhandlung zwischen Initiator und Target.
Sie folgt einer definierten Zustandsmaschine mit strengen Uebergangsregeln gemaess RFC 7143, Abschnitt 6.

#### 4.5.1 Zustandsdefinitionen

| Zustand | Bezeichnung | CSG-Wert | Beschreibung |
|---------|-------------|----------|--------------|
| S0 | `idle` | -- | Keine Login-Verhandlung aktiv. TCP-Verbindung steht oder wird aufgebaut. |
| S1 | `securityNegotiation` | 0 | Austausch von Authentifizierungsparametern (CHAP, SRP usw.) |
| S2 | `loginOperationalNegotiation` | 1 | Austausch operativer Session-/Verbindungsparameter |
| S3 | `fullFeaturePhase` | 3 | Login erfolgreich abgeschlossen. SCSI-Befehle moeglich. |
| S4 | `failed` | -- | Login abgelehnt, Timeout oder Protokollfehler. |

**Hinweis:** CSG-Wert `2` ist gemaess RFC reserviert und darf nicht verwendet werden.

#### 4.5.2 Login-PDU-Steuerfelder

| Feld | Bits | Position | Beschreibung |
|------|------|----------|--------------|
| CSG (Current Stage) | 2 | Byte 1, Bit3-2 | Aktuelle Verhandlungsstufe: 0=Security, 1=Operational, 3=FullFeature |
| NSG (Next Stage) | 2 | Byte 1, Bit1-0 | Naechste gewuenschte Stufe (nur gueltig wenn T=1) |
| T (Transit) | 1 | Byte 1, Bit7 | `1` = Bereit fuer Uebergang zu NSG, `0` = Verbleib in CSG |
| C (Continue) | 1 | Byte 1, Bit6 | `1` = Weitere Key-Value-Paare folgen in naechstem PDU, `0` = Letztes Login-PDU dieser Runde |

**Status-Class und Status-Detail:**

| Status-Class | Bedeutung | Typische Details |
|-------------|-----------|------------------|
| 0x00 | Success | 0x00 = Login erfolgreich |
| 0x01 | Redirection | 0x01 = temporaere Umleitung, 0x02 = permanente Umleitung |
| 0x02 | Initiator Error | 0x00 = Init Error, 0x01 = Auth Failure, 0x02 = Forbidden, 0x03 = Target Not Found, 0x04 = Target Removed, 0x05 = Unsupported Version, 0x06 = Too Many Connections, 0x07 = Missing Parameter, 0x08 = Cant Include In Session, 0x09 = Session Type Not Supported, 0x0A = Session Not Found, 0x0B = Invalid During Login |
| 0x03 | Target Error | 0x00 = Target Error, 0x01 = Service Unavailable, 0x02 = Out Of Resources |

#### 4.5.3 ISID-Generierungsstrategie

Die ISID (Initiator Session ID) ist 6 Bytes lang und muss pro Session eindeutig sein:

```
 Byte 0       1         2         3         4         5
 +--------+--------+--------+--------+--------+--------+
 |  T(2)  |   A    |   B    |   C    |   D(2 Bytes)    |
 +--------+--------+--------+--------+--------+--------+
```

| Feld | Groesse | Empfohlener Wert |
|------|---------|-----------------|
| T (Typ) | 2 Bit | `0x00` (OUI), `0x02` (random), `0x03` (EN-basiert) |
| A | 6 Bit + 1 Byte | Abhaengig vom Typ T |
| B | 2 Bytes | Qualifier (z.B. Prozess-ID oder Zufallswert) |
| C | 1 Byte | Qualifier |
| D | 2 Bytes | Qualifier |

**Empfehlung fuer unsere Implementierung:** Typ `0x02` (Random) mit kryptographisch sicherem Zufallsgenerator (`SecRandomCopyBytes`), um Kollisionen zu vermeiden.

```swift
/// Generiert eine eindeutige ISID fuer eine neue Session
func generateISID() -> (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) {
    var bytes = [UInt8](repeating: 0, count: 6)
    _ = SecRandomCopyBytes(kSecRandomDefault, 6, &bytes)
    // Typ-Feld auf 0x02 (Random) setzen: obere 2 Bits von Byte 0
    bytes[0] = (0x80) | (bytes[0] & 0x3F) // T=10 (0x02) in den oberen 2 Bits
    return (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5])
}
```

**TSIH (Target Session Identifying Handle):**
- `0x0000` bei einer neuen Session (erster Login)
- Wert aus vorheriger Login Response bei Session-Reinstatement

#### 4.5.4 Zustandsdiagramm

```
                    +--------------+
                    |   S0: idle   |
                    +------+-------+
                           | TCP verbunden,
                           | Login Request senden
                           v
          +----------------------------------------+
          |                                        |
          v                                        v
+---------------------+              +------------------------------+
| S1: securityNeg     |              | S2: loginOperationalNeg      |
| (CSG=0)             |              | (CSG=1)                      |
|                     |              |                              |
| C=1: weitere Paare  |--(loop)--+  | C=1: weitere Paare --(loop)  |
| T=0: in CSG bleiben |          |  | T=0: in CSG bleiben          |
| T=1,NSG=1: weiter   |----------+->| T=1,NSG=3: weiter            |
| T=1,NSG=3: direkt   |------+  |  |                              |
|                     |      |  |  |                              |
+--------+------------+      |  |  +--------------+---------------+
         |                   |  |                  |
         | Status-Class!=0   |  |                  | T=1, NSG=3,
         v                   |  |                  | Status-Class=0
+---------------------+      |  |                  v
| S4: failed          |<-----+--+--(Status!=0)-----+
|                     |      |  |                  |
| - Timeout           |      |  |  +---------------+
| - Auth-Fehler       |      |  |  |
| - Protokollfehler   |      |  |  v
+---------------------+      |  |  +------------------------------+
                             +--+->| S3: fullFeaturePhase (CSG=3) |
                                |  |                              |
                                |  | Login abgeschlossen.         |
                                |  | SCSI-Befehle moeglich.       |
                                |  +------------------------------+
                                |
                                +--(C=1 Loop innerhalb S1)
```

#### 4.5.5 Uebergangstabelle

| Von | Nach | Bedingung | Aktion |
|-----|------|-----------|--------|
| S0 (idle) | S1 (securityNeg) | TCP-Verbindung steht, CHAP konfiguriert | Login Request senden mit CSG=0, NSG=0 oder NSG=1 |
| S0 (idle) | S2 (loginOpNeg) | TCP-Verbindung steht, keine Auth noetig | Login Request senden mit CSG=1, NSG=1 oder NSG=3 |
| S1 (securityNeg) | S1 (securityNeg) | Response: Status-Class=0, T=0 oder C=1 | Naechste Auth-Runde senden |
| S1 (securityNeg) | S2 (loginOpNeg) | Response: Status-Class=0, T=1, NSG=1 | Operational-Parameter senden, CSG=1 |
| S1 (securityNeg) | S3 (fullFeature) | Response: Status-Class=0, T=1, NSG=3 | Login abgeschlossen (z.B. keine Op-Params noetig) |
| S1 (securityNeg) | S4 (failed) | Response: Status-Class != 0 oder Timeout | Verbindung abbauen, Fehler melden |
| S2 (loginOpNeg) | S2 (loginOpNeg) | Response: Status-Class=0, T=0 oder C=1 | Weitere Parameter verhandeln |
| S2 (loginOpNeg) | S3 (fullFeature) | Response: Status-Class=0, T=1, NSG=3 | Login abgeschlossen |
| S2 (loginOpNeg) | S4 (failed) | Response: Status-Class != 0 oder Timeout | Verbindung abbauen, Fehler melden |

#### 4.5.6 Swift-Implementierung: Login-Zustandsmaschine

```swift
/// Login-Zustaende gemaess RFC 7143 Abschnitt 6
enum LoginState: Equatable {
    case idle
    case securityNegotiation
    case loginOperationalNegotiation
    case fullFeaturePhase
    case failed(LoginError)
}

enum LoginStage: UInt8 {
    case securityNegotiation = 0   // CSG=0
    case operationalNegotiation = 1 // CSG=1
    case fullFeaturePhase = 3       // CSG=3
    // Wert 2 ist reserviert
}

struct LoginError: Equatable {
    let statusClass: UInt8
    let statusDetail: UInt8
    let message: String
}

actor LoginStateMachine {
    private(set) var state: LoginState = .idle
    private var isid: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)?
    private var tsih: UInt16 = 0
    private var currentCmdSN: UInt32 = 1

    /// Startet den Login-Prozess
    func startLogin(authRequired: Bool) -> LoginState {
        guard state == .idle else { return state }
        isid = generateISID()

        if authRequired {
            state = .securityNegotiation
        } else {
            state = .loginOperationalNegotiation
        }
        return state
    }

    /// Verarbeitet eine Login Response vom Target
    func handleLoginResponse(
        statusClass: UInt8,
        statusDetail: UInt8,
        transitBit: Bool,
        continueBit: Bool,
        currentStage: LoginStage,
        nextStage: LoginStage,
        responseTSIH: UInt16
    ) -> LoginState {
        // Fehlschlag pruefen
        guard statusClass == 0x00 else {
            state = .failed(LoginError(
                statusClass: statusClass,
                statusDetail: statusDetail,
                message: "Login abgelehnt: Class=\(statusClass), Detail=\(statusDetail)"
            ))
            return state
        }

        // TSIH uebernehmen
        if responseTSIH != 0 {
            tsih = responseTSIH
        }

        // Continue-Bit: noch mehr Daten in dieser Phase
        if continueBit {
            // Zustand bleibt gleich, weitere PDUs senden/empfangen
            return state
        }

        // Transit-Bit: Uebergang zur naechsten Phase
        if transitBit {
            switch nextStage {
            case .operationalNegotiation:
                state = .loginOperationalNegotiation
            case .fullFeaturePhase:
                state = .fullFeaturePhase
            case .securityNegotiation:
                // Rueckschritt nicht erlaubt
                state = .failed(LoginError(
                    statusClass: 0xFF,
                    statusDetail: 0x00,
                    message: "Ungueltiger Stufenuebergang: Rueckschritt zu Security"
                ))
            }
        }

        return state
    }
}
```

---

### 4.6 Session-Verhandlungsparameter (Gap C3)

Waehrend der Login-Phase (CSG=1, Operational Negotiation) werden Session- und Verbindungsparameter
zwischen Initiator und Target ausgehandelt. Die vollstaendige Parameterliste ist in RFC 7143,
Abschnitt 13 definiert.

#### 4.6.1 Vollstaendige Parametertabelle

| Parameter | Typ | Verhandlung | Default | Bereich | Scope |
|-----------|-----|-------------|---------|---------|-------|
| MaxRecvDataSegmentLength | Numerisch | Declarative | 8192 | 512 bis 2^24-1 | Connection |
| MaxBurstLength | Numerisch | Minimum | 262144 | 512 bis 2^24-1 | Session |
| FirstBurstLength | Numerisch | Minimum | 65536 | 512 bis 2^24-1 | Session |
| MaxConnections | Numerisch | Minimum | 1 | 1-65535 | Session |
| InitialR2T | Boolean | OR | Yes | Yes/No | Session |
| ImmediateData | Boolean | AND | Yes | Yes/No | Session |
| MaxOutstandingR2T | Numerisch | Minimum | 1 | 1-65535 | Session |
| DataPDUInOrder | Boolean | OR | Yes | Yes/No | Session |
| DataSequenceInOrder | Boolean | OR | Yes | Yes/No | Session |
| DefaultTime2Wait | Numerisch | Maximum | 2 | 0-3600 | Session |
| DefaultTime2Retain | Numerisch | Minimum | 20 | 0-3600 | Session |
| ErrorRecoveryLevel | Numerisch | Minimum | 0 | 0-2 | Session |
| HeaderDigest | String-Liste | OR | None | None,CRC32C | Connection |
| DataDigest | String-Liste | OR | None | None,CRC32C | Connection |

#### 4.6.2 Deklarative Parameter (nicht verhandelt)

| Parameter | Typ | Richtung | Beschreibung |
|-----------|-----|----------|--------------|
| TargetName | String | I->T (Request) | iSCSI Qualified Name des Targets (z.B. `iqn.2024-01.com.nas:disk1`) |
| InitiatorName | String | I->T (Request) | IQN des Initiators (z.B. `iqn.2026-02.com.apple:macmini`) |
| SessionType | String | I->T (Request) | `Normal` (Blockdevice) oder `Discovery` (nur SendTargets) |
| TargetAlias | String | T->I (Response) | Freundlicher Name des Targets |
| InitiatorAlias | String | I->T (Request) | Freundlicher Name des Initiators |
| TargetPortalGroupTag | Numerisch | T->I (Response) | Portal Group Tag (16-Bit) |
| TargetAddress | String | T->I (Response) | IP:Port bei Redirect |

#### 4.6.3 Verhandlungsalgorithmen

**Minimum (Numerisch):** Beide Seiten schlagen einen Wert vor; der kleinere Wert gewinnt.
```
Ergebnis = min(Initiator-Vorschlag, Target-Vorschlag)
```

**Maximum (Numerisch):** Beide Seiten schlagen einen Wert vor; der groessere Wert gewinnt.
```
Ergebnis = max(Initiator-Vorschlag, Target-Vorschlag)
```

**OR (Boolean):** Ergebnis ist `Yes`, wenn mindestens eine Seite `Yes` vorschlaegt.
```
Ergebnis = Initiator-Vorschlag || Target-Vorschlag
```

**AND (Boolean):** Ergebnis ist `Yes`, nur wenn beide Seiten `Yes` vorschlagen.
```
Ergebnis = Initiator-Vorschlag && Target-Vorschlag
```

**Declarative:** Kein Verhandeln; jede Seite deklariert ihren eigenen Wert. Der Empfaenger akzeptiert.

**OR (String-Liste):** Der Initiator sendet eine Liste (z.B. `CRC32C,None`), das Target waehlt daraus.

#### 4.6.4 Empfohlene Initiator-Vorschlagswerte

| Parameter | Empfohlener Wert | Begruendung |
|-----------|-----------------|-------------|
| MaxRecvDataSegmentLength | 262144 (256 KiB) | Groessere Segmente reduzieren Overhead |
| MaxBurstLength | 1048576 (1 MiB) | Hoher Durchsatz fuer grosse Transfers |
| FirstBurstLength | 262144 (256 KiB) | Genug fuer initiale Daten vor R2T |
| MaxConnections | 1 | Einfachheit; Multi-Conn spaeter |
| InitialR2T | No | Ermoeglicht unsolicited Data-Out |
| ImmediateData | Yes | Daten direkt mit Command senden |
| MaxOutstandingR2T | 4 | Mehrere parallele R2T-Transfers |
| DataPDUInOrder | Yes | Vereinfacht Reassembly |
| DataSequenceInOrder | Yes | Vereinfacht Reassembly |
| DefaultTime2Wait | 2 | Standard beibehalten |
| DefaultTime2Retain | 20 | Standard beibehalten |
| ErrorRecoveryLevel | 0 | Nur Session Recovery (Stufe 0) fuer V1.0 |
| HeaderDigest | CRC32C,None | CRC32C bevorzugt, None als Fallback |
| DataDigest | CRC32C,None | CRC32C bevorzugt, None als Fallback |

#### 4.6.5 Key-Value-Kodierungsformat

Alle Parameter werden als UTF-8-Zeichenketten im Datensegment der Login/Text-PDUs uebertragen.
Format: `Schluessel=Wert\0` (Null-terminiert).

Beispiel-Datensegment:
```
MaxRecvDataSegmentLength=262144\0MaxBurstLength=1048576\0FirstBurstLength=262144\0
InitialR2T=No\0ImmediateData=Yes\0HeaderDigest=CRC32C,None\0DataDigest=CRC32C,None\0
```

**Kodierungsregeln:**
- Jedes Paar wird durch `\0` (Null-Byte, 0x00) abgeschlossen.
- Keys sind case-sensitiv (gemaess RFC).
- Mehrere Werte in einer Liste werden durch Komma getrennt (z.B. `CRC32C,None`).
- Boolean-Werte: `Yes` oder `No` (exakt, case-sensitiv).
- Numerische Werte: Dezimaldarstellung als ASCII-String.
- Unbekannte Keys muessen mit `NotUnderstood` beantwortet werden.

#### 4.6.6 Swift-Strukturen fuer verhandelte Parameter

```swift
/// Ausgehandelte Parameter auf Session-Ebene (gelten fuer alle Connections)
struct NegotiatedSessionParameters {
    var maxBurstLength: UInt32 = 262144
    var firstBurstLength: UInt32 = 65536
    var maxConnections: UInt16 = 1
    var initialR2T: Bool = true
    var immediateData: Bool = true
    var maxOutstandingR2T: UInt16 = 1
    var dataPDUInOrder: Bool = true
    var dataSequenceInOrder: Bool = true
    var defaultTime2Wait: UInt16 = 2
    var defaultTime2Retain: UInt16 = 20
    var errorRecoveryLevel: UInt8 = 0

    // Deklarative Session-Parameter
    var targetName: String = ""
    var initiatorName: String = ""
    var sessionType: SessionType = .normal
    var targetAlias: String?
    var initiatorAlias: String?
    var targetPortalGroupTag: UInt16 = 0

    enum SessionType: String {
        case normal = "Normal"
        case discovery = "Discovery"
    }
}

/// Ausgehandelte Parameter auf Connection-Ebene (pro TCP-Verbindung)
struct NegotiatedConnectionParameters {
    var maxRecvDataSegmentLength: UInt32 = 8192
    var headerDigest: DigestMethod = .none
    var dataDigest: DigestMethod = .none

    enum DigestMethod: String {
        case none = "None"
        case crc32c = "CRC32C"
    }
}

/// Parser und Builder fuer Key-Value-Paare
struct ISCSIKeyValueCodec {

    /// Kodiert ein Dictionary in ein Null-terminiertes Datensegment
    static func encode(_ parameters: [(String, String)]) -> Data {
        var data = Data()
        for (key, value) in parameters {
            let pair = "\(key)=\(value)\0"
            data.append(contentsOf: pair.utf8)
        }
        return data
    }

    /// Dekodiert ein Null-terminiertes Datensegment in Key-Value-Paare
    static func decode(_ data: Data) -> [(String, String)] {
        var result: [(String, String)] = []
        let string = String(data: data, encoding: .utf8) ?? ""
        let pairs = string.split(separator: "\0", omittingEmptySubsequences: true)
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result.append((String(parts[0]), String(parts[1])))
            }
        }
        return result
    }

    /// Wendet Verhandlungslogik an
    static func negotiate(
        key: String,
        initiatorValue: String,
        targetValue: String,
        rule: NegotiationRule
    ) -> String {
        switch rule {
        case .minimum:
            let i = UInt32(initiatorValue) ?? 0
            let t = UInt32(targetValue) ?? 0
            return String(min(i, t))
        case .maximum:
            let i = UInt32(initiatorValue) ?? 0
            let t = UInt32(targetValue) ?? 0
            return String(max(i, t))
        case .booleanOR:
            return (initiatorValue == "Yes" || targetValue == "Yes") ? "Yes" : "No"
        case .booleanAND:
            return (initiatorValue == "Yes" && targetValue == "Yes") ? "Yes" : "No"
        case .declarative:
            return targetValue  // Target-Wert wird uebernommen
        case .stringListOR:
            // Target waehlt aus Initiator-Liste
            return targetValue
        }
    }

    enum NegotiationRule {
        case minimum, maximum, booleanOR, booleanAND, declarative, stringListOR
    }
}
```

---

### 4.7 Sequenznummern-Verwaltung (Gap C4)

iSCSI verwendet mehrere Sequenznummern zur Sicherstellung der korrekten Reihenfolge,
Flusskontrolle und Fehlererkennung. Alle Sequenznummern sind 32-Bit-Unsigned-Integer
mit Wraparound-Arithmetik gemaess RFC 1982 (Serial Number Arithmetic).

#### 4.7.1 Uebersicht der Sequenznummern

| Sequenznummer | Scope | Zugewiesen von | Beschreibung |
|---------------|-------|----------------|--------------|
| CmdSN | Session | Initiator | Kommando-Reihenfolge; inkrementiert pro nicht-Immediate Command |
| ExpCmdSN | Session | Target | Naechste erwartete CmdSN; dient der Bestaetigungslogik |
| MaxCmdSN | Session | Target | Obere Grenze des Command Window |
| StatSN | Connection | Target | Status-Reihenfolge pro TCP-Verbindung |
| ExpStatSN | Connection | Initiator | Naechste erwartete StatSN; bestaetigt empfangene Responses |
| DataSN | Task | Sender | Sequenznummer fuer Data-In/Data-Out PDUs pro Task |
| R2TSN | Task | Target | Sequenznummer fuer R2T-PDUs pro Task |

#### 4.7.2 Initialisierungsregeln

| Sequenznummer | Initialer Wert | Zeitpunkt |
|---------------|----------------|-----------|
| CmdSN | 1 (oder beliebig, im Login Request) | Nach TCP-Verbindungsaufbau |
| ExpCmdSN | CmdSN aus Login Request | Aus erster Login Response |
| MaxCmdSN | Aus Login Response | Aus erster Login Response |
| StatSN | Aus Login Response | Target beginnt bei Login |
| ExpStatSN | StatSN + 1 (aus Login Response) | Nach letzter Login Response |
| DataSN | 0 | Pro neuem Data-Transfer (Task) |
| R2TSN | 0 | Pro neuem R2T-Zyklus (Task) |

#### 4.7.3 Command Window (Flusskontrolle)

Das Command Window steuert, wie viele Befehle der Initiator senden darf:

```
Window = MaxCmdSN - ExpCmdSN + 1
```

**Sende-Regel:** Ein Befehl darf nur gesendet werden, wenn gilt:
```
ExpCmdSN <= CmdSN <= MaxCmdSN
```

Wobei der Vergleich Serial Number Arithmetic (RFC 1982) verwendet.

**Window geschlossen:** Wenn `CmdSN > MaxCmdSN` (unter Serial Arithmetic), muss der Initiator warten.
Strategie:
1. Warten auf eine Response, die `MaxCmdSN` erhoeht
2. Oder einen NOP-Out senden (als Immediate, verbraucht keine CmdSN), um ein NOP-In mit aktualisiertem `MaxCmdSN` zu erhalten

#### 4.7.4 Serial Number Arithmetic (RFC 1982)

Fuer 32-Bit-Werte gilt Wraparound:

```swift
/// Serial Number Vergleich gemaess RFC 1982 (32-Bit)
/// Gibt true zurueck, wenn sn1 < sn2 unter Beruecksichtigung von Wraparound
func serialNumberLessThan(_ sn1: UInt32, _ sn2: UInt32) -> Bool {
    let diff = Int64(sn1) - Int64(sn2)
    // sn1 < sn2 wenn die Differenz negativ ist (modulo 2^32)
    return (sn1 != sn2) && ((sn2 &- sn1) < 0x80000000)
}

/// sn1 <= sn2
func serialNumberLessOrEqual(_ sn1: UInt32, _ sn2: UInt32) -> Bool {
    return sn1 == sn2 || serialNumberLessThan(sn1, sn2)
}

/// sn1 > sn2
func serialNumberGreaterThan(_ sn1: UInt32, _ sn2: UInt32) -> Bool {
    return serialNumberLessThan(sn2, sn1)
}
```

#### 4.7.5 Regeln fuer Immediate Commands

- Immediate Commands (Bit 6 im Opcode-Byte gesetzt) verbrauchen **keine** CmdSN.
- Sie tragen die aktuelle CmdSN, inkrementieren sie aber nicht.
- Beispiele fuer Immediate Commands: NOP-Out (als Ping), Task Management Request.
- Der Initiator muss sicherstellen, dass `CmdSN` nur fuer Non-Immediate Commands atomar inkrementiert wird.

#### 4.7.6 Thread-Safety-Anforderung

Da mehrere Threads gleichzeitig SCSI-Befehle senden koennen, muss die CmdSN-Zuweisung
atomar erfolgen. Dies ist besonders wichtig bei DriverKit-basierten Implementierungen,
wo SCSI-Tasks aus dem Kernel-Callback-Thread kommen.

#### 4.7.7 Swift-Implementierung: Sequenznummern-Verwaltung

```swift
/// Thread-sichere Verwaltung aller Sequenznummern einer iSCSI-Session
actor ISCSISequenceNumberManager {

    // --- Session-Scope (alle Connections) ---
    private var cmdSN: UInt32 = 1
    private var expCmdSN: UInt32 = 1
    private var maxCmdSN: UInt32 = 1

    // --- Connection-Scope (pro TCP-Verbindung) ---
    private var statSN: UInt32 = 0
    private var expStatSN: UInt32 = 0

    // MARK: - Initialisierung nach Login

    /// Wird aufgerufen, nachdem die letzte Login Response empfangen wurde
    func initializeAfterLogin(
        initialCmdSN: UInt32,
        responseExpCmdSN: UInt32,
        responseMaxCmdSN: UInt32,
        responseStatSN: UInt32
    ) {
        self.cmdSN = initialCmdSN
        self.expCmdSN = responseExpCmdSN
        self.maxCmdSN = responseMaxCmdSN
        self.statSN = responseStatSN
        self.expStatSN = responseStatSN &+ 1 // Naechste erwartete StatSN
    }

    // MARK: - CmdSN-Management

    /// Weist die naechste CmdSN zu (nur fuer Non-Immediate Commands)
    /// Gibt nil zurueck, wenn das Command Window geschlossen ist
    func allocateCmdSN() -> UInt32? {
        guard isCommandWindowOpen() else {
            return nil // Window geschlossen, Aufrufer muss warten
        }
        let assigned = cmdSN
        cmdSN = cmdSN &+ 1 // Wraparound-sicheres Inkrement
        return assigned
    }

    /// Gibt die aktuelle CmdSN zurueck (fuer Immediate Commands, ohne Inkrement)
    func currentCmdSN() -> UInt32 {
        return cmdSN
    }

    /// Prueft, ob das Command Window offen ist
    func isCommandWindowOpen() -> Bool {
        return serialNumberLessOrEqual(cmdSN, maxCmdSN)
    }

    /// Berechnet die aktuelle Window-Groesse
    func commandWindowSize() -> UInt32 {
        if serialNumberLessOrEqual(expCmdSN, maxCmdSN) {
            return maxCmdSN &- expCmdSN &+ 1
        }
        return 0
    }

    // MARK: - Response-Verarbeitung

    /// Aktualisiert Sequenznummern aus einer Target-Response
    func updateFromResponse(
        responseStatSN: UInt32,
        responseExpCmdSN: UInt32,
        responseMaxCmdSN: UInt32
    ) {
        // StatSN verarbeiten
        if responseStatSN == expStatSN {
            expStatSN = responseStatSN &+ 1
        }
        statSN = responseStatSN

        // Command Window aktualisieren
        if serialNumberLessOrEqual(expCmdSN, responseExpCmdSN) {
            expCmdSN = responseExpCmdSN
        }
        if serialNumberLessOrEqual(maxCmdSN, responseMaxCmdSN) {
            maxCmdSN = responseMaxCmdSN
        }
    }

    // MARK: - Serial Number Arithmetic (RFC 1982)

    private func serialNumberLessThan(_ sn1: UInt32, _ sn2: UInt32) -> Bool {
        return (sn1 != sn2) && ((sn2 &- sn1) < 0x80000000)
    }

    private func serialNumberLessOrEqual(_ sn1: UInt32, _ sn2: UInt32) -> Bool {
        return sn1 == sn2 || serialNumberLessThan(sn1, sn2)
    }
}
```

---

### 4.8 R2T und Datentransfer-Protokoll (Gap C5)

Das R2T-Protokoll (Ready to Transfer) steuert den Datentransfer bei iSCSI-Write-Operationen.
Dieses Abschnitt beschreibt den vollstaendigen Ablauf fuer Read- und Write-Transfers
einschliesslich der Sequenzierung und der Per-Task-Zustandsverwaltung.

#### 4.8.1 Write-Transfer-Ablauf

```
 Initiator                                   Target
    |                                           |
    | 1. SCSI Write Command (Opcode 0x01)       |
    |   [F=1, W=1, ExpDataTransferLen=N]        |
    |------------------------------------------>|
    |                                           |
    | 2a. (Optional) Unsolicited Data-Out       |
    |   [Wenn ImmediateData=Yes UND             |
    |    InitialR2T=No]                         |
    |   [Bis zu FirstBurstLength Bytes]         |
    |------------------------------------------>|
    |                                           |
    | 3. R2T (Opcode 0x31)                      |
    |   [R2TSN=0, BufferOffset=X,               |
    |    DesiredDataTransferLength=Y]            |
    |<------------------------------------------|
    |                                           |
    | 4. Data-Out Sequenz (Opcode 0x05)         |
    |   [DataSN=0, BufferOffset=X,              |
    |    Len=MaxRecvDataSegmentLength]           |
    |------------------------------------------>|
    |   [DataSN=1, BufferOffset=X+chunk, ...]   |
    |------------------------------------------>|
    |   [DataSN=n, F=1, letztes Chunk]          |
    |------------------------------------------>|
    |                                           |
    | 5. (Weitere R2Ts moeglich: R2TSN=1,2,...) |
    |<------------------------------------------|
    |   [Data-Out Sequenz fuer jedes R2T]       |
    |------------------------------------------>|
    |                                           |
    | 6. SCSI Response (Opcode 0x21)            |
    |   [Status=GOOD, Residuals]                |
    |<------------------------------------------|
```

**Schritt-fuer-Schritt-Erklaerung:**

1. **SCSI Write Command senden:** Der Initiator sendet einen SCSI Command mit W-Bit=1 und der erwarteten Transfergroesse (`Expected Data Transfer Length`).

2. **Unsolicited Data (optional):**
   - Wenn `ImmediateData=Yes`: Die ersten Daten koennen direkt mit dem Command-PDU gesendet werden (im selben PDU als Datensegment, bis zu `MaxRecvDataSegmentLength`).
   - Wenn zusaetzlich `InitialR2T=No`: Weitere Data-Out PDUs duerfen ohne R2T gesendet werden, bis `FirstBurstLength` erreicht ist.
   - Wenn `InitialR2T=Yes`: Keine unaufgeforderten Daten; warten auf R2T.

3. **R2T vom Target:** Das Target fordert Daten an mit `BufferOffset` (wo im Gesamtbuffer) und `DesiredDataTransferLength` (wie viel).

4. **Data-Out Sequenz:** Der Initiator zerlegt die angeforderten Daten in Chunks der Groesse `MaxRecvDataSegmentLength` und sendet sie mit aufsteigender `DataSN`. Das letzte PDU hat F-Bit=1.

5. **Mehrere R2Ts:** Das Target kann bis zu `MaxOutstandingR2T` R2Ts gleichzeitig aussenden. Jedes R2T hat eine eigene `R2TSN` (pro Task aufsteigend).

6. **SCSI Response:** Nach Abschluss aller Daten sendet das Target die SCSI Response.

#### 4.8.2 R2T PDU Detail-Referenz (Byte 20-47)

| Offset | Groesse | Feld | Bedeutung fuer Write-Flow |
|--------|---------|------|---------------------------|
| 20-23 | 4 | Target Transfer Tag | Muss in allen Data-Out-Antworten kopiert werden |
| 24-27 | 4 | StatSN | Aktuelle Status-SN des Targets |
| 28-31 | 4 | ExpCmdSN | Erwartete CmdSN (Command Window Update) |
| 32-35 | 4 | MaxCmdSN | Maximale CmdSN (Command Window Update) |
| 36-39 | 4 | R2TSN | Laufende Nummer dieses R2T (pro Task: 0, 1, 2, ...) |
| 40-43 | 4 | Buffer Offset | Ab welchem Byte-Offset im Gesamt-Buffer die Daten beginnen |
| 44-47 | 4 | Desired Data Transfer Length | Wie viele Bytes das Target erwartet (max `MaxBurstLength`) |

#### 4.8.3 Data-Out Sequenz-Generierungsalgorithmus

```swift
/// Erzeugt eine Sequenz von Data-Out PDUs als Antwort auf ein R2T
func generateDataOutSequence(
    for r2t: R2TPDU,
    writeData: Data,
    maxRecvDataSegmentLength: UInt32,
    initiatorTaskTag: UInt32,
    lun: UInt64,
    expStatSN: UInt32
) -> [DataOutPDU] {
    var pdus: [DataOutPDU] = []
    let totalLength = r2t.desiredDataTransferLength
    var remainingLength = totalLength
    var currentOffset = r2t.bufferOffset
    var dataSN: UInt32 = 0

    while remainingLength > 0 {
        let chunkSize = min(remainingLength, maxRecvDataSegmentLength)
        let isFinal = (remainingLength - chunkSize) == 0

        let startIndex = Int(currentOffset)
        let endIndex = startIndex + Int(chunkSize)
        let chunkData = writeData[startIndex..<endIndex]

        let pdu = DataOutPDU(
            finalBit: isFinal,
            lun: lun,
            initiatorTaskTag: initiatorTaskTag,
            targetTransferTag: r2t.targetTransferTag,
            expStatSN: expStatSN,
            dataSN: dataSN,
            bufferOffset: currentOffset,
            data: Data(chunkData)
        )
        pdus.append(pdu)

        remainingLength -= chunkSize
        currentOffset += chunkSize
        dataSN += 1
    }

    return pdus
}
```

**Regeln:**
- `DataSN` startet bei 0 fuer jede R2T-Antwort (nicht global pro Task bei Data-Out).
- Das F-Bit (Final) wird nur im letzten Data-Out PDU der Sequenz gesetzt.
- `Target Transfer Tag` muss exakt vom R2T kopiert werden.
- `Buffer Offset` in jedem Data-Out muss korrekt berechnet sein.
- Die Summe aller Data-Out-Laengen muss exakt `DesiredDataTransferLength` ergeben.

#### 4.8.4 Read-Transfer-Ablauf

```
 Initiator                                   Target
    |                                           |
    | 1. SCSI Read Command (Opcode 0x01)        |
    |   [F=1, R=1, ExpDataTransferLen=N]        |
    |------------------------------------------>|
    |                                           |
    | 2. Data-In PDU(s) (Opcode 0x25)           |
    |   [DataSN=0, BufferOffset=0, ...]         |
    |<------------------------------------------|
    |   [DataSN=1, BufferOffset=chunk, ...]     |
    |<------------------------------------------|
    |   [DataSN=n, F=1, S=1, Status=GOOD]      |
    |<------------------------------------------|
```

**Varianten des letzten Data-In PDU:**

| Variante | F-Bit | S-Bit | Status gueltig | Beschreibung |
|----------|-------|-------|----------------|--------------|
| A: Integriert | 1 | 1 | Ja | SCSI Status im letzten Data-In (effizient) |
| B: Separiert | 1 | 0 | Nein | Separates SCSI Response PDU folgt |

**Regeln fuer Data-In:**
- `DataSN` laeuft pro Task aufsteigend (0, 1, 2, ...) ueber alle Data-In PDUs.
- Wenn `DataPDUInOrder=Yes`: Data-In PDUs kommen in aufsteigender Buffer-Offset-Reihenfolge.
- Wenn `DataSequenceInOrder=Yes`: Sequenzen fuer verschiedene R2Ts kommen in Reihenfolge.

#### 4.8.5 Per-Task Zustandsverfolgung

```swift
/// Zustand eines einzelnen SCSI-Tasks mit partiellem Transfer
actor ISCSITaskState {
    let initiatorTaskTag: UInt32
    let lun: UInt64
    let scsiCommand: SCSICommand
    let expectedDataTransferLength: UInt32
    let isWrite: Bool
    let isRead: Bool

    // Daten-Buffer fuer den gesamten Transfer
    private var dataBuffer: Data

    // Write-spezifisch
    private var unsolicitedDataSent: UInt32 = 0
    private var pendingR2Ts: [UInt32: R2TInfo] = [:]  // R2TSN -> Info
    private var nextExpectedR2TSN: UInt32 = 0
    private var totalDataSent: UInt32 = 0

    // Read-spezifisch
    private var nextExpectedDataSN: UInt32 = 0
    private var totalDataReceived: UInt32 = 0

    // Gemeinsam
    private var isComplete: Bool = false
    private var scsiStatus: UInt8?
    private var senseData: Data?

    struct R2TInfo {
        let r2tSN: UInt32
        let targetTransferTag: UInt32
        let bufferOffset: UInt32
        let desiredDataTransferLength: UInt32
        var bytesSent: UInt32 = 0
        var isComplete: Bool = false
    }

    init(tag: UInt32, lun: UInt64, command: SCSICommand,
         transferLength: UInt32, direction: TransferDirection, writeData: Data? = nil) {
        self.initiatorTaskTag = tag
        self.lun = lun
        self.scsiCommand = command
        self.expectedDataTransferLength = transferLength
        self.isWrite = (direction == .write || direction == .bidirectional)
        self.isRead = (direction == .read || direction == .bidirectional)
        self.dataBuffer = writeData ?? Data(count: Int(transferLength))
    }

    enum TransferDirection {
        case read, write, bidirectional, none
    }

    // MARK: - Write-Operationen

    /// Registriert ein empfangenes R2T
    func handleR2T(
        r2tSN: UInt32,
        targetTransferTag: UInt32,
        bufferOffset: UInt32,
        desiredDataTransferLength: UInt32
    ) {
        precondition(r2tSN == nextExpectedR2TSN,
            "R2TSN Reihenfolge verletzt: erwartet \(nextExpectedR2TSN), erhalten \(r2tSN)")

        let info = R2TInfo(
            r2tSN: r2tSN,
            targetTransferTag: targetTransferTag,
            bufferOffset: bufferOffset,
            desiredDataTransferLength: desiredDataTransferLength
        )
        pendingR2Ts[r2tSN] = info
        nextExpectedR2TSN = r2tSN &+ 1
    }

    /// Markiert gesendete Bytes fuer ein R2T
    func recordDataOutSent(r2tSN: UInt32, bytesSent: UInt32) {
        guard var info = pendingR2Ts[r2tSN] else { return }
        info.bytesSent += bytesSent
        totalDataSent += bytesSent
        if info.bytesSent >= info.desiredDataTransferLength {
            info.isComplete = true
        }
        pendingR2Ts[r2tSN] = info
    }

    /// Prueft, ob unsolicited Data gesendet werden darf
    func canSendUnsolicitedData(
        immediateData: Bool,
        initialR2T: Bool,
        firstBurstLength: UInt32
    ) -> UInt32 {
        guard isWrite else { return 0 }
        if initialR2T { return 0 }  // Nur mit R2T senden
        let maxUnsolicited = min(firstBurstLength, expectedDataTransferLength)
        return maxUnsolicited - unsolicitedDataSent
    }

    // MARK: - Read-Operationen

    /// Verarbeitet ein empfangenes Data-In PDU
    func handleDataIn(dataSN: UInt32, bufferOffset: UInt32,
                      data: Data, isFinal: Bool, hasStatus: Bool,
                      status: UInt8?) {
        precondition(dataSN == nextExpectedDataSN,
            "DataSN Reihenfolge verletzt: erwartet \(nextExpectedDataSN), erhalten \(dataSN)")

        // Daten in Buffer schreiben
        let startIndex = Int(bufferOffset)
        let endIndex = startIndex + data.count
        if endIndex <= dataBuffer.count {
            dataBuffer.replaceSubrange(startIndex..<endIndex, with: data)
        }

        totalDataReceived += UInt32(data.count)
        nextExpectedDataSN = dataSN &+ 1

        if isFinal && hasStatus {
            scsiStatus = status
            isComplete = true
        }
    }

    // MARK: - Abschluss

    /// Verarbeitet eine SCSI Response (separates PDU)
    func handleSCSIResponse(status: UInt8, senseData: Data?) {
        self.scsiStatus = status
        self.senseData = senseData
        self.isComplete = true
    }

    /// Task-Status abfragen
    func getStatus() -> (complete: Bool, status: UInt8?,
                         dataSent: UInt32, dataReceived: UInt32) {
        return (isComplete, scsiStatus, totalDataSent, totalDataReceived)
    }

    /// Read-Buffer zurueckgeben
    func getReadData() -> Data {
        return dataBuffer
    }
}
```

### 4.9 CHAP-Authentifizierung (Gap C6)

CHAP (Challenge Handshake Authentication Protocol) wird waehrend der Login-Phase im `SecurityNegotiation`-Zustand verhandelt. Der iSCSI-Standard unterstuetzt unidirektionales und bidirektionales CHAP.

#### Algorithmus-Auswahl

| CHAP_A Wert | Algorithmus | Status |
|-------------|-------------|--------|
| 5 | MD5 (128-bit) | Pflicht (RFC 7143) |
| 7 | SHA-256 (256-bit) | Empfohlen fuer neue Implementierungen |

Der Initiator sendet `AuthMethod=CHAP` im Login-Request. Der Target antwortet mit `AuthMethod=CHAP` bei Akzeptanz oder `Reject` bei Ablehnung.

#### Unidirektionales CHAP (Target authentifiziert Initiator)

```
Initiator                          Target
    |                                  |
    |  Login Req: AuthMethod=CHAP      |
    |--------------------------------->|
    |  Login Resp: AuthMethod=CHAP     |
    |<---------------------------------|
    |                                  |
    |  Login Req: (leer, wartet)       |
    |--------------------------------->|
    |  Login Resp:                     |
    |    CHAP_A=5 (MD5)                |
    |    CHAP_I=<identifier>           |
    |    CHAP_C=<challenge>            |
    |<---------------------------------|
    |                                  |
    |  Login Req:                      |
    |    CHAP_N=<initiator-name>       |
    |    CHAP_R=<response>             |
    |--------------------------------->|
    |  Login Resp: Status=SUCCESS      |
    |<---------------------------------|
```

#### Bidirektionales CHAP (gegenseitige Authentifizierung)

Bei bidirektionalem CHAP sendet der Initiator im gleichen PDU wie `CHAP_R` eine eigene Challenge:

```
    |  Login Req:                      |
    |    CHAP_N=<initiator-name>       |
    |    CHAP_R=<response>             |
    |    CHAP_I=<initiator-id>         |  (eigene ID)
    |    CHAP_C=<initiator-challenge>  |  (eigene Challenge)
    |--------------------------------->|
    |  Login Resp:                     |
    |    CHAP_N=<target-name>          |
    |    CHAP_R=<target-response>      |  (Antwort auf Initiator-Challenge)
    |<---------------------------------|
```

#### Response-Berechnung

```swift
/// CHAP Response berechnen (RFC 1994, RFC 7143 Section 12.1)
///
/// response = HASH(identifier || secret || challenge)
///
/// - identifier: 1 Byte (CHAP_I)
/// - secret: Das gemeinsame Passwort (aus Keychain)
/// - challenge: Mindestens 16 Bytes (CHAP_C)
func computeCHAPResponse(algorithm: CHAPAlgorithm,
                          identifier: UInt8,
                          secret: Data,
                          challenge: Data) -> Data {
    var input = Data()
    input.append(identifier)
    input.append(secret)
    input.append(challenge)

    switch algorithm {
    case .md5:
        return Insecure.MD5.hash(data: input).withUnsafeBytes { Data($0) }
    case .sha256:
        return SHA256.hash(data: input).withUnsafeBytes { Data($0) }
    }
}
```

#### Datentypen

```swift
enum CHAPAlgorithm: UInt8, Sendable {
    case md5 = 5
    case sha256 = 7
}

struct CHAPState: Sendable {
    var algorithm: CHAPAlgorithm?
    var targetIdentifier: UInt8?
    var targetChallenge: Data?
    var initiatorIdentifier: UInt8?
    var initiatorChallenge: Data?
    var isBidirectional: Bool = false
}
```

#### Fehlerbehandlung

| Szenario | iSCSI Status | Swift Error |
|----------|-------------|-------------|
| AuthMethod abgelehnt | Class=0x02, Detail=0x01 | `.authMethodRejected` |
| Falsches Passwort | Class=0x02, Detail=0x01 | `.authenticationFailed` |
| Unbekannter Algorithmus | Class=0x02, Detail=0x02 | `.unsupportedCHAPAlgorithm` |
| Challenge zu kurz (<16 B) | — | `.invalidCHAPChallenge` |
| Target-Verifizierung fehlgeschlagen | — | `.mutualAuthFailed` |

#### Integration mit Login State Machine

CHAP wird im Zustand `securityNegotiation` (CSG=0) ausgefuehrt. Nach erfolgreicher Authentifizierung setzt der Initiator `T-Bit=1` und `NSG=1` (operationalNegotiation), um zur naechsten Phase ueberzugehen.

### 4.10 Fehler-Recovery (Gap C7)

#### Error Recovery Level

| Level | Beschreibung | V1.0 Status |
|-------|-------------|-------------|
| 0 | Session Recovery (Neustart bei jedem Fehler) | **Implementiert** |
| 1 | Digest-basierte Recovery + Task Reassignment | Zukunft |
| 2 | Verbindungs-Recovery innerhalb einer Session | Zukunft |

**Entscheidung:** V1.0 implementiert ausschliesslich Error Recovery Level 0. Dies wird waehrend der Login-Verhandlung mit `ErrorRecoveryLevel=0` deklariert.

#### Level 0 Recovery-Prozedur

```
Fehler erkannt (Timeout, Protokollfehler, Verbindungsabbruch)
    |
    v
1. Alle ausstehenden SCSI-Tasks mit kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE abschliessen
    |
    v
2. Aktive TCP-Verbindung schliessen (NWConnection.cancel())
    |
    v
3. Exponentielles Backoff (gemaess Abschnitt 3.7 Reconnection-Strategie)
    |
    v
4. Neue TCP-Verbindung aufbauen
    |
    v
5. Neuen Login durchfuehren (volle Login-Sequenz inkl. CHAP falls konfiguriert)
    |
    v
6. Session-Parameter neu verhandeln
    |
    v
7. CreateSCSITarget() erneut aufrufen (falls Target verloren gegangen)
    |
    v
8. SCSI-Subsystem informieren → I/O wird automatisch erneut eingereicht
```

#### Timeout-Werte

| Parameter | Wert | Beschreibung |
|-----------|------|-------------|
| `DefaultTime2Wait` | 2 Sekunden | Wartezeit vor Reconnect-Versuch |
| `DefaultTime2Retain` | 20 Sekunden | Wie lange Task-States aufbewahrt werden |
| I/O Timeout | 30 Sekunden | Max. Wartezeit auf SCSI Response |
| Login Timeout | 10 Sekunden | Max. Wartezeit auf Login Response |
| Connection Timeout | 5 Sekunden | Max. TCP-Verbindungsaufbau |

#### Eskalationslogik

```swift
enum RecoveryAction: Sendable {
    case retry          // Einzelnen Task erneut versuchen
    case reconnect      // Verbindung neu aufbauen
    case sessionRestart // Gesamte Session neu starten
    case abort          // Session aufgeben, Benutzer informieren
}

func determineRecoveryAction(error: ISCSIError,
                              retryCount: Int,
                              reconnectCount: Int) -> RecoveryAction {
    switch error {
    case .timeout where retryCount < 3:
        return .retry
    case .timeout, .protocolError, .connectionLost:
        if reconnectCount < 5 {
            return .reconnect
        } else {
            return .sessionRestart
        }
    case .targetNotFound, .authenticationFailed:
        return .abort
    default:
        return .sessionRestart
    }
}
```

---

## 5. Entwicklungsphasen

### Phase 1: Foundation (8-10 Wochen)

#### Milestone 1.1: Projekt-Setup (1 Woche)
- [ ] Xcode-Projekt mit allen Targets erstellen
- [ ] DriverKit Entitlements beantragen (Apple Developer Account)
- [ ] CI/CD Pipeline (GitHub Actions)
- [ ] Dokumentations-Framework aufsetzen

#### Milestone 1.2: DriverKit Extension Grundgerüst (3 Wochen)
- [ ] IOUserSCSIParallelInterfaceController Subklasse (.iig + .cpp)
- [ ] IOUserClient für User-Space-Kommunikation
- [ ] Basic SCSI Command Routing
- [ ] Installation/Aktivierung testen

#### Milestone 1.3: iSCSI Protocol Engine (4 Wochen)
- [ ] PDU Parser/Builder (gemäß Abschnitt 4.4)
- [ ] Basic Header Segment (BHS) Handling
- [ ] Login Phase Implementation (gemäß Abschnitt 4.5)
- [ ] Text Negotiation (SendTargets)

#### Milestone 1.4: Network Layer (2 Wochen)
- [ ] TCP-Verbindung mit Network.framework (gemäß Abschnitt 3.7)
- [ ] Connection State Machine
- [ ] Reconnection Logic

### Phase 2: Core Functionality (8-10 Wochen)

#### Milestone 2.1: Full Login Sequence (2 Wochen)
- [ ] Security Negotiation (CHAP)
- [ ] Operational Negotiation (gemäß Abschnitt 4.6)
- [ ] Full Feature Phase Transition
- [ ] Multi-Connection Session (optional)

#### Milestone 2.2: SCSI Command Processing (4 Wochen)
- [ ] READ/WRITE Commands
- [ ] INQUIRY, READ CAPACITY
- [ ] Request Sense
- [ ] Data-In/Data-Out Handling (gemäß Abschnitt 4.8)
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
- [ ] DiskArbitration Integration (gemäß Abschnitt 3.8)
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
| Build | Swift Package Manager + Xcode | - |
| CI/CD | GitHub Actions | - |

### Unterstützte Plattformen

| macOS Version | Unterstützung | Anmerkung |
|---------------|---------------|-----------|
| macOS 15 (Sequoia) | ✅ Voll | DriverKit |
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

### Hohe Risiken 🔴

| Risiko | Beschreibung | Mitigation |
|--------|--------------|------------|
| **DriverKit Socket-Limitation** | DriverKit hat keinen direkten Socket-Zugriff | User-Space Helper mit Network.framework |
| **Apple Developer Entitlements** | DriverKit erfordert spezielle Entitlements | Frühzeitig beantragen, Fallback planen |
| **Signierung & Notarization** | Unsigned Drivers werden nicht geladen | Apple Developer Program ($99/Jahr) |

### Mittlere Risiken 🟡

| Risiko | Beschreibung | Mitigation |
|--------|--------------|------------|
| **Performance User-Space** | Overhead durch User/Kernel-Transition | Optimiertes Buffer-Management (siehe 3.6) |
| **iSCSI Interoperabilität** | Verschiedene NAS-Implementierungen | Breites Testing (Synology, QNAP, TrueNAS) |
| **macOS Updates** | API-Änderungen in neuen Versionen | Beta-Testing, modulare Architektur |

### Niedrige Risiken 🟢

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
- Zugriff nur ueber den Daemon
- GUI/CLI kommunizieren ausschliesslich ueber XPC

### 9.1 Keychain-Zugriffskonfiguration (Gap J2)

#### Access Group

Alle Komponenten (Daemon, App, CLI) teilen sich die Keychain ueber eine App Group:

```
com.opensource.iscsi    (App Group Identifier)
```

**Entitlements** (in jeder Komponente):
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>com.opensource.iscsi</string>
</array>
```

#### Keychain-Schema

| Attribut | Wert | Beschreibung |
|----------|------|-------------|
| `kSecClass` | `kSecClassGenericPassword` | Passwort-Typ |
| `kSecAttrService` | `com.opensource.iscsi.chap` | Service-Kennung |
| `kSecAttrAccount` | `<target-iqn>` | Target-IQN als Account |
| `kSecAttrAccessGroup` | `com.opensource.iscsi` | Shared Access Group |
| `kSecAttrLabel` | `iSCSI CHAP: <target-iqn>` | Benutzerfreundliches Label |
| `kSecValueData` | `<chap-secret>` | Das CHAP-Passwort (verschluesselt) |

#### API-Muster

```swift
actor KeychainManager {
    private let service = "com.opensource.iscsi.chap"
    private let accessGroup = "com.opensource.iscsi"

    func saveCredential(targetIQN: String, secret: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: targetIQN,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrLabel as String: "iSCSI CHAP: \(targetIQN)",
            kSecValueData as String: secret
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existierender Eintrag
            let update: [String: Any] = [kSecValueData as String: secret]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ISCSIError.keychainWriteError(updateStatus)
            }
        } else if status != errSecSuccess {
            throw ISCSIError.keychainWriteError(status)
        }
    }

    func loadCredential(targetIQN: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: targetIQN,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ISCSIError.keychainReadError(status)
        }
        return result as? Data
    }

    func deleteCredential(targetIQN: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: targetIQN,
            kSecAttrAccessGroup as String: accessGroup
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ISCSIError.keychainDeleteError(status)
        }
    }
}
```

### 9.2 Konfigurationsschema (Gap F1)

#### Speicherstrategie

| Konfigurationstyp | Speicherort | Format |
|-------------------|-------------|--------|
| Gespeicherte Targets | `~/Library/Application Support/com.opensource.iscsi/targets.json` | JSON |
| Daemon-Einstellungen | `~/Library/Preferences/com.opensource.iscsi.daemon.plist` | Property List |
| CHAP-Credentials | macOS Keychain | Keychain Items |
| Auto-Connect-Liste | Teil von `targets.json` | JSON |

#### Target-Konfiguration (targets.json)

```json
{
    "version": 1,
    "targets": [
        {
            "id": "uuid-string",
            "portalAddress": "192.168.1.100",
            "portalPort": 3260,
            "targetIQN": "iqn.2024-01.com.example:storage",
            "initiatorIQN": "iqn.2024-01.com.opensource:initiator",
            "authMethod": "CHAP",
            "chapUsername": "initiator-name",
            "mutualCHAP": false,
            "autoConnect": true,
            "autoConnectDelay": 5,
            "preferredNIC": null,
            "maxConnections": 1,
            "headerDigest": "None",
            "dataDigest": "None",
            "tags": ["production", "nas"],
            "lastConnected": "2026-02-04T10:30:00Z",
            "addedAt": "2026-01-15T08:00:00Z"
        }
    ]
}
```

**Validierungsregeln:**
- `portalPort`: 1-65535, Standard 3260
- `targetIQN`: Muss RFC 3721 IQN-Format entsprechen
- `initiatorIQN`: Optional; wird aus System-UUID generiert falls leer
- `chapUsername`: Erforderlich wenn `authMethod` = "CHAP"
- CHAP-Passwort wird NICHT in JSON gespeichert (nur in Keychain)

#### Daemon-Einstellungen

```swift
struct DaemonConfiguration: Codable, Sendable {
    var logLevel: LogLevel = .info
    var maxSessions: Int = 16
    var defaultTimeout: TimeInterval = 30
    var reconnectEnabled: Bool = true
    var maxReconnectAttempts: Int = 5
    var discoveryInterval: TimeInterval = 300  // 5 Minuten
}

enum LogLevel: String, Codable, Sendable {
    case debug, info, warning, error
}
```

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
```

### Beantragungsprozess

1. Apple Developer Program beitreten ($99/Jahr)
2. DriverKit Entitlement beantragen (Formular)
3. Warten auf Apple-Genehmigung (1-4 Wochen)
4. Provisioning Profile erstellen
5. Code signieren und notarisieren

### 10.1 Fehlerkategorien und Fehlerbehandlung (Gap L1)

#### ISCSIError Enum

```swift
/// Zentrale Fehlerhierarchie fuer den gesamten iSCSI-Stack
enum ISCSIError: Error, Sendable {

    // --- Protokoll-Fehler (1xx) ---
    case protocolViolation(String)           // 100: Allgemeiner Protokollfehler
    case invalidPDU(String)                  // 101: PDU-Parsing fehlgeschlagen
    case unexpectedOpcode(UInt8)             // 102: Unerwarteter PDU-Opcode
    case invalidBHS(String)                  // 103: BHS-Validierungsfehler
    case sequenceError(String)               // 104: Sequenznummern-Fenster verletzt
    case loginFailed(statusClass: UInt8,
                     statusDetail: UInt8)    // 105: Login abgelehnt
    case negotiationFailed(String)           // 106: Parameter-Verhandlung gescheitert
    case targetError(response: UInt8)        // 107: Target meldet Fehler
    case digestMismatch                      // 108: Header/Data Digest stimmt nicht

    // --- Netzwerk-Fehler (2xx) ---
    case connectionFailed(String)            // 200: TCP-Verbindung fehlgeschlagen
    case connectionLost                      // 201: Verbindung unerwartet getrennt
    case connectionTimeout                   // 202: Verbindungsaufbau Timeout
    case dnsResolutionFailed(String)         // 203: Hostname nicht aufloesbar
    case tlsError(String)                    // 204: TLS-Handshake fehlgeschlagen
    case networkUnavailable                  // 205: Kein Netzwerk verfuegbar

    // --- Authentifizierungs-Fehler (3xx) ---
    case authMethodRejected                  // 300: AuthMethod nicht akzeptiert
    case authenticationFailed                // 301: CHAP-Verifizierung fehlgeschlagen
    case unsupportedCHAPAlgorithm            // 302: CHAP_A nicht unterstuetzt
    case invalidCHAPChallenge                // 303: Challenge ungueltig (<16 Bytes)
    case mutualAuthFailed                    // 304: Bidirektionale Auth gescheitert
    case credentialNotFound(String)          // 305: Keychain-Eintrag nicht gefunden

    // --- SCSI-Fehler (4xx) ---
    case scsiCheckCondition(senseKey: UInt8,
                            asc: UInt8,
                            ascq: UInt8)     // 400: SCSI Check Condition
    case scsiBusy                            // 401: Target ist busy
    case scsiReservationConflict             // 402: Reservation Conflict
    case scsiTaskSetFull                     // 403: Task Set Full
    case scsiCommandTimeout                  // 404: SCSI Command Timeout

    // --- Konfigurations-Fehler (5xx) ---
    case invalidTargetIQN(String)            // 500: Ungueltiges IQN-Format
    case invalidPortalAddress(String)        // 501: Ungueltige Portal-Adresse
    case configurationCorrupt(String)        // 502: targets.json beschaedigt
    case targetNotConfigured(String)         // 503: Target nicht in Konfiguration

    // --- System-Fehler (6xx) ---
    case driverKitUnavailable                // 600: Dext nicht geladen
    case dextCommunicationFailed(String)     // 601: IOUserClient-Fehler
    case sharedMemoryMapFailed               // 602: Memory Mapping fehlgeschlagen
    case bufferPoolExhausted                 // 603: Alle Datenpuffer belegt
    case keychainReadError(OSStatus)         // 604: Keychain-Lesefehler
    case keychainWriteError(OSStatus)        // 605: Keychain-Schreibfehler
    case keychainDeleteError(OSStatus)       // 606: Keychain-Loeschfehler
    case systemExtensionNotApproved          // 607: Benutzer hat Dext nicht genehmigt
}
```

#### iSCSI Status-Code Mapping

| Status-Class | Status-Detail | Bedeutung | ISCSIError |
|-------------|--------------|-----------|------------|
| 0x00 | 0x00 | Erfolg | — (kein Fehler) |
| 0x01 | 0x01 | Target moved temporarily | `.targetError(0x01)` |
| 0x01 | 0x02 | Target moved permanently | `.targetError(0x02)` |
| 0x02 | 0x00 | Initiator Error (generisch) | `.loginFailed(0x02, 0x00)` |
| 0x02 | 0x01 | Authentication Failure | `.authenticationFailed` |
| 0x02 | 0x02 | Authorization Failure | `.authMethodRejected` |
| 0x02 | 0x03 | Not Found | `.loginFailed(0x02, 0x03)` |
| 0x03 | 0x00 | Target Error (generisch) | `.targetError(0x00)` |
| 0x03 | 0x01 | Service Unavailable | `.targetError(0x01)` |
| 0x03 | 0x02 | Out of Resources | `.targetError(0x02)` |

#### SCSI Status Mapping

| SCSI Status | Bedeutung | ISCSIError |
|------------|-----------|------------|
| 0x00 | GOOD | — (kein Fehler) |
| 0x02 | CHECK CONDITION | `.scsiCheckCondition(...)` |
| 0x08 | BUSY | `.scsiBusy` |
| 0x18 | RESERVATION CONFLICT | `.scsiReservationConflict` |
| 0x28 | TASK SET FULL | `.scsiTaskSetFull` |

#### Recovery-Aktionen pro Fehlertyp

| Fehlerkategorie | Aktion | Max Retries |
|-----------------|--------|-------------|
| Protokoll (1xx) | Session Restart | 3 |
| Netzwerk (2xx) | Reconnect mit Backoff | 5 |
| Auth (3xx) | Abbruch, Benutzer informieren | 0 |
| SCSI (4xx) | Task Retry (CHECK CONDITION, BUSY) | 3 |
| Konfiguration (5xx) | Abbruch, Benutzer informieren | 0 |
| System (6xx) | Abbruch, Logging, Benutzer informieren | 0 |

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
│   │   ├── iSCSIVirtualHBA.iig          <- Interface-Definition
│   │   ├── iSCSIVirtualHBA.cpp          <- Implementierung
│   │   ├── iSCSIUserClient.iig          <- UserClient Interface
│   │   ├── iSCSIUserClient.cpp          <- UserClient Implementierung
│   │   ├── iSCSIUserClientShared.h      <- Gemeinsame Definitionen
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
│   │   ├── DextConnector.swift
│   │   └── ConfigurationStore.swift
│   ├── com.opensource.iscsid.plist
│   └── Entitlements.plist
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
│   │   ├── Session/
│   │   │   ├── ISCSISession.swift
│   │   │   ├── ISCSIConnection.swift
│   │   │   ├── LoginStateMachine.swift
│   │   │   ├── NegotiationParameters.swift
│   │   │   └── SequenceNumberManager.swift
│   │   └── DataTransfer/
│   │       ├── TaskState.swift
│   │       ├── R2THandler.swift
│   │       └── DataOutGenerator.swift
│   └── Tests/
│       ├── PDUTests.swift
│       ├── SCSITests.swift
│       ├── LoginStateMachineTests.swift
│       ├── NegotiationTests.swift
│       └── SessionTests.swift
│
├── Network/
│   ├── Sources/
│   │   ├── ISCSIProtocolFramer.swift
│   │   ├── ISCSIConnectionManager.swift
│   │   ├── ConnectionStateMachine.swift
│   │   ├── ReconnectionStrategy.swift
│   │   └── NetworkMonitor.swift
│   └── Tests/
│       └── FramerTests.swift
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
│   │   ├── SystemExtension/
│   │   │   └── SystemExtensionInstaller.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Localizable.strings
│   ├── Info.plist
│   └── Entitlements.plist
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


### 11.1 Build-System-Konfiguration (Gaps H1, H2)

### Xcode-Projektstruktur

Das Projekt besteht aus 5 primaeren Targets und 2 Test-Targets:

| Target | Typ | Sprache | Bundle ID | Abhaengigkeiten |
|--------|-----|---------|-----------|-----------------|
| iSCSIVirtualHBA | DriverKit System Extension | C++ | `com.opensource.iscsi.virtualHBA` | -- (standalone) |
| iscsid | Command Line Tool | Swift | `com.opensource.iscsi.daemon` | ISCSIProtocol, ISCSINetwork |
| ISCSIProtocol | Swift Package (lokal) | Swift | -- | -- |
| ISCSINetwork | Swift Package (lokal) | Swift | -- | ISCSIProtocol |
| iSCSI Initiator | macOS App | Swift | `com.opensource.iscsi.app` | ISCSIProtocol |
| iscsiadm | Command Line Tool | Swift | `com.opensource.iscsi.cli` | ISCSIProtocol, ArgumentParser |
| ISCSIProtocolTests | XCTest Bundle | Swift | -- | ISCSIProtocol |

### SPM vs. Xcode: Entscheidungsmatrix

| Target | Build-System | Begruendung |
|--------|-------------|-------------|
| ISCSIProtocol | Swift Package Manager | Reines Swift, keine Systemabhaengigkeiten, plattformuebergreifend testbar |
| ISCSINetwork | Swift Package Manager | Reines Swift, abhaengig nur von ISCSIProtocol |
| iSCSIVirtualHBA | Xcode (DriverKit) | Erfordert DriverKit-Build-System, C++, `.iig`-Dateien -- SPM nicht moeglich |
| iscsid | Xcode Target | Benoetigt IOKit-C-Header, abhaengig von lokalen SPM-Paketen |
| iSCSI Initiator | Xcode Target | SwiftUI, App-Bundle-Struktur, Entitlements |
| iscsiadm | Xcode Target + SPM | Nutzt Swift Argument Parser ueber SPM-Abhaengigkeit |

### Root Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iSCSIInitiator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ISCSIProtocol", targets: ["ISCSIProtocol"]),
        .library(name: "ISCSINetwork", targets: ["ISCSINetwork"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ISCSIProtocol",
            path: "Protocol/Sources"
        ),
        .target(
            name: "ISCSINetwork",
            dependencies: ["ISCSIProtocol"],
            path: "Network/Sources"
        ),
        .testTarget(
            name: "ISCSIProtocolTests",
            dependencies: ["ISCSIProtocol"],
            path: "Protocol/Tests"
        ),
        .testTarget(
            name: "ISCSINetworkTests",
            dependencies: ["ISCSINetwork"],
            path: "Network/Tests"
        ),
    ]
)
```

### DriverKit Build Settings

Die DriverKit-Extension erfordert spezifische Xcode-Build-Einstellungen, die sich vom normalen macOS-Target unterscheiden:

| Build Setting | Wert | Anmerkung |
|--------------|------|-----------|
| `SDKROOT` | `driverkit` | DriverKit-SDK statt macOS-SDK |
| `DRIVERKIT_DEPLOYMENT_TARGET` | `21.0` | Minimale DriverKit-Version |
| `SYSTEM_EXTENSION_API_DIR` | `/System/Library/Frameworks/DriverKit.framework` | DriverKit-Framework-Pfad |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.opensource.iscsi.virtualHBA` | Muss mit Entitlements uebereinstimmen |
| `INFOPLIST_FILE` | `Driver/iSCSIVirtualHBA/Info.plist` | DriverKit-spezifische Info.plist |
| `CODE_SIGN_ENTITLEMENTS` | `Driver/iSCSIVirtualHBA/Entitlements.plist` | DriverKit + SCSI Entitlements |
| `CLANG_CXX_LANGUAGE_STANDARD` | `c++20` | C++20 fuer DriverKit |
| `SKIP_INSTALL` | `NO` | Extension muss im App-Bundle installiert werden |

### Target-Abhaengigkeitsgraph

```
iSCSIVirtualHBA (dext) ──── standalone, keine Swift-Abhaengigkeiten
                             (C++, DriverKit-SDK, eigenes Build-System)

iscsid ─────────────────┬── ISCSIProtocol (SPM)
                        └── ISCSINetwork (SPM)
                             + IOKit.framework (System)

iSCSI Initiator (app) ──┬── ISCSIProtocol (SPM)
                         └── iSCSIVirtualHBA.dext (eingebettet in App-Bundle)

iscsiadm (CLI) ─────────┬── ISCSIProtocol (SPM)
                         └── ArgumentParser (SPM, extern)
```

**Hinweis:** Die App `iSCSI Initiator` bettet die DriverKit-Extension `iSCSIVirtualHBA.dext` in ihr App-Bundle ein (`Contents/Library/SystemExtensions/`). Die Aktivierung der System Extension erfolgt ueber `OSSystemExtensionRequest` zur Laufzeit.

### Entitlement-Dateien pro Target

Jedes Target benoetigt spezifische Entitlements:

**Driver/iSCSIVirtualHBA/Entitlements.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.driverkit</key>
    <true/>
    <key>com.apple.developer.driverkit.transport.scsi</key>
    <true/>
    <key>com.apple.developer.driverkit.family.scsi-parallel</key>
    <true/>
    <key>com.apple.developer.driverkit.userclient-access</key>
    <true/>
</dict>
</plist>
```

**Daemon/iscsid/Entitlements.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.developer.driverkit.userclient-access</key>
    <true/>
    <key>com.apple.security.temporary-exception.iokit-user-client-class</key>
    <array>
        <string>iSCSIUserClient</string>
    </array>
</dict>
</plist>
```

**App/iSCSI Initiator/Entitlements.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.developer.system-extension.install</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>com.opensource.iscsi</string>
    </array>
</dict>
</plist>
```

---

---

## 12. Definition of Done (MVP)

- [ ] DriverKit Extension lädt zuverlässig und übersteht Reboots
- [ ] Discovery & Login gegen mindestens ein reales Target
- [ ] READ/WRITE erfolgreich bei einem Blockdevice
- [ ] Volume erscheint stabil in Finder/Disk Utility
- [ ] CLI unterstützt Discovery, Login, Session-Status
- [ ] Basisdokumentation vorhanden

---

## 13. Testmatrix (Qualitaetssicherung)

> Detaillierter Testplan mit Testfall-IDs, Passkriterien, Baseline-Scripts und Ergebnis-Templates: siehe `docs/testing-plan.md` (v2.7)

### Ziel
Sicherstellen, dass der Initiator stabil, interoperabel und performant ueber relevante Zielplattformen hinweg funktioniert.

### Dimensionen der Testabdeckung
- Betriebssystem: macOS 15, 14, 13, 12
- Hardware: Apple Silicon (M1, M2, M3, M4) und Intel (x86_64)
- Targets: Synology, QNAP, TrueNAS, Linux LIO, Windows iSCSI Target
- Auth: Keine, CHAP unidirektional, CHAP bidirektional
- Netzwerk: 1 GbE, 2.5 GbE, 10 GbE, Latenz/Packet Loss Simulation
- Features: Discovery, Login, READ/WRITE, Reconnect, Automount

### Basis-Testmatrix (MVP)

| Bereich | Variationen | Erwartung | Prioritaet |
|---------|-------------|-----------|-----------|
| Discovery | SendTargets gegen 3 Targets | Targets werden korrekt gefunden | Hoch |
| Login | Ohne Auth und mit CHAP | Session wird stabil aufgebaut | Hoch |
| I/O | READ/WRITE mit 4K/64K/1M | Konsistente Daten, keine Timeouts | Hoch |
| Reconnect | Link Drop / Interface Switch | Automatisches Recovery | Mittel |
| Sleep/Wake | macOS Sleep/Wake | Session-Recovery, keine Kernel-Haenger | Mittel |
| Filesystem | APFS, HFS+ | Mount/Unmount stabil | Mittel |
| Performance | Sequentiell vs. Random | Baseline-Performance dokumentiert | Niedrig |

### Interoperabilitaets-Suite (Empfohlen)

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
- Abbruch waehrend Data-Out
- Simulierter Session-Timeout

### Tooling und Automatisierung
- Unit-Tests: PDU-Parser, State-Machine, CHAP
- Integration-Tests: Scripted I/O gegen Test-Targets
- Performance: FIO-Profile (sequentiell/random)
- Logging: strukturierte Logs, anonymisierte Dumps

### Performance-Ziele (MVP)

| Metrik | 1 GbE | 2.5 GbE | 10 GbE |
|--------|-------|---------|--------|
| Seq. Read (1M, iodepth=8) | >= 110 MB/s | >= 280 MB/s | >= 800 MB/s |
| Seq. Write (1M, iodepth=8) | >= 100 MB/s | >= 250 MB/s | >= 700 MB/s |
| Random Read (4K, iodepth=32) | >= 5.000 IOPS | >= 10.000 IOPS | >= 30.000 IOPS |
| Random Write (4K, iodepth=32) | >= 3.000 IOPS | >= 7.000 IOPS | >= 20.000 IOPS |
| Latenz (4K random read, p95) | <= 100 ms | <= 50 ms | <= 30 ms |

**Messmethode:** FIO mit `--direct=1 --time_based --runtime=300`, Medianwerte aus 3 Laeufen. Durchsatz-Ziele orientieren sich an >= 60% der gemessenen TCP-Bandbreite (`iperf3`).

---

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
- [DiskArbitration](https://developer.apple.com/documentation/diskarbitration)

### Open Source Referenzen

- [open-iscsi (Linux)](https://github.com/open-iscsi/open-iscsi)
- [libiscsi](https://github.com/sahlberg/libiscsi)
- [iSCSI-OSX (veraltet)](https://github.com/iscsi-osx/iSCSIInitiator)

### WWDC Sessions

- WWDC 2019: System Extensions and DriverKit
- WWDC 2020: Modernize PCI and SCSI drivers with DriverKit
- WWDC 2022: What's new in DriverKit

---

## 16. Kontakt und Community

- **GitHub:** [TBD - Repository URL]
- **Discussions:** GitHub Discussions
- **Issues:** GitHub Issues
- **Discord/Slack:** [TBD]

---

*Dieses Dokument wird kontinuierlich aktualisiert. Letzte Aenderung: 4. Februar 2026 (v1.2 — Testmatrix, CHAP, Fehler-Recovery, Keychain, Konfiguration, Fehlerkategorien hinzugefuegt)*
