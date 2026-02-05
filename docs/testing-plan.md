# iSCSI Initiator Testplan (macOS)

**Version:** 2.7
**Datum:** 4. Februar 2026
**Geltungsbereich:** iSCSI-Initiator für macOS (Apple Silicon + Intel)

---

## 1. Ziel
Sicherstellen, dass der Initiator stabil, interoperabel und performant über relevante Zielplattformen hinweg funktioniert.

---

## 2. Abdeckung

### Dimensionen
- Betriebssystem: macOS 15, 14, 13, 12
- Hardware: Apple Silicon (M1, M2, M3, M4) und Intel (x86_64)
- Targets: Synology, QNAP, TrueNAS, Linux LIO, Windows iSCSI Target
- Auth: Keine, CHAP unidirektional, CHAP bidirektional
- Netzwerk: 1 GbE, 2.5 GbE, 10 GbE, Latenz/Packet Loss Simulation
- Features: Discovery, Login, READ/WRITE, Reconnect, Automount

---

## 3. Basis-Testmatrix (MVP)

| Bereich | Variationen | Erwartung | Priorität |
|---------|-------------|-----------|-----------|
| Discovery | SendTargets gegen 3 Targets | Targets werden korrekt gefunden | Hoch |
| Login | Ohne Auth und mit CHAP | Session wird stabil aufgebaut | Hoch |
| I/O | READ/WRITE mit 4K/64K/1M | Konsistente Daten, keine Timeouts | Hoch |
| Reconnect | Link Drop / Interface Switch | Automatisches Recovery | Mittel |
| Sleep/Wake | macOS Sleep/Wake | Session-Recovery, keine Kernel-Hänger | Mittel |
| Filesystem | APFS, HFS+ | Mount/Unmount stabil | Mittel |
| Performance | Sequentiell vs. Random | Baseline-Performance dokumentiert | Niedrig |

---

## 4. Testfälle (IDs)

| ID | Bereich | Beschreibung | Erwartung | Priorität |
|----|---------|-------------|-----------|-----------|
| TC-DISC-001 | Discovery | SendTargets gegen 3 Targets | Targets werden korrekt gefunden | Hoch |
| TC-LOGIN-001 | Login | Login ohne Auth | Session stabil aufgebaut | Hoch |
| TC-LOGIN-002 | Login | Login mit CHAP | Session stabil aufgebaut | Hoch |
| TC-IO-001 | I/O | READ/WRITE 4K | Daten konsistent, keine Timeouts | Hoch |
| TC-IO-002 | I/O | READ/WRITE 64K | Daten konsistent, keine Timeouts | Hoch |
| TC-IO-003 | I/O | READ/WRITE 1M | Daten konsistent, keine Timeouts | Hoch |
| TC-REC-001 | Reconnect | Link Drop während I/O | Automatisches Recovery | Mittel |
| TC-SLP-001 | Sleep/Wake | Sleep/Wake mit aktiver Session | Recovery ohne Kernel-Hänger | Mittel |
| TC-FS-001 | Filesystem | APFS Mount/Unmount | Stabiler Mount/Unmount | Mittel |
| TC-FS-002 | Filesystem | HFS+ Mount/Unmount | Stabiler Mount/Unmount | Mittel |
| TC-PERF-001 | Performance | Sequentiell vs. Random | Baseline dokumentiert | Niedrig |

---

## 5. Interoperabilitäts-Suite (Empfohlen)

| Target | Auth | Erwartung |
|--------|------|-----------|
| Synology DSM 7.x | CHAP | Stabile Session + I/O |
| QNAP QTS 5.x | CHAP | Stabile Session + I/O |
| TrueNAS SCALE | Keine/CHAP | Stabile Session + I/O |
| Linux LIO | Keine/CHAP | Stabile Session + I/O |
| Windows iSCSI | Keine/CHAP | Stabile Session + I/O |

---

## 6. Interoperabilitäts-Testfälle (IDs)

| ID | Target | Modell/Version | Auth | Erwartung | Priorität |
|----|--------|----------------|------|-----------|-----------|
| TC-INT-SYN-001 | Synology DSM | z. B. DS923+ / DSM 7.x | CHAP | Stabile Session + I/O | Hoch |
| TC-INT-QNAP-001 | QNAP QTS | z. B. TS-464 / QTS 5.x | CHAP | Stabile Session + I/O | Hoch |
| TC-INT-TRN-001 | TrueNAS SCALE | z. B. 24.x | Keine/CHAP | Stabile Session + I/O | Hoch |
| TC-INT-LIO-001 | Linux LIO | z. B. Ubuntu 22.04 | Keine/CHAP | Stabile Session + I/O | Mittel |
| TC-INT-WIN-001 | Windows iSCSI | z. B. Windows Server 2022 | Keine/CHAP | Stabile Session + I/O | Mittel |

Hinweis: Modell/Version im Testlauf dokumentieren und ggf. weitere IDs pro Modell ergänzen.

---


## 7. Passkriterien pro Target (Initial)

Diese Kriterien gelten pro Target-Modell und sollen nach den ersten Baselines verifiziert und ggf. angepasst werden.

| Kriterium | Schwelle (Pass) |
|----------|------------------|
| Session-Stabilität | 60 Minuten Idle + 60 Minuten Dauer-I/O ohne Disconnect |
| Datenintegrität | Checksum-Verify auf 10 GB Testdaten ohne Abweichung |
| I/O-Fehler | 0 unrecoverte I/O-Fehler; Retry-Rate <= 0.01% |
| Reconnect | Wiederherstellung nach Link Drop: Session <= 30 s, I/O <= 60 s |
| Latenz (4K random read, p95) | 1 GbE <= 100 ms; 2.5 GbE <= 50 ms; 10 GbE <= 30 ms |
| Throughput (1M seq read/write) | >= 60% der gemessenen TCP-Bandbreite (`iperf3`) oder nominalen Linkrate |

---

## 8. Baseline-Messung (Vorgehen)

Ziel: Reproduzierbare Referenzwerte je Target und Netzwerk, um Passkriterien nachvollziehbar abzuleiten.

1. Testumgebung dokumentieren: macOS-Version, Hardware, Target-Modell, Auth, Link-Rate, Switch/Router.
2. Netzwerk-Baseline messen: `iperf3` für TCP-Durchsatz (mindestens 3 Läufe, Median notieren).
3. I/O-Baseline messen: `fio` Profile für 4K random read/write und 1M sequentiell read/write (je 5 Minuten).
4. Stabilität prüfen: 60 Minuten Idle + 60 Minuten Dauer-I/O; keine Disconnects.
5. Integrität prüfen: Checksum-Verify auf 10 GB Testdaten (z. B. SHA-256).
6. Recovery prüfen: Link Drop erzwingen, Session- und I/O-Recovery-Zeit messen.
7. Ergebnisse dokumentieren: Medianwerte + p95-Latenz + Abweichungen in der Ergebnis-Template-Tabelle.

### Beispiel-Kommandos (fio)

```bash
# Parameter
TESTVOL="/Volumes/TESTVOL"
RUNTIME=300
SIZE_RAND="10G"
SIZE_SEQ="20G"
FIO_FILE="$TESTVOL/fio-test.bin"

# 4K random read
fio --name=randread_4k --filename="$FIO_FILE" --rw=randread     --bs=4k --iodepth=32 --numjobs=4 --size="$SIZE_RAND"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

# 4K random write
fio --name=randwrite_4k --filename="$FIO_FILE" --rw=randwrite     --bs=4k --iodepth=32 --numjobs=4 --size="$SIZE_RAND"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

# 1M sequential read
fio --name=seqread_1m --filename="$FIO_FILE" --rw=read     --bs=1m --iodepth=8 --numjobs=1 --size="$SIZE_SEQ"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

# 1M sequential write
fio --name=seqwrite_1m --filename="$FIO_FILE" --rw=write     --bs=1m --iodepth=8 --numjobs=1 --size="$SIZE_SEQ"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting
```

### Beispiel-Kommandos (iperf3)

```bash
# Server auf dem Target/LAN Host
iperf3 -s

# Client auf macOS (3 Läufe, Median dokumentieren)
iperf3 -c <TARGET_IP> -t 30 -P 4
```

### Baseline-Script (Beispiel)

**Voraussetzungen:**
- `fio` (z. B. via Homebrew: `brew install fio`)
- `iperf3` (z. B. via Homebrew: `brew install iperf3`)

**Usage:**

```bash
# Dry run
TARGET_IP=192.168.1.10 DRY_RUN=1 ./baseline.sh

# Real run
TARGET_IP=192.168.1.10 DRY_RUN=0 ./baseline.sh

# Logs are written to ./test-logs/baseline-<timestamp>.log
```

```bash
#!/usr/bin/env bash
set -euo pipefail


LAST_STEP="start"
trap 'log "FAILED at step: $LAST_STEP"' ERR
START_TS=$(date +%s)

# Parameter
TESTVOL="/Volumes/TESTVOL"
RUNTIME=300
SIZE_RAND="10G"
SIZE_SEQ="20G"
FIO_FILE="$TESTVOL/fio-test.bin"
TARGET_IP="<TARGET_IP>"
DRY_RUN=0
LOG_DIR="./test-logs"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/baseline-$RUN_ID.log"

# Preflight
if [ ! -d "$TESTVOL" ]; then
  echo "Mountpoint not found: $TESTVOL" >&2
  exit 1
fi


validate_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid TARGET_IP format: $ip" >&2
    return 1
  fi
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    if [ "$o" -gt 255 ]; then
      echo "Invalid TARGET_IP octet: $o" >&2
      return 1
    fi
  done
  return 0
}

validate_target() {
  local host="$1"
  if [[ "$host" =~ ^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+$ ]]; then
    return 0
  fi
  echo "Invalid TARGET host: $host" >&2
  return 1
}
validate_ip "$TARGET_IP" || validate_target "$TARGET_IP"


run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] $*"
  else
    "$@"
  fi
}

log() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] $*"
  else
    echo "$*" | tee -a "$LOG_FILE"
  fi
}

mkdir -p "$LOG_DIR"
log "Baseline run: $RUN_ID"
log "Target: $TARGET_IP"
log "Volume: $TESTVOL"
log "Runtime: $RUNTIME"
log "Sizes: rand=$SIZE_RAND seq=$SIZE_SEQ"

# Network baseline
LAST_STEP="iperf3"
log "iperf3"
run iperf3 -c "$TARGET_IP" -t 30 -P 4

# 4K random read/write
LAST_STEP="fio randread 4k"
log "fio randread 4k"
run fio --name=randread_4k --filename="$FIO_FILE" --rw=randread     --bs=4k --iodepth=32 --numjobs=4 --size="$SIZE_RAND"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

LAST_STEP="fio randwrite 4k"
log "fio randwrite 4k"
run fio --name=randwrite_4k --filename="$FIO_FILE" --rw=randwrite     --bs=4k --iodepth=32 --numjobs=4 --size="$SIZE_RAND"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

# 1M sequential read/write
LAST_STEP="fio seqread 1m"
log "fio seqread 1m"
run fio --name=seqread_1m --filename="$FIO_FILE" --rw=read     --bs=1m --iodepth=8 --numjobs=1 --size="$SIZE_SEQ"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

LAST_STEP="fio seqwrite 1m"
log "fio seqwrite 1m"
run fio --name=seqwrite_1m --filename="$FIO_FILE" --rw=write     --bs=1m --iodepth=8 --numjobs=1 --size="$SIZE_SEQ"     --time_based --runtime="$RUNTIME" --direct=1 --group_reporting

# Cleanup
LAST_STEP="cleanup"
log "cleanup"
run rm -f "$FIO_FILE"

END_TS=$(date +%s)
ELAPSED=$((END_TS-START_TS))
log "Elapsed: ${ELAPSED}s"
log "Log file: $LOG_FILE"
```


### Cleanup

```bash
# Remove test file after benchmarks
rm -f "$FIO_FILE"
```

---

## 9. Negative Tests
- Falsche CHAP Credentials
- Target nicht erreichbar / Port 3260 blockiert
- Abbruch während Data-Out
- Simulierter Session-Timeout

---

## 10. Tooling und Automatisierung
- Unit-Tests: PDU-Parser, State-Machine, CHAP
- Integration-Tests: Scripted I/O gegen Test-Targets
- Performance: FIO-Profile (sequentiell/random)
- Logging: strukturierte Logs, anonymisierte Dumps

---

## 11. Test-Infrastruktur und Mocks (Gap I1)

### MockISCSITarget

Ein lokaler, minimaler iSCSI-Target-Simulator fuer Unit- und Integration-Tests ohne externe Hardware.

```swift
/// Minimaler iSCSI Target Simulator fuer Tests
/// Lauscht auf einem lokalen TCP-Port und verarbeitet grundlegende iSCSI PDUs
actor MockISCSITarget {
    private let listener: NWListener
    private let port: UInt16
    private var connections: [NWConnection] = []
    private var targetIQN: String
    private var authMode: MockAuthMode
    private var lunSize: UInt64  // Virtuelle LUN-Groesse in Bytes

    enum MockAuthMode: Sendable {
        case none
        case chapUnidirectional(secret: String)
        case chapBidirectional(initiatorSecret: String, targetSecret: String)
    }

    init(port: UInt16 = 13260,
         targetIQN: String = "iqn.2026-01.com.test:mock-target",
         authMode: MockAuthMode = .none,
         lunSize: UInt64 = 1_073_741_824) { // 1 GB
        self.port = port
        self.targetIQN = targetIQN
        self.authMode = authMode
        self.lunSize = lunSize
        self.listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    }

    func start() async throws { /* Listener starten */ }
    func stop() async { /* Listener + Connections beenden */ }

    /// Verarbeitete PDU-Typen:
    /// - Login Request/Response (inkl. CHAP)
    /// - Text Request/Response (SendTargets Discovery)
    /// - SCSI Command (READ, WRITE, INQUIRY, READ CAPACITY)
    /// - NOP-Out/NOP-In
    /// - Logout Request/Response
}
```

### Protocol Abstractions fuer Dependency Injection

```swift
/// Abstrahiert die Netzwerkverbindung fuer Tests
protocol ISCSITransport: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

/// Reale Implementierung: NWConnection
struct NetworkTransport: ISCSITransport { ... }

/// Mock fuer Unit-Tests: Direkte Data-Uebergabe
actor MockTransport: ISCSITransport {
    var sentData: [Data] = []
    var responseQueue: [Data] = []

    func enqueueResponse(_ pdu: Data) {
        responseQueue.append(pdu)
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> Data {
        guard !responseQueue.isEmpty else {
            throw ISCSIError.connectionTimeout
        }
        return responseQueue.removeFirst()
    }

    func close() async {
        sentData.removeAll()
        responseQueue.removeAll()
    }
}
```

### Test Fixtures

```swift
/// Vorgefertigte Test-Daten
enum TestFixtures {
    /// Gueltige Login Response PDU
    static let loginResponseSuccess: Data = { ... }()

    /// Login Response mit CHAP Challenge
    static func loginResponseCHAP(algorithm: UInt8 = 5,
                                   identifier: UInt8 = 1,
                                   challenge: Data) -> Data { ... }

    /// SendTargets Discovery Response
    static func discoveryResponse(targets: [(iqn: String, portal: String)]) -> Data { ... }

    /// SCSI Response (GOOD)
    static func scsiResponse(initiatorTaskTag: UInt32,
                              status: UInt8 = 0x00) -> Data { ... }

    /// R2T PDU
    static func r2tPDU(initiatorTaskTag: UInt32,
                        targetTransferTag: UInt32,
                        r2tSN: UInt32,
                        desiredLength: UInt32,
                        bufferOffset: UInt32) -> Data { ... }
}
```

### Testumgebung-Setup

| Komponente | Tool | Beschreibung |
|------------|------|-------------|
| MockISCSITarget | Integriert | Lokaler Target-Simulator (Port 13260) |
| PDU-Fixtures | TestFixtures | Vorgefertigte PDU-Daten |
| MockTransport | Integriert | In-Memory Netzwerk-Mock |
| Realer Target | Docker + LIO | `docker run targetcli` fuer Integration-Tests |
| Netzwerk-Simulation | tc/netem | Latenz/Paketverlust fuer Robustness-Tests |

---

## 12. Ergebnisdokumentation
- Pro Testlauf: macOS-Version, Hardware, Target, Auth, Netz, Ergebnis
- Regressions: Verweis auf Issue-ID und Commit-Hash
- Performance: Baseline-Vergleich je Target und macOS-Version

### Ergebnis-Template

| Testlauf-ID | Datum | Build/Commit | macOS | Hardware | Target | Auth | Netz | Testfall-ID | Ergebnis | Notizen | Issue |
|-------------|-------|--------------|-------|----------|--------|------|------|-------------|----------|---------|-------|
| RUN-YYYYMMDD-001 | 2026-02-04 | abcdef1 | 15.x | M2 | TrueNAS | CHAP | 10 GbE | TC-IO-001 | Pass | - | - |
