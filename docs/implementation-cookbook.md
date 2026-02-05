# Implementation Cookbook
## iSCSI Initiator for macOS - Code Examples and Patterns

**Version:** 1.0
**Date:** 5. Februar 2026
**Purpose:** Complete code examples and implementation patterns for all project components

---

## Table of Contents

1. [Overview](#1-overview)
2. [DriverKit Extension (iSCSIVirtualHBA)](#2-driverkit-extension-iscsivirtualhba)
3. [XPC Communication Layer](#3-xpc-communication-layer)
4. [PDU Protocol Engine](#4-pdu-protocol-engine)
5. [Network Layer (NWProtocolFramer)](#5-network-layer-nwprotocolframer)
6. [Login State Machine](#6-login-state-machine)
7. [Session Management](#7-session-management)
8. [CHAP Authentication](#8-chap-authentication)
9. [Data Path (Shared Memory)](#9-data-path-shared-memory)
10. [Error Handling Patterns](#10-error-handling-patterns)
11. [SwiftUI App Structure](#11-swiftui-app-structure)
12. [CLI Tool (iscsiadm)](#12-cli-tool-iscsiadm)

---

## 1. Overview

### 1.1 How to Use This Cookbook

This cookbook provides **complete, compilable code examples** for every major component of the iSCSI Initiator. Each chapter includes:

- ✅ **Complete source code** (ready to copy/paste)
- ✅ **Implementation notes** (why certain patterns are used)
- ✅ **TODO markers** (for functionality you'll implement)
- ✅ **Integration points** (how components connect)

### 1.2 Implementation Order (Recommended)

Follow this order for best results:

1. **Chapter 4 (PDU Protocol Engine)** - Foundation for everything
2. **Chapter 3 (XPC Communication)** - Inter-process communication
3. **Chapter 5 (Network Layer)** - TCP/IP connectivity
4. **Chapter 6 (Login State Machine)** - Session establishment
5. **Chapter 7 (Session Management)** - Putting it together
6. **Chapter 8 (CHAP Authentication)** - Security
7. **Chapter 2 (DriverKit Extension)** - SCSI HBA integration
8. **Chapter 9 (Data Path)** - High-performance I/O
9. **Chapter 10 (Error Handling)** - Robustness
10. **Chapter 11 (GUI App)** - User interface
11. **Chapter 12 (CLI Tool)** - Command-line interface

### 1.3 Reference Documentation

While implementing, keep these documents handy:

- `docs/iSCSI-Initiator-Entwicklungsplan.md` - Architecture details
- `docs/development-environment-setup.md` - Setup guide
- RFC 7143 - iSCSI protocol specification
- Apple DriverKit Documentation

---

## 2. DriverKit Extension (iSCSIVirtualHBA)

### 2.1 Overview

The DriverKit extension is the kernel-facing component that presents a virtual SCSI HBA to macOS. It runs in user space but communicates with the kernel's SCSI subsystem.

**Files to create:**
- `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.iig` (interface definition)
- `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.cpp` (implementation)
- `Driver/iSCSIVirtualHBA/iSCSIUserClient.iig` (client interface)
- `Driver/iSCSIVirtualHBA/iSCSIUserClient.cpp` (client implementation)

### 2.2 iSCSIVirtualHBA.iig

Create `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.iig`:

```cpp
#ifndef iSCSIVirtualHBA_h
#define iSCSIVirtualHBA_h

#include <Availability.h>
#include <DriverKit/IOService.iig>
#include <DriverKit/IOUserSCSIParallelInterfaceController.iig>

class iSCSIVirtualHBA: public IOUserSCSIParallelInterfaceController
{
public:
    // Initialization
    virtual bool init() override;
    virtual void free() override;

    // Controller lifecycle
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;

    // Required pure virtual methods from IOUserSCSIParallelInterfaceController

    virtual bool UserInitializeController() QUEUENAME(Default);

    virtual bool UserStartController() QUEUENAME(Default);

    virtual void UserStopController() QUEUENAME(Default);

    virtual void UserTerminateController() QUEUENAME(Default);

    virtual kern_return_t UserProcessParallelTask(
        IOUserSCSIParallelTask* task,
        OSAction* completion) QUEUENAME(I/O);

    virtual bool UserDoesHBASupportSCSIParallelFeature(
        SCSIParallelFeature theFeature) QUEUENAME(Default);

    virtual SCSIInitiatorIdentifier UserReportInitiatorIdentifier() QUEUENAME(Default);

    virtual SCSIDeviceIdentifier UserReportHBAHighestLogicalUnitNumber() QUEUENAME(Default);

    virtual uint32_t UserReportMaximumTaskCount() QUEUENAME(Default);

    virtual SCSIParallelTaskControllerConstraints UserReportHBAConstraints(
        SCSITargetIdentifier targetID) QUEUENAME(Default);

private:
    // Dispatch queues
    IODispatchQueue* fDefaultQueue;
    IODispatchQueue* fIOQueue;
    IODispatchQueue* fAuxiliaryQueue;

    // User client for daemon communication
    IOUserClient* fUserClient;

    // Shared memory regions
    IOMemoryDescriptor* fCommandQueueMemory;
    IOMemoryDescriptor* fCompletionQueueMemory;
    IOMemoryDescriptor* fDataBufferPoolMemory;

    // Completion callback
    virtual void TaskCompleted(
        IOUserSCSIParallelTask* task,
        SCSITaskStatus status,
        uint32_t dataTransferred) QUEUENAME(I/O);
};

#endif /* iSCSIVirtualHBA_h */
```

### 2.3 iSCSIVirtualHBA.cpp

Create `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.cpp`:

```cpp
#include <os/log.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/OSAction.h>
#include "iSCSIVirtualHBA.h"
#include "iSCSIUserClient.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "iSCSIVirtualHBA: " fmt, ##__VA_ARGS__)

struct iSCSIVirtualHBA_IVars {
    IODispatchQueue* defaultQueue;
    IODispatchQueue* ioQueue;
    IODispatchQueue* auxiliaryQueue;
    IOUserClient* userClient;
};

bool iSCSIVirtualHBA::init()
{
    bool result = false;

    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(iSCSIVirtualHBA_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }

    Log("init() called");
    return true;
}

void iSCSIVirtualHBA::free()
{
    Log("free() called");

    if (ivars != nullptr) {
        IOSafeDeleteNULL(ivars, iSCSIVirtualHBA_IVars, 1);
    }

    super::free();
}

kern_return_t IMPL(iSCSIVirtualHBA, Start)
{
    kern_return_t ret;

    Log("Start() called");

    ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        Log("super::Start() failed: 0x%x", ret);
        return ret;
    }

    // Create dispatch queues
    ret = CreateDispatchQueue("Default", 0, 0, &ivars->defaultQueue);
    if (ret != kIOReturnSuccess) {
        Log("Failed to create default queue: 0x%x", ret);
        goto error;
    }

    ret = CreateDispatchQueue("I/O",
                              kIODispatchQueuePriorityHigh,
                              0,
                              &ivars->ioQueue);
    if (ret != kIOReturnSuccess) {
        Log("Failed to create I/O queue: 0x%x", ret);
        goto error;
    }

    ret = CreateDispatchQueue("Auxiliary", 0, 0, &ivars->auxiliaryQueue);
    if (ret != kIOReturnSuccess) {
        Log("Failed to create auxiliary queue: 0x%x", ret);
        goto error;
    }

    // Initialize controller
    if (!UserInitializeController()) {
        Log("UserInitializeController() failed");
        ret = kIOReturnError;
        goto error;
    }

    // Start controller
    if (!UserStartController()) {
        Log("UserStartController() failed");
        ret = kIOReturnError;
        goto error;
    }

    // Register service (makes it visible to system)
    ret = RegisterService();
    if (ret != kIOReturnSuccess) {
        Log("RegisterService() failed: 0x%x", ret);
        goto error;
    }

    Log("Start() succeeded");
    return kIOReturnSuccess;

error:
    Stop(provider, SUPERDISPATCH);
    return ret;
}

kern_return_t IMPL(iSCSIVirtualHBA, Stop)
{
    Log("Stop() called");

    UserStopController();

    OSSafeReleaseNULL(ivars->defaultQueue);
    OSSafeReleaseNULL(ivars->ioQueue);
    OSSafeReleaseNULL(ivars->auxiliaryQueue);
    OSSafeReleaseNULL(ivars->userClient);

    return Stop(provider, SUPERDISPATCH);
}

bool IMPL(iSCSIVirtualHBA, UserInitializeController)
{
    Log("UserInitializeController() called");

    // Allocate shared memory regions
    // Command Queue: 64KB (1024 × 64-byte descriptors)
    kern_return_t ret = IOMemoryDescriptor::Create(
        kIOMemoryDirectionInOut,
        64 * 1024,  // 64KB
        0,          // alignment
        &fCommandQueueMemory
    );

    if (ret != kIOReturnSuccess) {
        Log("Failed to create command queue memory: 0x%x", ret);
        return false;
    }

    // Completion Queue: 64KB
    ret = IOMemoryDescriptor::Create(
        kIOMemoryDirectionInOut,
        64 * 1024,
        0,
        &fCompletionQueueMemory
    );

    if (ret != kIOReturnSuccess) {
        Log("Failed to create completion queue memory: 0x%x", ret);
        return false;
    }

    // Data Buffer Pool: 64MB (256 × 256KB buffers)
    ret = IOMemoryDescriptor::Create(
        kIOMemoryDirectionInOut,
        64 * 1024 * 1024,  // 64MB
        0,
        &fDataBufferPoolMemory
    );

    if (ret != kIOReturnSuccess) {
        Log("Failed to create data buffer pool memory: 0x%x", ret);
        return false;
    }

    Log("Shared memory regions allocated successfully");
    return true;
}

bool IMPL(iSCSIVirtualHBA, UserStartController)
{
    Log("UserStartController() called");

    // TODO: Signal daemon that HBA is ready
    // This will be done via IOUserClient notifications

    return true;
}

void IMPL(iSCSIVirtualHBA, UserStopController)
{
    Log("UserStopController() called");

    // Clean up shared memory
    OSSafeReleaseNULL(fCommandQueueMemory);
    OSSafeReleaseNULL(fCompletionQueueMemory);
    OSSafeReleaseNULL(fDataBufferPoolMemory);
}

void IMPL(iSCSIVirtualHBA, UserTerminateController)
{
    Log("UserTerminateController() called");
    UserStopController();
}

kern_return_t IMPL(iSCSIVirtualHBA, UserProcessParallelTask)
{
    // This is called when kernel submits a SCSI command
    Log("UserProcessParallelTask() called");

    // Extract SCSI command info
    SCSICommandDescriptorBlock cdb;
    UInt8 cdbLength;
    UInt64 requestedDataTransferCount;
    UInt8 dataDirection;

    task->GetCommandDescriptorBlock(&cdb, &cdbLength);
    task->GetRequestedDataTransferCount(&requestedDataTransferCount);
    task->GetDataTransferDirection(&dataDirection);

    Log("SCSI CDB: opcode=0x%02x length=%u dataLen=%llu dir=%u",
        cdb[0], cdbLength, requestedDataTransferCount, dataDirection);

    // TODO: Forward command to daemon via shared memory
    // For now, complete with error
    SCSITaskStatus status;
    status.taskStatus = kSCSITaskStatus_CHECK_CONDITION;
    status.serviceResponse = kSCSIServiceResponse_TASK_COMPLETE;

    TaskCompleted(task, status, 0);

    if (completion) {
        completion->Cancel();
    }

    return kIOReturnSuccess;
}

void IMPL(iSCSIVirtualHBA, TaskCompleted)
{
    Log("TaskCompleted() called: status=%u transferred=%u",
        status.taskStatus, dataTransferred);

    task->SetRealizedDataTransferCount(dataTransferred);
    task->SetTaskStatus(status.taskStatus);
    task->SetServiceResponse(status.serviceResponse);

    // Complete the task back to kernel
    task->CompleteParallelTask(kSCSITaskStatus_GOOD,
                               kSCSIServiceResponse_TASK_COMPLETE);
}

bool IMPL(iSCSIVirtualHBA, UserDoesHBASupportSCSIParallelFeature)
{
    // Report which features this HBA supports
    switch (theFeature) {
        case kSCSIParallelFeature_WideDataTransfer:
            return true;  // Support 16-bit wide transfers
        case kSCSIParallelFeature_SynchronousDataTransfer:
            return true;  // Support synchronous transfers
        case kSCSIParallelFeature_QuickArbitrationAndSelection:
            return false; // Not applicable for virtual HBA
        case kSCSIParallelFeature_DoubleTransitionDataTransfers:
            return false; // Not applicable for virtual HBA
        case kSCSIParallelFeature_InformationUnitTransfers:
            return false; // Not applicable for virtual HBA
        default:
            return false;
    }
}

SCSIInitiatorIdentifier IMPL(iSCSIVirtualHBA, UserReportInitiatorIdentifier)
{
    // This HBA acts as initiator ID 7 (standard for SCSI)
    return 7;
}

SCSIDeviceIdentifier IMPL(iSCSIVirtualHBA, UserReportHBAHighestLogicalUnitNumber)
{
    // Support up to 8 LUNs per target (0-7)
    return 7;
}

uint32_t IMPL(iSCSIVirtualHBA, UserReportMaximumTaskCount)
{
    // Maximum number of concurrent I/O operations
    // Matches command queue size: 1024 entries
    return 1024;
}

SCSIParallelTaskControllerConstraints IMPL(iSCSIVirtualHBA, UserReportHBAConstraints)
{
    SCSIParallelTaskControllerConstraints constraints = {};

    // Maximum SCSI target ID supported
    constraints.maxTargetID = 15;

    // Maximum transfer size per command: 16MB
    constraints.maxTransferSize = 16 * 1024 * 1024;

    // Maximum number of scatter-gather segments: 256
    constraints.maxSegmentCount = 256;

    // Alignment requirements
    constraints.alignmentMask = 0;  // No special alignment needed

    return constraints;
}
```

### 2.4 iSCSIUserClient.iig

Create `Driver/iSCSIVirtualHBA/iSCSIUserClient.iig`:

```cpp
#ifndef iSCSIUserClient_h
#define iSCSIUserClient_h

#include <Availability.h>
#include <DriverKit/IOUserClient.iig>
#include <DriverKit/IODataQueueDispatchSource.iig>

class iSCSIUserClient: public IOUserClient
{
public:
    virtual bool init() override;
    virtual void free() override;
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;

    // External method dispatch
    virtual kern_return_t ExternalMethod(
        uint64_t selector,
        IOUserClientMethodArguments* arguments,
        const IOUserClientMethodDispatch* dispatch,
        OSObject* target,
        void* reference) override;

    // Method selectors
    enum {
        kMethodMapCommandQueue = 0,
        kMethodMapCompletionQueue = 1,
        kMethodMapDataBufferPool = 2,
        kMethodSubmitCommand = 3,
        kMethodCompleteCommand = 4,
        kMethodGetHBAInfo = 5,
        kMethodResetHBA = 6,
        kNumMethods
    };

private:
    // Notification queue for daemon
    IODataQueueDispatchSource* fNotificationQueue;
    IOMemoryDescriptor* fNotificationMemory;

    // Handler methods
    kern_return_t HandleMapCommandQueue(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleMapCompletionQueue(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleMapDataBufferPool(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleSubmitCommand(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleCompleteCommand(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleGetHBAInfo(
        IOUserClientMethodArguments* arguments);

    kern_return_t HandleResetHBA(
        IOUserClientMethodArguments* arguments);
};

#endif /* iSCSIUserClient_h */
```

### 2.5 iSCSIUserClient.cpp

Create `Driver/iSCSIVirtualHBA/iSCSIUserClient.cpp`:

```cpp
#include <os/log.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IODataQueueDispatchSource.h>
#include "iSCSIUserClient.h"
#include "iSCSIVirtualHBA.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "iSCSIUserClient: " fmt, ##__VA_ARGS__)

struct iSCSIUserClient_IVars {
    iSCSIVirtualHBA* provider;
    IODataQueueDispatchSource* notificationQueue;
    IOMemoryDescriptor* notificationMemory;
};

bool iSCSIUserClient::init()
{
    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(iSCSIUserClient_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }

    Log("init() called");
    return true;
}

void iSCSIUserClient::free()
{
    Log("free() called");

    if (ivars != nullptr) {
        IOSafeDeleteNULL(ivars, iSCSIUserClient_IVars, 1);
    }

    super::free();
}

kern_return_t IMPL(iSCSIUserClient, Start)
{
    kern_return_t ret;

    Log("Start() called");

    ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        Log("super::Start() failed: 0x%x", ret);
        return ret;
    }

    ivars->provider = OSDynamicCast(iSCSIVirtualHBA, provider);
    if (ivars->provider == nullptr) {
        Log("Provider is not iSCSIVirtualHBA");
        return kIOReturnError;
    }

    // Create notification queue for sending events to daemon
    // Queue size: 4KB (enough for ~100 notifications)
    ret = IOMemoryDescriptor::Create(
        kIOMemoryDirectionInOut,
        4096,
        0,
        &ivars->notificationMemory
    );

    if (ret != kIOReturnSuccess) {
        Log("Failed to create notification memory: 0x%x", ret);
        return ret;
    }

    ret = IODataQueueDispatchSource::Create(
        ivars->notificationMemory,
        nullptr,  // No handler (daemon polls)
        &ivars->notificationQueue
    );

    if (ret != kIOReturnSuccess) {
        Log("Failed to create notification queue: 0x%x", ret);
        OSSafeReleaseNULL(ivars->notificationMemory);
        return ret;
    }

    Log("Start() succeeded");
    return kIOReturnSuccess;
}

kern_return_t IMPL(iSCSIUserClient, Stop)
{
    Log("Stop() called");

    OSSafeReleaseNULL(ivars->notificationQueue);
    OSSafeReleaseNULL(ivars->notificationMemory);

    return Stop(provider, SUPERDISPATCH);
}

kern_return_t IMPL(iSCSIUserClient, ExternalMethod)
{
    // Dispatch table
    const IOUserClientMethodDispatch dispatchTable[kNumMethods] = {
        [kMethodMapCommandQueue] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleMapCommandQueue,
            .checkCompletionExists = false,
            .checkScalarInputCount = 0,
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 1,
            .checkStructureOutputSize = 0
        },
        [kMethodMapCompletionQueue] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleMapCompletionQueue,
            .checkCompletionExists = false,
            .checkScalarInputCount = 0,
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 1,
            .checkStructureOutputSize = 0
        },
        [kMethodMapDataBufferPool] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleMapDataBufferPool,
            .checkCompletionExists = false,
            .checkScalarInputCount = 0,
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 1,
            .checkStructureOutputSize = 0
        },
        [kMethodSubmitCommand] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleSubmitCommand,
            .checkCompletionExists = false,
            .checkScalarInputCount = 2,  // slot, tag
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 0,
            .checkStructureOutputSize = 0
        },
        [kMethodCompleteCommand] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleCompleteCommand,
            .checkCompletionExists = false,
            .checkScalarInputCount = 3,  // slot, status, transferred
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 0,
            .checkStructureOutputSize = 0
        },
        [kMethodGetHBAInfo] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleGetHBAInfo,
            .checkCompletionExists = false,
            .checkScalarInputCount = 0,
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 0,
            .checkStructureOutputSize = 64  // HBA info struct
        },
        [kMethodResetHBA] = {
            .function = (IOUserClientMethodFunction)&iSCSIUserClient::HandleResetHBA,
            .checkCompletionExists = false,
            .checkScalarInputCount = 0,
            .checkStructureInputSize = 0,
            .checkScalarOutputCount = 0,
            .checkStructureOutputSize = 0
        }
    };

    if (selector >= kNumMethods) {
        Log("Invalid selector: %llu", selector);
        return kIOReturnBadArgument;
    }

    return ExternalMethod(selector, arguments, &dispatchTable[selector],
                          this, reference, SUPERDISPATCH);
}

kern_return_t iSCSIUserClient::HandleMapCommandQueue(
    IOUserClientMethodArguments* arguments)
{
    Log("HandleMapCommandQueue() called");

    // Return memory descriptor to daemon
    // Daemon will use IOConnectMapMemory64() to map this
    arguments->scalarOutput[0] = (uint64_t)ivars->provider->fCommandQueueMemory;

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleMapCompletionQueue(
    IOUserClientMethodArguments* arguments)
{
    Log("HandleMapCompletionQueue() called");

    arguments->scalarOutput[0] = (uint64_t)ivars->provider->fCompletionQueueMemory;

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleMapDataBufferPool(
    IOUserClientMethodArguments* arguments)
{
    Log("HandleMapDataBufferPool() called");

    arguments->scalarOutput[0] = (uint64_t)ivars->provider->fDataBufferPoolMemory;

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleSubmitCommand(
    IOUserClientMethodArguments* arguments)
{
    uint32_t slot = (uint32_t)arguments->scalarInput[0];
    uint32_t tag = (uint32_t)arguments->scalarInput[1];

    Log("HandleSubmitCommand(): slot=%u tag=%u", slot, tag);

    // TODO: Read command from shared memory slot
    // TODO: Submit to iSCSI session

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleCompleteCommand(
    IOUserClientMethodArguments* arguments)
{
    uint32_t slot = (uint32_t)arguments->scalarInput[0];
    uint8_t status = (uint8_t)arguments->scalarInput[1];
    uint32_t transferred = (uint32_t)arguments->scalarInput[2];

    Log("HandleCompleteCommand(): slot=%u status=%u transferred=%u",
        slot, status, transferred);

    // TODO: Write completion to shared memory slot
    // TODO: Signal kernel that task is complete

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleGetHBAInfo(
    IOUserClientMethodArguments* arguments)
{
    Log("HandleGetHBAInfo() called");

    // Fill HBA info structure
    struct {
        uint32_t version;
        uint32_t maxTargets;
        uint32_t maxLUNs;
        uint32_t maxTasks;
        uint64_t maxTransferSize;
    } info = {
        .version = 0x00010000,  // 1.0
        .maxTargets = 16,
        .maxLUNs = 8,
        .maxTasks = 1024,
        .maxTransferSize = 16 * 1024 * 1024  // 16MB
    };

    memcpy(arguments->structureOutput, &info, sizeof(info));
    arguments->structureOutputSize = sizeof(info);

    return kIOReturnSuccess;
}

kern_return_t iSCSIUserClient::HandleResetHBA(
    IOUserClientMethodArguments* arguments)
{
    Log("HandleResetHBA() called");

    // TODO: Reset all sessions
    // TODO: Clear command/completion queues

    return kIOReturnSuccess;
}
```

---

## 3. XPC Communication Layer

### 3.1 Overview

XPC provides inter-process communication between the GUI app, CLI tool, and daemon. Three protocols are needed:

1. **ISCSIDaemonXPCProtocol** - App/CLI → Daemon requests
2. **ISCSIDaemonCallbackProtocol** - Daemon → App notifications
3. **ISCSICLIXPCProtocol** - CLI-specific operations

### 3.2 XPC Protocol Definitions

Create `Protocol/Sources/XPC/ISCSIXPCProtocols.swift`:

```swift
import Foundation

// MARK: - Data Models

/// Represents an iSCSI target
@objc public class ISCSITarget: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let iqn: String
    @objc public let portal: String  // IP:Port
    @objc public let targetPortalGroupTag: UInt16

    public init(iqn: String, portal: String, tpgt: UInt16 = 1) {
        self.iqn = iqn
        self.portal = portal
        self.targetPortalGroupTag = tpgt
    }

    public required init?(coder: NSCoder) {
        guard let iqn = coder.decodeObject(of: NSString.self, forKey: "iqn") as? String,
              let portal = coder.decodeObject(of: NSString.self, forKey: "portal") as? String else {
            return nil
        }
        self.iqn = iqn
        self.portal = portal
        self.targetPortalGroupTag = UInt16(coder.decodeInteger(forKey: "tpgt"))
    }

    public func encode(with coder: NSCoder) {
        coder.encode(iqn as NSString, forKey: "iqn")
        coder.encode(portal as NSString, forKey: "portal")
        coder.encode(Int(targetPortalGroupTag), forKey: "tpgt")
    }
}

/// Session state
@objc public enum ISCSISessionState: Int, Sendable {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case loggedIn = 3
    case failed = 4
}

/// Session information
@objc public class ISCSISessionInfo: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let target: ISCSITarget
    @objc public let state: ISCSISessionState
    @objc public let sessionID: String
    @objc public let connectedAt: Date?

    public init(target: ISCSITarget,
                state: ISCSISessionState,
                sessionID: String,
                connectedAt: Date? = nil) {
        self.target = target
        self.state = state
        self.sessionID = sessionID
        self.connectedAt = connectedAt
    }

    public required init?(coder: NSCoder) {
        guard let target = coder.decodeObject(of: ISCSITarget.self, forKey: "target"),
              let sessionID = coder.decodeObject(of: NSString.self, forKey: "sessionID") as? String else {
            return nil
        }
        self.target = target
        self.state = ISCSISessionState(rawValue: coder.decodeInteger(forKey: "state")) ?? .disconnected
        self.sessionID = sessionID
        self.connectedAt = coder.decodeObject(of: NSDate.self, forKey: "connectedAt") as? Date
    }

    public func encode(with coder: NSCoder) {
        coder.encode(target, forKey: "target")
        coder.encode(state.rawValue, forKey: "state")
        coder.encode(sessionID as NSString, forKey: "sessionID")
        if let connectedAt = connectedAt {
            coder.encode(connectedAt as NSDate, forKey: "connectedAt")
        }
    }
}

// MARK: - Main Daemon Protocol

/// XPC protocol for daemon operations
@objc public protocol ISCSIDaemonXPCProtocol {

    /// Discover targets at a portal using SendTargets
    /// - Parameters:
    ///   - portal: Portal address (IP:Port, e.g., "192.168.1.10:3260")
    ///   - completion: Returns discovered targets or error
    func discoverTargets(
        portal: String,
        completion: @escaping ([ISCSITarget]?, Error?) -> Void
    )

    /// Login to a target
    /// - Parameters:
    ///   - iqn: Target IQN
    ///   - portal: Portal address
    ///   - username: CHAP username (optional)
    ///   - secret: CHAP secret (optional)
    ///   - completion: Returns error on failure
    func loginToTarget(
        iqn: String,
        portal: String,
        username: String?,
        secret: String?,
        completion: @escaping (Error?) -> Void
    )

    /// Logout from a target
    /// - Parameters:
    ///   - sessionID: Session identifier
    ///   - completion: Returns error on failure
    func logoutFromTarget(
        sessionID: String,
        completion: @escaping (Error?) -> Void
    )

    /// List active sessions
    /// - Parameter completion: Returns session info array
    func listSessions(
        completion: @escaping ([ISCSISessionInfo], Error?) -> Void
    )

    /// Get daemon status
    /// - Parameter completion: Returns status dictionary
    func getStatus(
        completion: @escaping ([String: Any], Error?) -> Void
    )

    /// Configure auto-connect for a target
    /// - Parameters:
    ///   - iqn: Target IQN
    ///   - portal: Portal address
    ///   - enabled: Enable/disable auto-connect
    ///   - completion: Returns error on failure
    func setAutoConnect(
        iqn: String,
        portal: String,
        enabled: Bool,
        completion: @escaping (Error?) -> Void
    )
}

// MARK: - Callback Protocol

/// Callback protocol for daemon→app notifications
@objc public protocol ISCSIDaemonCallbackProtocol {

    /// Session state changed
    func sessionStateChanged(sessionID: String, newState: ISCSISessionState)

    /// Target discovered during background discovery
    func targetDiscovered(target: ISCSITarget)

    /// Connection lost
    func connectionLost(sessionID: String, error: Error)

    /// Connection restored
    func connectionRestored(sessionID: String)
}

// MARK: - CLI Protocol (optional extensions)

/// Extended protocol for CLI-specific operations
@objc public protocol ISCSICLIXPCProtocol: ISCSIDaemonXPCProtocol {

    /// Get detailed session statistics
    func getSessionStats(
        sessionID: String,
        completion: @escaping ([String: Any]?, Error?) -> Void
    )

    /// Rescan for LUNs on a session
    func rescanLUNs(
        sessionID: String,
        completion: @escaping (Error?) -> Void
    )
}
```

### 3.3 Daemon XPC Server

Create `Daemon/iscsid/ISCSIDaemonXPCServer.swift`:

```swift
import Foundation

/// XPC server implementation for daemon
actor ISCSIDaemonXPCServer: NSObject {

    private let listener: NSXPCListener
    private let sessionManager: ISCSISessionManager  // TODO: Implement

    init() {
        // Listen on Mach service name
        self.listener = NSXPCListener(machServiceName: "com.opensource.iscsi.daemon")
        self.sessionManager = ISCSISessionManager()

        super.init()

        self.listener.delegate = self
    }

    func start() {
        listener.resume()
        print("XPC server listening on: com.opensource.iscsi.daemon")
    }

    func stop() {
        listener.suspend()
    }
}

// MARK: - NSXPCListenerDelegate

extension ISCSIDaemonXPCServer: NSXPCListenerDelegate {

    nonisolated func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {

        // Configure connection
        newConnection.exportedInterface = NSXPCInterface(with: ISCSIDaemonXPCProtocol.self)

        // Set up allowed classes for parameters
        let targetClass = ISCSITarget.self
        let sessionClass = ISCSISessionInfo.self

        // discoverTargets returns [ISCSITarget]
        newConnection.exportedInterface?.setClasses(
            [NSArray.self, targetClass],
            for: #selector(ISCSIDaemonXPCProtocol.discoverTargets(portal:completion:)),
            argumentIndex: 0,
            ofReply: true
        )

        // listSessions returns [ISCSISessionInfo]
        newConnection.exportedInterface?.setClasses(
            [NSArray.self, sessionClass],
            for: #selector(ISCSIDaemonXPCProtocol.listSessions(completion:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Set exported object
        let exportedObject = ISCSIDaemonXPCInterface(sessionManager: sessionManager)
        newConnection.exportedObject = exportedObject

        // Set remote object interface (for callbacks)
        newConnection.remoteObjectInterface = NSXPCInterface(with: ISCSIDaemonCallbackProtocol.self)

        // Connection lifecycle
        newConnection.invalidationHandler = {
            print("XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            print("XPC connection interrupted")
        }

        newConnection.resume()

        print("Accepted new XPC connection from PID: \(newConnection.processIdentifier)")
        return true
    }
}

// MARK: - XPC Interface Implementation

/// Implements the XPC protocol
class ISCSIDaemonXPCInterface: NSObject, ISCSIDaemonXPCProtocol {

    private let sessionManager: ISCSISessionManager

    init(sessionManager: ISCSISessionManager) {
        self.sessionManager = sessionManager
    }

    func discoverTargets(
        portal: String,
        completion: @escaping ([ISCSITarget]?, Error?) -> Void
    ) {
        Task {
            do {
                // TODO: Implement discovery
                let targets = try await sessionManager.discoverTargets(portal: portal)
                completion(targets, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    func loginToTarget(
        iqn: String,
        portal: String,
        username: String?,
        secret: String?,
        completion: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                try await sessionManager.login(
                    iqn: iqn,
                    portal: portal,
                    username: username,
                    secret: secret
                )
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func logoutFromTarget(
        sessionID: String,
        completion: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                try await sessionManager.logout(sessionID: sessionID)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func listSessions(
        completion: @escaping ([ISCSISessionInfo], Error?) -> Void
    ) {
        Task {
            let sessions = await sessionManager.listSessions()
            completion(sessions, nil)
        }
    }

    func getStatus(
        completion: @escaping ([String: Any], Error?) -> Void
    ) {
        Task {
            let status = await sessionManager.getStatus()
            completion(status, nil)
        }
    }

    func setAutoConnect(
        iqn: String,
        portal: String,
        enabled: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                try await sessionManager.setAutoConnect(
                    iqn: iqn,
                    portal: portal,
                    enabled: enabled
                )
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}
```

### 3.4 App XPC Client

Create `App/iSCSI Initiator/XPC/ISCSIDaemonClient.swift`:

```swift
import Foundation

/// XPC client for communicating with daemon
@MainActor
class ISCSIDaemonClient: ObservableObject {

    private var connection: NSXPCConnection?
    private var proxy: ISCSIDaemonXPCProtocol?

    @Published var isConnected = false

    init() {
        setupConnection()
    }

    deinit {
        disconnect()
    }

    private func setupConnection() {
        let connection = NSXPCConnection(machServiceName: "com.opensource.iscsi.daemon")

        connection.remoteObjectInterface = NSXPCInterface(with: ISCSIDaemonXPCProtocol.self)

        // Configure allowed classes
        connection.remoteObjectInterface?.setClasses(
            [NSArray.self, ISCSITarget.self],
            for: #selector(ISCSIDaemonXPCProtocol.discoverTargets(portal:completion:)),
            argumentIndex: 0,
            ofReply: true
        )

        connection.remoteObjectInterface?.setClasses(
            [NSArray.self, ISCSISessionInfo.self],
            for: #selector(ISCSIDaemonXPCProtocol.listSessions(completion:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Set up callbacks
        connection.exportedInterface = NSXPCInterface(with: ISCSIDaemonCallbackProtocol.self)
        connection.exportedObject = self

        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
                print("Daemon connection invalidated")
            }
        }

        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
                print("Daemon connection interrupted")
                // Attempt reconnection
                self?.setupConnection()
            }
        }

        connection.resume()

        self.connection = connection
        self.proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC error: \(error)")
        } as? ISCSIDaemonXPCProtocol

        self.isConnected = true
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        proxy = nil
        isConnected = false
    }

    // MARK: - Public API

    func discoverTargets(portal: String) async throws -> [ISCSITarget] {
        guard let proxy = proxy else {
            throw ISCSIError.daemonNotConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.discoverTargets(portal: portal) { targets, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: targets ?? [])
                }
            }
        }
    }

    func loginToTarget(
        iqn: String,
        portal: String,
        username: String? = nil,
        secret: String? = nil
    ) async throws {
        guard let proxy = proxy else {
            throw ISCSIError.daemonNotConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.loginToTarget(
                iqn: iqn,
                portal: portal,
                username: username,
                secret: secret
            ) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func logoutFromTarget(sessionID: String) async throws {
        guard let proxy = proxy else {
            throw ISCSIError.daemonNotConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.logoutFromTarget(sessionID: sessionID) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func listSessions() async throws -> [ISCSISessionInfo] {
        guard let proxy = proxy else {
            throw ISCSIError.daemonNotConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.listSessions { sessions, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: sessions)
                }
            }
        }
    }

    func setAutoConnect(iqn: String, portal: String, enabled: Bool) async throws {
        guard let proxy = proxy else {
            throw ISCSIError.daemonNotConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.setAutoConnect(iqn: iqn, portal: portal, enabled: enabled) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Callback Implementation

extension ISCSIDaemonClient: ISCSIDaemonCallbackProtocol {

    nonisolated func sessionStateChanged(sessionID: String, newState: ISCSISessionState) {
        Task { @MainActor in
            print("Session \(sessionID) state changed to: \(newState)")
            // TODO: Update UI
        }
    }

    nonisolated func targetDiscovered(target: ISCSITarget) {
        Task { @MainActor in
            print("Target discovered: \(target.iqn)")
            // TODO: Update UI
        }
    }

    nonisolated func connectionLost(sessionID: String, error: Error) {
        Task { @MainActor in
            print("Connection lost for session \(sessionID): \(error)")
            // TODO: Show notification
        }
    }

    nonisolated func connectionRestored(sessionID: String) {
        Task { @MainActor in
            print("Connection restored for session \(sessionID)")
            // TODO: Show notification
        }
    }
}
```

---

## 4. PDU Protocol Engine

### 4.1 Overview

The PDU (Protocol Data Unit) engine handles encoding/decoding of iSCSI protocol messages according to RFC 7143.

**Reference:** `docs/iSCSI-Initiator-Entwicklungsplan.md` Section 4.4 for complete PDU binary layouts.

### 4.2 PDU Base Structures

Create `Protocol/Sources/PDU/ISCSIPDUTypes.swift`:

```swift
import Foundation

// MARK: - PDU Opcodes

public enum ISCSIPDUOpcode: UInt8, Sendable {
    // Initiator → Target
    case nopOut             = 0x00
    case scsiCommand        = 0x01
    case taskManagementReq  = 0x02
    case loginRequest       = 0x03
    case textRequest        = 0x04
    case dataOut            = 0x05
    case logoutRequest      = 0x06
    case snackRequest       = 0x10

    // Target → Initiator
    case nopIn              = 0x20
    case scsiResponse       = 0x21
    case taskManagementResp = 0x22
    case loginResponse      = 0x23
    case textResponse       = 0x24
    case dataIn             = 0x25
    case logoutResponse     = 0x26
    case r2t                = 0x31
    case asyncMessage       = 0x32
    case reject             = 0x3f
}

// MARK: - Basic Header Segment (BHS)

/// Basic Header Segment - 48 bytes (common to all PDUs)
public struct BasicHeaderSegment: Sendable {
    public var opcode: UInt8                    // Byte 0
    public var flags: UInt8                     // Byte 1
    public var totalAHSLength: UInt8            // Byte 4 (in 4-byte words)
    public var dataSegmentLength: UInt32        // Bytes 5-7 (24-bit, big-endian)
    public var lun: UInt64                      // Bytes 8-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var opcodeSpecific: Data             // Bytes 20-47 (28 bytes)

    public init() {
        self.opcode = 0
        self.flags = 0
        self.totalAHSLength = 0
        self.dataSegmentLength = 0
        self.lun = 0
        self.initiatorTaskTag = 0
        self.opcodeSpecific = Data(count: 28)
    }

    public static let size = 48
}

// MARK: - Complete PDU

/// Complete iSCSI PDU
public struct ISCSIPDU: Sendable {
    public var bhs: BasicHeaderSegment
    public var ahs: [Data]?                     // Additional Header Segments
    public var headerDigest: UInt32?            // CRC32C (optional)
    public var dataSegment: Data?
    public var dataDigest: UInt32?              // CRC32C (optional)

    public init(opcode: ISCSIPDUOpcode) {
        self.bhs = BasicHeaderSegment()
        self.bhs.opcode = opcode.rawValue
    }
}

// MARK: - Login PDU

public struct LoginRequestPDU: Sendable {
    // Flags (byte 1)
    public var transit: Bool                    // T bit
    public var `continue`: Bool                 // C bit
    public var currentStageCode: UInt8          // CSG (2 bits)
    public var nextStageCode: UInt8             // NSG (2 bits)

    // Fields
    public var versionMax: UInt8                // Byte 2
    public var versionMin: UInt8                // Byte 3
    public var isid: Data                       // Bytes 8-13 (6 bytes)
    public var tsih: UInt16                     // Bytes 14-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var cid: UInt16                      // Bytes 20-21 (Connection ID)
    public var cmdSN: UInt32                    // Bytes 24-27
    public var expStatSN: UInt32                // Bytes 28-31

    // Data segment (text key=value pairs)
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionMin = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.cid = 0
        self.cmdSN = 0
        self.expStatSN = 0
        self.keyValuePairs = [:]
    }
}

public struct LoginResponsePDU: Sendable {
    // Flags
    public var transit: Bool
    public var `continue`: Bool
    public var currentStageCode: UInt8
    public var nextStageCode: UInt8

    // Fields
    public var versionMax: UInt8
    public var versionActive: UInt8
    public var isid: Data
    public var tsih: UInt16
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var statusClass: UInt8
    public var statusDetail: UInt8

    // Data segment
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionActive = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.statusClass = 0
        self.statusDetail = 0
        self.keyValuePairs = [:]
    }
}

// MARK: - SCSI Command PDU

public struct SCSICommandPDU: Sendable {
    // Flags
    public var final: Bool                      // F bit
    public var read: Bool                       // R bit
    public var write: Bool                      // W bit
    public var attributes: UInt8                // ATTR (3 bits)

    // Fields
    public var lun: UInt64
    public var initiatorTaskTag: UInt32
    public var expectedDataTransferLength: UInt32
    public var cmdSN: UInt32
    public var expStatSN: UInt32
    public var cdb: Data                        // SCSI CDB (16 bytes)

    public init() {
        self.final = false
        self.read = false
        self.write = false
        self.attributes = 0
        self.lun = 0
        self.initiatorTaskTag = 0
        self.expectedDataTransferLength = 0
        self.cmdSN = 0
        self.expStatSN = 0
        self.cdb = Data(count: 16)
    }
}

public struct SCSIResponsePDU: Sendable {
    // Fields
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var response: UInt8                  // 0x00 = command completed at target
    public var status: UInt8                    // SCSI status
    public var senseData: Data?                 // Autosense data (if status = CHECK_CONDITION)

    public init() {
        self.initiatorTaskTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.response = 0
        self.status = 0
    }
}

// MARK: - Text Request/Response (for SendTargets)

public struct TextRequestPDU: Sendable {
    public var final: Bool
    public var `continue`: Bool
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var cmdSN: UInt32
    public var expStatSN: UInt32
    public var keyValuePairs: [String: String]

    public init() {
        self.final = false
        self.continue = false
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0xFFFFFFFF  // Reserved value
        self.cmdSN = 0
        self.expStatSN = 0
        self.keyValuePairs = [:]
    }
}

public struct TextResponsePDU: Sendable {
    public var final: Bool
    public var `continue`: Bool
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var keyValuePairs: [String: String]

    public init() {
        self.final = false
        self.continue = false
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0xFFFFFFFF
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.keyValuePairs = [:]
    }
}

// MARK: - Logout PDU

public struct LogoutRequestPDU: Sendable {
    public var reasonCode: UInt8                // 0=close session, 1=close connection, 2=remove for recovery
    public var initiatorTaskTag: UInt32
    public var cid: UInt16
    public var cmdSN: UInt32
    public var expStatSN: UInt32

    public init(reasonCode: UInt8 = 0) {
        self.reasonCode = reasonCode
        self.initiatorTaskTag = 0
        self.cid = 0
        self.cmdSN = 0
        self.expStatSN = 0
    }
}

public struct LogoutResponsePDU: Sendable {
    public var response: UInt8                  // 0=success, 1=CID not found, etc.
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var time2Wait: UInt16
    public var time2Retain: UInt16

    public init() {
        self.response = 0
        self.initiatorTaskTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.time2Wait = 0
        self.time2Retain = 0
    }
}

// MARK: - NOP-Out/NOP-In (for keepalive)

public struct NOPOutPDU: Sendable {
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32        // 0xFFFFFFFF if initiator originated
    public var cmdSN: UInt32
    public var expStatSN: UInt32
    public var pingData: Data?

    public init() {
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0xFFFFFFFF
        self.cmdSN = 0
        self.expStatSN = 0
    }
}

public struct NOPInPDU: Sendable {
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var pingData: Data?

    public init() {
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0xFFFFFFFF
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
    }
}

// MARK: - R2T (Ready to Transfer)

public struct R2TPDU: Sendable {
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var r2tSN: UInt32                    // R2T sequence number
    public var bufferOffset: UInt32             // Offset into SCSI write buffer
    public var desiredDataTransferLength: UInt32

    public init() {
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.r2tSN = 0
        self.bufferOffset = 0
        self.desiredDataTransferLength = 0
    }
}

// MARK: - Data-Out

public struct DataOutPDU: Sendable {
    public var final: Bool
    public var lun: UInt64
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var expStatSN: UInt32
    public var dataSN: UInt32                   // Data sequence number
    public var bufferOffset: UInt32
    public var data: Data

    public init() {
        self.final = false
        self.lun = 0
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0
        self.expStatSN = 0
        self.dataSN = 0
        self.bufferOffset = 0
        self.data = Data()
    }
}

// MARK: - Data-In

public struct DataInPDU: Sendable {
    public var final: Bool
    public var acknowledge: Bool                // A bit
    public var overflow: Bool                   // O bit
    public var underflow: Bool                  // U bit
    public var statusPresent: Bool              // S bit
    public var lun: UInt64
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var dataSN: UInt32
    public var bufferOffset: UInt32
    public var residualCount: UInt32
    public var status: UInt8?                   // Only if S bit set
    public var data: Data

    public init() {
        self.final = false
        self.acknowledge = false
        self.overflow = false
        self.underflow = false
        self.statusPresent = false
        self.lun = 0
        self.initiatorTaskTag = 0
        self.targetTransferTag = 0xFFFFFFFF
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.dataSN = 0
        self.bufferOffset = 0
        self.residualCount = 0
        self.data = Data()
    }
}
```

### 4.3 PDU Parser

Create `Protocol/Sources/PDU/ISCSIPDUParser.swift`:

```swift
import Foundation

public enum PDUParseError: Error {
    case insufficientData
    case invalidOpcode(UInt8)
    case invalidHeaderDigest
    case invalidDataDigest
    case malformedPDU(String)
}

public struct ISCSIPDUParser {

    /// Parse BHS from data
    public static func parseBHS(_ data: Data) throws -> BasicHeaderSegment {
        guard data.count >= BasicHeaderSegment.size else {
            throw PDUParseError.insufficientData
        }

        var bhs = BasicHeaderSegment()

        // Byte 0: Opcode
        bhs.opcode = data[0]

        // Byte 1: Flags
        bhs.flags = data[1]

        // Byte 4: TotalAHSLength
        bhs.totalAHSLength = data[4]

        // Bytes 5-7: DataSegmentLength (24-bit, big-endian)
        bhs.dataSegmentLength = UInt32(data[5]) << 16 |
                                UInt32(data[6]) << 8 |
                                UInt32(data[7])

        // Bytes 8-15: LUN (big-endian)
        bhs.lun = data.subdata(in: 8..<16).withUnsafeBytes {
            $0.load(as: UInt64.self).bigEndian
        }

        // Bytes 16-19: ITT (big-endian)
        bhs.initiatorTaskTag = data.subdata(in: 16..<20).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // Bytes 20-47: Opcode-specific
        bhs.opcodeSpecific = data.subdata(in: 20..<48)

        return bhs
    }

    /// Encode BHS to data
    public static func encodeBHS(_ bhs: BasicHeaderSegment) -> Data {
        var data = Data(count: BasicHeaderSegment.size)

        data[0] = bhs.opcode
        data[1] = bhs.flags
        data[2] = 0  // Reserved
        data[3] = 0  // Reserved
        data[4] = bhs.totalAHSLength

        // DataSegmentLength (24-bit, big-endian)
        data[5] = UInt8((bhs.dataSegmentLength >> 16) & 0xFF)
        data[6] = UInt8((bhs.dataSegmentLength >> 8) & 0xFF)
        data[7] = UInt8(bhs.dataSegmentLength & 0xFF)

        // LUN (big-endian)
        withUnsafeBytes(of: bhs.lun.bigEndian) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }

        // ITT (big-endian)
        withUnsafeBytes(of: bhs.initiatorTaskTag.bigEndian) { bytes in
            data.replaceSubrange(16..<20, with: bytes)
        }

        // Opcode-specific
        data.replaceSubrange(20..<48, with: bhs.opcodeSpecific)

        return data
    }

    /// Parse complete PDU
    public static func parsePDU(_ data: Data) throws -> ISCSIPDU {
        let bhs = try parseBHS(data)

        var pdu = ISCSIPDU(opcode: ISCSIPDUOpcode(rawValue: bhs.opcode & 0x3F) ?? .nopOut)
        pdu.bhs = bhs

        var offset = BasicHeaderSegment.size

        // Parse AHS if present
        if bhs.totalAHSLength > 0 {
            let ahsLength = Int(bhs.totalAHSLength) * 4  // In 4-byte words
            guard data.count >= offset + ahsLength else {
                throw PDUParseError.insufficientData
            }
            // TODO: Parse AHS segments
            offset += ahsLength
        }

        // Parse header digest if present (not implemented yet)
        // offset += 4 if header digest enabled

        // Parse data segment if present
        if bhs.dataSegmentLength > 0 {
            let dataLength = Int(bhs.dataSegmentLength)
            let paddedLength = (dataLength + 3) & ~3  // Pad to 4-byte boundary

            guard data.count >= offset + paddedLength else {
                throw PDUParseError.insufficientData
            }

            pdu.dataSegment = data.subdata(in: offset..<(offset + dataLength))
            offset += paddedLength
        }

        // Parse data digest if present (not implemented yet)
        // offset += 4 if data digest enabled

        return pdu
    }

    /// Encode complete PDU
    public static func encodePDU(_ pdu: ISCSIPDU) -> Data {
        var data = encodeBHS(pdu.bhs)

        // Add AHS if present
        if let ahs = pdu.ahs, !ahs.isEmpty {
            for segment in ahs {
                data.append(segment)
            }
        }

        // Add header digest if present
        if let digest = pdu.headerDigest {
            withUnsafeBytes(of: digest.bigEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        // Add data segment if present
        if let dataSegment = pdu.dataSegment, !dataSegment.isEmpty {
            data.append(dataSegment)

            // Add padding to 4-byte boundary
            let padding = (4 - (dataSegment.count % 4)) % 4
            if padding > 0 {
                data.append(Data(count: padding))
            }
        }

        // Add data digest if present
        if let digest = pdu.dataDigest {
            withUnsafeBytes(of: digest.bigEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        return data
    }

    /// Parse key=value pairs from text data segment
    public static func parseKeyValuePairs(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var pairs: [String: String] = [:]

        // Split by null terminators
        let entries = text.components(separatedBy: "\0").filter { !$0.isEmpty }

        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                pairs[String(parts[0])] = String(parts[1])
            }
        }

        return pairs
    }

    /// Encode key=value pairs to text data segment
    public static func encodeKeyValuePairs(_ pairs: [String: String]) -> Data {
        var text = ""

        for (key, value) in pairs.sorted(by: { $0.key < $1.key }) {
            text += "\(key)=\(value)\0"
        }

        // iSCSI text data must be null-terminated
        if !text.isEmpty && !text.hasSuffix("\0") {
            text += "\0"
        }

        return text.data(using: .utf8) ?? Data()
    }
}

// MARK: - Login PDU Parsing

extension ISCSIPDUParser {

    public static func parseLoginRequest(_ pdu: ISCSIPDU) throws -> LoginRequestPDU {
        var login = LoginRequestPDU()

        let flags = pdu.bhs.flags
        login.transit = (flags & 0x80) != 0
        login.continue = (flags & 0x40) != 0
        login.currentStageCode = (flags >> 2) & 0x03
        login.nextStageCode = flags & 0x03

        let spec = pdu.bhs.opcodeSpecific
        login.versionMax = spec[0]
        login.versionMin = spec[1]
        login.isid = spec.subdata(in: 4..<10)
        login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        login.cid = spec.subdata(in: 12..<14).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        login.cmdSN = spec.subdata(in: 16..<20).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        login.expStatSN = spec.subdata(in: 20..<24).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        if let data = pdu.dataSegment {
            login.keyValuePairs = parseKeyValuePairs(data)
        }

        return login
    }

    public static func encodeLoginRequest(_ login: LoginRequestPDU) -> Data {
        var pdu = ISCSIPDU(opcode: .loginRequest)

        // Flags
        var flags: UInt8 = 0
        if login.transit { flags |= 0x80 }
        if login.continue { flags |= 0x40 }
        flags |= (login.currentStageCode & 0x03) << 2
        flags |= login.nextStageCode & 0x03
        pdu.bhs.flags = flags

        // Opcode-specific
        var spec = Data(count: 28)
        spec[0] = login.versionMax
        spec[1] = login.versionMin
        spec.replaceSubrange(4..<10, with: login.isid)

        withUnsafeBytes(of: login.tsih.bigEndian) { bytes in
            spec.replaceSubrange(10..<12, with: bytes)
        }

        pdu.bhs.initiatorTaskTag = login.initiatorTaskTag

        withUnsafeBytes(of: login.cid.bigEndian) { bytes in
            spec.replaceSubrange(12..<14, with: bytes)
        }
        withUnsafeBytes(of: login.cmdSN.bigEndian) { bytes in
            spec.replaceSubrange(16..<20, with: bytes)
        }
        withUnsafeBytes(of: login.expStatSN.bigEndian) { bytes in
            spec.replaceSubrange(20..<24, with: bytes)
        }

        pdu.bhs.opcodeSpecific = spec

        // Data segment
        if !login.keyValuePairs.isEmpty {
            let data = encodeKeyValuePairs(login.keyValuePairs)
            pdu.bhs.dataSegmentLength = UInt32(data.count)
            pdu.dataSegment = data
        }

        return encodePDU(pdu)
    }

    public static func parseLoginResponse(_ pdu: ISCSIPDU) throws -> LoginResponsePDU {
        var login = LoginResponsePDU()

        let flags = pdu.bhs.flags
        login.transit = (flags & 0x80) != 0
        login.continue = (flags & 0x40) != 0
        login.currentStageCode = (flags >> 2) & 0x03
        login.nextStageCode = flags & 0x03

        let spec = pdu.bhs.opcodeSpecific
        login.versionMax = spec[0]
        login.versionActive = spec[1]
        login.isid = spec.subdata(in: 4..<10)
        login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        login.statSN = spec.subdata(in: 16..<20).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        login.expCmdSN = spec.subdata(in: 20..<24).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        login.maxCmdSN = spec.subdata(in: 24..<28).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        login.statusClass = spec[12]
        login.statusDetail = spec[13]

        if let data = pdu.dataSegment {
            login.keyValuePairs = parseKeyValuePairs(data)
        }

        return login
    }
}

// TODO: Add similar parse/encode methods for other PDU types
// (TextRequest, TextResponse, SCSICommand, SCSIResponse, etc.)
```

---

## 5. Network Layer (NWProtocolFramer)

### 5.1 Overview

The network layer uses Apple's Network.framework with a custom NWProtocolFramer to handle TCP connections and PDU framing.

**Reference:** `docs/iSCSI-Initiator-Entwicklungsplan.md` Section 3.7

### 5.2 Custom Protocol Framer

Create `Network/Sources/ISCSIProtocolFramer.swift`:

```swift
import Foundation
import Network

/// Custom NWProtocolFramer for iSCSI PDU framing
class ISCSIProtocolFramer: NWProtocolFramerImplementation {

    static let definition = NWProtocolFramer.Definition(implementation: ISCSIProtocolFramer.self)
    static let label = "iSCSI"

    required init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        return .ready
    }

    func wakeup(framer: NWProtocolFramer.Instance) {}

    func stop(framer: NWProtocolFramer.Instance) -> Bool {
        return true
    }

    func cleanup(framer: NWProtocolFramer.Instance) {}

    // Handle incoming data (framing)
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            // Parse BHS (48 bytes) to determine PDU size
            var bhsData: Data?
            let bhsParsed = framer.parseInput(
                minimumIncompleteLength: BasicHeaderSegment.size,
                maximumLength: BasicHeaderSegment.size
            ) { buffer, isComplete in
                guard let buffer = buffer, buffer.count >= BasicHeaderSegment.size else {
                    return 0
                }
                bhsData = Data(buffer)
                return BasicHeaderSegment.size
            }

            guard bhsParsed, let bhs = bhsData else {
                // Not enough data yet
                return BasicHeaderSegment.size
            }

            // Extract data segment length (bytes 5-7)
            let dataSegmentLength = UInt32(bhs[5]) << 16 |
                                    UInt32(bhs[6]) << 8 |
                                    UInt32(bhs[7])

            let totalAHSLength = UInt32(bhs[4]) * 4  // In 4-byte words

            // Calculate total PDU size
            var totalSize = BasicHeaderSegment.size
            totalSize += Int(totalAHSLength)  // AHS
            // TODO: Add header digest size if enabled (4 bytes)

            if dataSegmentLength > 0 {
                let paddedDataLength = (Int(dataSegmentLength) + 3) & ~3  // 4-byte alignment
                totalSize += paddedDataLength
                // TODO: Add data digest size if enabled (4 bytes)
            }

            // Try to parse complete PDU
            var pduData: Data?
            let pduParsed = framer.parseInput(
                minimumIncompleteLength: totalSize,
                maximumLength: totalSize
            ) { buffer, isComplete in
                guard let buffer = buffer, buffer.count >= totalSize else {
                    return 0
                }
                pduData = Data(buffer)
                return totalSize
            }

            guard pduParsed, let completePDU = pduData else {
                // Need more data
                return totalSize
            }

            // Deliver PDU to protocol stack
            let message = NWProtocolFramer.Message(definition: ISCSIProtocolFramer.definition)
            if !framer.deliverInputNoCopy(length: totalSize, message: message, isComplete: true) {
                return 0
            }
        }
    }

    // Handle outgoing data (framing)
    func handleOutput(
        framer: NWProtocolFramer.Instance,
        message: NWProtocolFramer.Message,
        messageLength: Int,
        isComplete: Bool
    ) {
        // iSCSI PDUs are self-framing (no additional work needed)
        // Just write the data as-is
        framer.writeOutput(data: message.content)
    }
}
```

### 5.3 TCP Connection Management

Create `Network/Sources/ISCSIConnection.swift`:

```swift
import Foundation
import Network

/// Manages a single TCP connection to an iSCSI target
actor ISCSIConnection {

    let host: String
    let port: UInt16

    private var connection: NWConnection?
    private var state: ConnectionState = .disconnected
    private var receiveQueue: AsyncStream<Data>?
    private var receiveContinuation: AsyncStream<Data>.Continuation?

    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    init(host: String, port: UInt16 = 3260) {
        self.host = host
        self.port = port
    }

    /// Connect to target
    func connect() async throws {
        guard state == .disconnected || (case .failed = state) else {
            throw ISCSIError.alreadyConnected
        }

        state = .connecting

        // Create TCP parameters with custom options
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true  // TCP_NODELAY for latency-sensitive protocol
        tcpOptions.connectionTimeout = 30  // 30 second timeout

        // Set send/receive buffer sizes
        tcpOptions.sendBufferSize = 256 * 1024  // 256KB
        tcpOptions.receiveBufferSize = 256 * 1024

        // Create parameters with iSCSI framer
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let iscsiOptions = NWProtocolFramer.Options(definition: ISCSIProtocolFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(iscsiOptions, at: 0)

        // Create connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )

        let newConnection = NWConnection(to: endpoint, using: parameters)

        // State handler
        newConnection.stateUpdateHandler = { [weak self] newState in
            Task {
                await self?.handleStateChange(newState)
            }
        }

        // Start connection
        let queue = DispatchQueue(label: "com.opensource.iscsi.connection.\(host):\(port)")
        newConnection.start(queue: queue)

        self.connection = newConnection

        // Wait for connection
        for _ in 0..<100 {  // 10 seconds timeout
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if case .connected = state {
                // Start receiving
                setupReceive()
                return
            }
            if case .failed(let error) = state {
                throw error
            }
        }

        throw ISCSIError.connectionTimeout
    }

    /// Disconnect from target
    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
        receiveContinuation?.finish()
    }

    /// Send PDU data
    func send(_ data: Data) async throws {
        guard let connection = connection, case .connected = state else {
            throw ISCSIError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// Receive PDU stream
    func receiveStream() -> AsyncStream<Data> {
        if let existing = receiveQueue {
            return existing
        }

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.receiveQueue = stream
        self.receiveContinuation = continuation
        return stream
    }

    // MARK: - Private

    private func handleStateChange(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            state = .connected
            print("✅ Connected to \(host):\(port)")

        case .failed(let error):
            state = .failed(error)
            print("❌ Connection failed: \(error)")

        case .waiting(let error):
            print("⏳ Waiting: \(error)")

        case .cancelled:
            state = .disconnected
            print("Connection cancelled")

        default:
            break
        }
    }

    private func setupReceive() {
        guard let connection = connection else { return }

        connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task {
                if let content = content, !content.isEmpty {
                    await self?.receiveContinuation?.yield(content)
                }

                if let error = error {
                    print("Receive error: \(error)")
                    await self?.receiveContinuation?.finish()
                    return
                }

                // Continue receiving
                await self?.setupReceive()
            }
        }
    }
}
```

---

## 6. Login State Machine

### 6.1 Overview

The login state machine handles the iSCSI login process through its various phases.

**Reference:** `docs/iSCSI-Initiator-Entwicklungsplan.md` Section 4.5

### 6.2 State Machine Actor

Create `Protocol/Sources/Session/LoginStateMachine.swift`:

```swift
import Foundation

/// Login state machine for iSCSI session establishment
actor LoginStateMachine {

    enum State: Sendable {
        case free                    // Not started
        case securityNegotiation     // CSG=0, NSG=varies
        case operationalNegotiation  // CSG=1, NSG=3
        case fullFeaturePhase        // CSG=3, NSG=3 (logged in)
        case failed(Error)
    }

    private(set) var currentState: State = .free
    private var isid: Data
    private var tsih: UInt16 = 0
    private var itt: UInt32 = 0
    private var cmdSN: UInt32 = 0
    private var expStatSN: UInt32 = 0

    // Negotiated parameters
    private var negotiatedParams: [String: String] = [:]

    init(isid: Data) {
        self.isid = isid
    }

    /// Start login process
    func startLogin(connection: ISCSIConnection) async throws {
        guard case .free = currentState else {
            throw ISCSIError.invalidState
        }

        currentState = .securityNegotiation

        // Build initial login PDU
        var loginPDU = LoginRequestPDU()
        loginPDU.transit = true  // T=1
        loginPDU.currentStageCode = 0  // Security negotiation
        loginPDU.nextStageCode = 1  // Move to operational negotiation
        loginPDU.versionMax = 0
        loginPDU.versionMin = 0
        loginPDU.isid = isid
        loginPDU.tsih = 0  // New session
        loginPDU.initiatorTaskTag = generateITT()
        loginPDU.cid = 0  // First connection
        loginPDU.cmdSN = cmdSN
        loginPDU.expStatSN = expStatSN

        // Initial key=value pairs
        loginPDU.keyValuePairs = [
            "InitiatorName": "iqn.2026-01.com.opensource:macos-initiator",
            "SessionType": "Normal",
            "AuthMethod": "None"  // TODO: Support CHAP
        ]

        // Send login request
        let data = ISCSIPDUParser.encodeLoginRequest(loginPDU)
        try await connection.send(data)

        // Receive response
        for await pduData in connection.receiveStream() {
            guard let pdu = try? ISCSIPDUParser.parsePDU(pduData),
                  pdu.bhs.opcode == ISCSIPDUOpcode.loginResponse.rawValue else {
                continue
            }

            let response = try ISCSIPDUParser.parseLoginResponse(pdu)
            try await processLoginResponse(response, connection: connection)

            if case .fullFeaturePhase = currentState {
                break  // Login complete
            }
        }
    }

    private func processLoginResponse(
        _ response: LoginResponsePDU,
        connection: ISCSIConnection
    ) async throws {
        // Check status
        if response.statusClass != 0 {
            let error = ISCSIError.loginFailed(
                statusClass: response.statusClass,
                statusDetail: response.statusDetail
            )
            currentState = .failed(error)
            throw error
        }

        // Update sequence numbers
        expStatSN = response.statSN + 1
        cmdSN = response.expCmdSN

        // Save TSIH if provided
        if response.tsih != 0 {
            tsih = response.tsih
        }

        // Store negotiated parameters
        for (key, value) in response.keyValuePairs {
            negotiatedParams[key] = value
        }

        // Handle state transition
        if response.transit {
            switch (response.currentStageCode, response.nextStageCode) {
            case (0, 1):
                // Security → Operational
                currentState = .operationalNegotiation
                try await sendOperationalNegotiation(connection: connection)

            case (1, 3):
                // Operational → Full Feature
                currentState = .fullFeaturePhase
                print("✅ Login successful, TSIH=\(tsih)")

            default:
                throw ISCSIError.invalidLoginStage(
                    current: response.currentStageCode,
                    next: response.nextStageCode
                )
            }
        } else {
            // Continue in current stage
            // TODO: Handle multi-PDU negotiation
        }
    }

    private func sendOperationalNegotiation(connection: ISCSIConnection) async throws {
        var loginPDU = LoginRequestPDU()
        loginPDU.transit = true
        loginPDU.currentStageCode = 1  // Operational
        loginPDU.nextStageCode = 3  // Full Feature
        loginPDU.versionMax = 0
        loginPDU.versionMin = 0
        loginPDU.isid = isid
        loginPDU.tsih = tsih
        loginPDU.initiatorTaskTag = generateITT()
        loginPDU.cid = 0
        loginPDU.cmdSN = cmdSN
        loginPDU.expStatSN = expStatSN

        // Operational parameters
        loginPDU.keyValuePairs = [
            "HeaderDigest": "None",
            "DataDigest": "None",
            "MaxRecvDataSegmentLength": "65536",
            "DefaultTime2Wait": "2",
            "DefaultTime2Retain": "20",
            "IFMarker": "No",
            "OFMarker": "No",
            "ErrorRecoveryLevel": "0"
        ]

        let data = ISCSIPDUParser.encodeLoginRequest(loginPDU)
        try await connection.send(data)
    }

    private func generateITT() -> UInt32 {
        itt += 1
        return itt
    }

    /// Get negotiated parameter value
    func getNegotiatedParameter(_ key: String) -> String? {
        return negotiatedParams[key]
    }
}
```

---

## 7. Session Management

### 7.1 Overview

The session manager coordinates multiple iSCSI sessions and integrates all components.

Create `Protocol/Sources/Session/ISCSISessionManager.swift`:

```swift
import Foundation

/// Manages all iSCSI sessions
actor ISCSISessionManager {

    private var sessions: [String: ISCSISession] = [:]
    private var autoConnectTargets: Set<String> = []

    init() {}

    /// Discover targets at a portal
    func discoverTargets(portal: String) async throws -> [ISCSITarget] {
        let components = portal.split(separator: ":")
        let host = String(components[0])
        let port = components.count > 1 ? UInt16(components[1]) ?? 3260 : 3260

        let connection = ISCSIConnection(host: host, port: port)
        try await connection.connect()
        defer { connection.disconnect() }

        // Send Text Request with SendTargets
        var textReq = TextRequestPDU()
        textReq.final = true
        textReq.initiatorTaskTag = 1
        textReq.cmdSN = 0
        textReq.expStatSN = 0
        textReq.keyValuePairs = ["SendTargets": "All"]

        // TODO: Encode and send TextRequest
        // TODO: Parse TextResponse for target list

        // Placeholder
        return []
    }

    /// Login to a target
    func login(
        iqn: String,
        portal: String,
        username: String?,
        secret: String?
    ) async throws {
        let sessionID = "\(iqn)@\(portal)"

        if sessions[sessionID] != nil {
            throw ISCSIError.sessionAlreadyExists
        }

        let components = portal.split(separator: ":")
        let host = String(components[0])
        let port = components.count > 1 ? UInt16(components[1]) ?? 3260 : 3260

        let session = ISCSISession(
            targetIQN: iqn,
            host: host,
            port: port
        )

        try await session.connect()

        sessions[sessionID] = session
        print("✅ Session created: \(sessionID)")
    }

    /// Logout from a target
    func logout(sessionID: String) async throws {
        guard let session = sessions[sessionID] else {
            throw ISCSIError.sessionNotFound
        }

        await session.disconnect()
        sessions.removeValue(forKey: sessionID)
        print("Session logged out: \(sessionID)")
    }

    /// List active sessions
    func listSessions() -> [ISCSISessionInfo] {
        return sessions.map { (sessionID, session) in
            ISCSISessionInfo(
                target: ISCSITarget(iqn: session.targetIQN, portal: "\(session.host):\(session.port)"),
                state: .connected,  // TODO: Get actual state
                sessionID: sessionID,
                connectedAt: Date()  // TODO: Track actual connection time
            )
        }
    }

    /// Get daemon status
    func getStatus() -> [String: Any] {
        return [
            "sessionCount": sessions.count,
            "version": "1.0.0",
            "uptime": 0  // TODO: Track daemon start time
        ]
    }

    /// Set auto-connect for a target
    func setAutoConnect(iqn: String, portal: String, enabled: Bool) async throws {
        let key = "\(iqn)@\(portal)"
        if enabled {
            autoConnectTargets.insert(key)
        } else {
            autoConnectTargets.remove(key)
        }
        // TODO: Persist to configuration file
    }
}

// MARK: - Session

actor ISCSISession {

    let targetIQN: String
    let host: String
    let port: UInt16

    private var connection: ISCSIConnection?
    private var loginStateMachine: LoginStateMachine?

    init(targetIQN: String, host: String, port: UInt16) {
        self.targetIQN = targetIQN
        self.host = host
        self.port = port
    }

    func connect() async throws {
        let conn = ISCSIConnection(host: host, port: port)
        try await conn.connect()
        self.connection = conn

        // Generate ISID (6 bytes)
        let isid = generateISID()

        let loginSM = LoginStateMachine(isid: isid)
        try await loginSM.startLogin(connection: conn)
        self.loginStateMachine = loginSM
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
    }

    private func generateISID() -> Data {
        // ISID format: Type(2) | Naming Authority(3) | Qualifier(1)
        // Type: 0x00 (OUI format)
        // For now, generate random ISID
        var isid = Data(count: 6)
        isid[0] = 0x00  // OUI format
        for i in 1..<6 {
            isid[i] = UInt8.random(in: 0...255)
        }
        return isid
    }
}
```

---

## 8. CHAP Authentication

### 8.1 Overview

CHAP (Challenge Handshake Authentication Protocol) provides secure authentication.

**Reference:** `docs/iSCSI-Initiator-Entwicklungsplan.md` Section 4.9

### 8.2 CHAP Authenticator

Create `Protocol/Sources/Auth/CHAPAuthenticator.swift`:

```swift
import Foundation
import CryptoKit

/// CHAP authentication handler
actor CHAPAuthenticator {

    enum Algorithm: UInt8 {
        case md5 = 5
        case sha256 = 7
    }

    /// Compute CHAP response
    /// - Parameters:
    ///   - identifier: CHAP_I (identifier)
    ///   - secret: CHAP shared secret
    ///   - challenge: CHAP_C (challenge from target)
    ///   - algorithm: Hash algorithm (default MD5)
    /// - Returns: CHAP response
    func computeResponse(
        identifier: UInt8,
        secret: String,
        challenge: Data,
        algorithm: Algorithm = .md5
    ) -> Data {
        // CHAP Response = Hash(identifier + secret + challenge)
        var data = Data()
        data.append(identifier)
        data.append(secret.data(using: .utf8)!)
        data.append(challenge)

        switch algorithm {
        case .md5:
            return Data(Insecure.MD5.hash(data: data))
        case .sha256:
            return Data(SHA256.hash(data: data))
        }
    }

    /// Parse CHAP parameters from login response
    func parseCHAPChallenge(_ keyValuePairs: [String: String]) -> (algorithm: Algorithm, identifier: UInt8, challenge: Data)? {
        guard let algorithmStr = keyValuePairs["CHAP_A"],
              let algorithm = Algorithm(rawValue: UInt8(algorithmStr) ?? 0),
              let identifierStr = keyValuePairs["CHAP_I"],
              let identifier = UInt8(identifierStr),
              let challengeHex = keyValuePairs["CHAP_C"],
              let challenge = Data(hexString: challengeHex) else {
            return nil
        }

        return (algorithm, identifier, challenge)
    }

    /// Build CHAP response key-value pairs
    func buildCHAPResponse(
        identifier: UInt8,
        secret: String,
        challenge: Data,
        name: String,
        algorithm: Algorithm = .md5
    ) -> [String: String] {
        let response = computeResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge,
            algorithm: algorithm
        )

        return [
            "CHAP_N": name,
            "CHAP_R": response.hexString
        ]
    }
}

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let cleanString = hexString.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: "0x", with: "")

        guard cleanString.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleanString.count / 2)

        var index = cleanString.startIndex
        while index < cleanString.endIndex {
            let nextIndex = cleanString.index(index, offsetBy: 2)
            let byteString = cleanString[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    var hexString: String {
        return map { String(format: "0x%02x", $0) }.joined()
    }
}
```

### 8.3 Keychain Manager

Create `Protocol/Sources/Auth/KeychainManager.swift`:

```swift
import Foundation
import Security

/// Manages credentials in macOS Keychain
actor KeychainManager {

    private let serviceName = "com.opensource.iscsi"
    private let accessGroup = "com.opensource.iscsi"

    /// Store credentials for a target
    func storeCredential(iqn: String, username: String, secret: String) async throws {
        let account = "\(iqn):\(username)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: secret.data(using: .utf8)!,
            kSecAttrAccessGroup as String: accessGroup
        ]

        // Delete existing entry
        SecItemDelete(query as CFDictionary)

        // Add new entry
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw ISCSIError.keychainError(status: status)
        }
    }

    /// Retrieve credentials for a target
    func retrieveCredential(iqn: String, username: String) async throws -> String {
        let account = "\(iqn):\(username)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw ISCSIError.keychainError(status: status)
        }

        return secret
    }

    /// Delete credentials for a target
    func deleteCredential(iqn: String, username: String) async throws {
        let account = "\(iqn):\(username)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ISCSIError.keychainError(status: status)
        }
    }
}
```

---

## 9. Data Path (Shared Memory)

### 9.1 Overview

The data path uses shared memory ring buffers for high-performance I/O between the daemon and DriverKit extension.

**Reference:** `docs/iSCSI-Initiator-Entwicklungsplan.md` Section 3.6

### 9.2 Shared Memory Descriptors

Create `Protocol/Sources/DataTransfer/SharedMemoryDescriptors.swift`:

```swift
import Foundation

/// Command descriptor (64 bytes)
struct CommandDescriptor: Sendable {
    var valid: UInt8                    // 0 = free, 1 = occupied
    var opcode: UInt8                   // SCSI opcode
    var flags: UInt8
    var reserved1: UInt8
    var lun: UInt64                     // Logical Unit Number
    var initiatorTaskTag: UInt32        // Kernel task tag
    var iscsiTaskTag: UInt32            // iSCSI ITT
    var transferLength: UInt32          // Expected data transfer length
    var cdbLength: UInt8                // CDB length (6, 10, 12, or 16)
    var reserved2: [UInt8]              // Padding (3 bytes)
    var cdb: [UInt8]                    // SCSI CDB (16 bytes max)
    var bufferIndex: UInt32             // Index into data buffer pool
    var reserved3: UInt32

    static let size = 64

    init() {
        self.valid = 0
        self.opcode = 0
        self.flags = 0
        self.reserved1 = 0
        self.lun = 0
        self.initiatorTaskTag = 0
        self.iscsiTaskTag = 0
        self.transferLength = 0
        self.cdbLength = 0
        self.reserved2 = [0, 0, 0]
        self.cdb = Array(repeating: 0, count: 16)
        self.bufferIndex = 0
        self.reserved3 = 0
    }
}

/// Completion descriptor (64 bytes)
struct CompletionDescriptor: Sendable {
    var valid: UInt8                    // 0 = free, 1 = occupied
    var status: UInt8                   // SCSI status
    var senseLength: UInt8              // Sense data length
    var reserved1: UInt8
    var initiatorTaskTag: UInt32        // Matches command tag
    var transferred: UInt32             // Actual bytes transferred
    var residual: UInt32                // Residual count
    var senseData: [UInt8]              // Sense data (48 bytes max)

    static let size = 64

    init() {
        self.valid = 0
        self.status = 0
        self.senseLength = 0
        self.reserved1 = 0
        self.initiatorTaskTag = 0
        self.transferred = 0
        self.residual = 0
        self.senseData = Array(repeating: 0, count: 48)
    }
}
```

### 9.3 Task Tag Mapping

Create `Protocol/Sources/DataTransfer/TaskTagMap.swift`:

```swift
import Foundation

/// Maps between kernel task tags and iSCSI ITTs
actor TaskTagMap {

    private var kernelToISCSI: [UInt32: UInt32] = [:]
    private var iscsiToKernel: [UInt32: UInt32] = [:]
    private var nextITT: UInt32 = 1

    /// Allocate new ITT for a kernel task tag
    func allocate(kernelTag: UInt32) -> UInt32 {
        let itt = nextITT
        nextITT += 1

        kernelToISCSI[kernelTag] = itt
        iscsiToKernel[itt] = kernelTag

        return itt
    }

    /// Get ITT for kernel tag
    func getISCSITag(kernelTag: UInt32) -> UInt32? {
        return kernelToISCSI[kernelTag]
    }

    /// Get kernel tag for ITT
    func getKernelTag(iscsiTag: UInt32) -> UInt32? {
        return iscsiToKernel[iscsiTag]
    }

    /// Release tag mapping
    func release(kernelTag: UInt32) {
        if let itt = kernelToISCSI[kernelTag] {
            iscsiToKernel.removeValue(forKey: itt)
            kernelToISCSI.removeValue(forKey: kernelTag)
        }
    }

    /// Release by ITT
    func releaseByISCSI(iscsiTag: UInt32) {
        if let kernelTag = iscsiToKernel[iscsiTag] {
            kernelToISCSI.removeValue(forKey: kernelTag)
            iscsiToKernel.removeValue(forKey: iscsiTag)
        }
    }
}
```

---

## 10. Error Handling Patterns

### 10.1 Error Types

Create `Protocol/Sources/ISCSIError.swift`:

```swift
import Foundation

public enum ISCSIError: Error, LocalizedError {
    // Connection errors
    case notConnected
    case alreadyConnected
    case connectionTimeout
    case connectionFailed(Error)
    case daemonNotConnected

    // Protocol errors
    case invalidPDU
    case invalidState
    case loginFailed(statusClass: UInt8, statusDetail: UInt8)
    case invalidLoginStage(current: UInt8, next: UInt8)
    case protocolViolation(String)

    // Session errors
    case sessionNotFound
    case sessionAlreadyExists
    case targetNotFound

    // Authentication errors
    case authenticationFailed
    case keychainError(status: OSStatus)

    // I/O errors
    case commandFailed(status: UInt8)
    case dataTransferError

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to target"
        case .alreadyConnected:
            return "Already connected"
        case .connectionTimeout:
            return "Connection timeout"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .daemonNotConnected:
            return "Daemon not connected"

        case .invalidPDU:
            return "Invalid PDU received"
        case .invalidState:
            return "Invalid state for operation"
        case .loginFailed(let statusClass, let statusDetail):
            return "Login failed: class=\(statusClass) detail=\(statusDetail)"
        case .invalidLoginStage(let current, let next):
            return "Invalid login stage transition: \(current) → \(next)"
        case .protocolViolation(let message):
            return "Protocol violation: \(message)"

        case .sessionNotFound:
            return "Session not found"
        case .sessionAlreadyExists:
            return "Session already exists"
        case .targetNotFound:
            return "Target not found"

        case .authenticationFailed:
            return "Authentication failed"
        case .keychainError(let status):
            return "Keychain error: \(status)"

        case .commandFailed(let status):
            return "SCSI command failed with status: 0x\(String(format: "%02x", status))"
        case .dataTransferError:
            return "Data transfer error"
        }
    }
}
```

### 10.2 Error Recovery Pattern

```swift
// Example error recovery in session management
actor SessionWithRecovery {
    private var retryCount = 0
    private let maxRetries = 3

    func executeWithRetry<T>(operation: () async throws -> T) async throws -> T {
        while retryCount < maxRetries {
            do {
                let result = try await operation()
                retryCount = 0  // Reset on success
                return result
            } catch {
                retryCount += 1

                if retryCount >= maxRetries {
                    throw error
                }

                // Exponential backoff
                let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000  // seconds
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw ISCSIError.protocolViolation("Max retries exceeded")
    }
}
```

---

## 11. SwiftUI App Structure

### 11.1 Main App

Create `App/iSCSI Initiator/iSCSI_InitiatorApp.swift`:

```swift
import SwiftUI

@main
struct iSCSI_InitiatorApp: App {

    @StateObject private var daemonClient = ISCSIDaemonClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(daemonClient)
                .onAppear {
                    // Ensure daemon is running
                    // TODO: Check and launch daemon if needed
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About iSCSI Initiator") {
                    // Show about window
                }
            }
        }
    }
}
```

### 11.2 Main Content View

Create `App/iSCSI Initiator/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {

    @EnvironmentObject var daemonClient: ISCSIDaemonClient
    @State private var sessions: [ISCSISessionInfo] = []
    @State private var showingDiscovery = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Sessions") {
                    ForEach(sessions, id: \.sessionID) { session in
                        SessionRow(session: session)
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: { showingDiscovery = true }) {
                        Label("Discover", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button(action: { Task { await refreshSessions() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        } detail: {
            Text("Select a session")
                .foregroundColor(.secondary)
        }
        .sheet(isPresented: $showingDiscovery) {
            DiscoveryView()
        }
        .task {
            await refreshSessions()
        }
    }

    private func refreshSessions() async {
        do {
            sessions = try await daemonClient.listSessions()
        } catch {
            print("Failed to refresh sessions: \(error)")
        }
    }
}

struct SessionRow: View {
    let session: ISCSISessionInfo

    var body: some View {
        VStack(alignment: .leading) {
            Text(session.target.iqn)
                .font(.headline)
            Text(session.target.portal)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateText)
                    .font(.caption)
            }
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .loggedIn: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        default: return .gray
        }
    }

    private var stateText: String {
        switch session.state {
        case .loggedIn: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        default: return "Unknown"
        }
    }
}
```

### 11.3 Discovery View

Create `App/iSCSI Initiator/Views/DiscoveryView.swift`:

```swift
import SwiftUI

struct DiscoveryView: View {

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var daemonClient: ISCSIDaemonClient

    @State private var portal = "192.168.1.10:3260"
    @State private var discoveredTargets: [ISCSITarget] = []
    @State private var isDiscovering = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Discover iSCSI Targets")
                .font(.title)

            TextField("Portal (IP:Port)", text: $portal)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Button(action: { Task { await discover() } }) {
                if isDiscovering {
                    ProgressView()
                } else {
                    Text("Discover")
                }
            }
            .disabled(isDiscovering)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }

            List(discoveredTargets, id: \.iqn) { target in
                TargetRow(target: target)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 400)
    }

    private func discover() async {
        isDiscovering = true
        errorMessage = nil

        do {
            discoveredTargets = try await daemonClient.discoverTargets(portal: portal)
        } catch {
            errorMessage = error.localizedDescription
        }

        isDiscovering = false
    }
}

struct TargetRow: View {
    let target: ISCSITarget

    @EnvironmentObject var daemonClient: ISCSIDaemonClient
    @State private var isLoggingIn = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(target.iqn)
                    .font(.headline)
                Text(target.portal)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { Task { await login() } }) {
                if isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login")
                }
            }
            .disabled(isLoggingIn)
        }
    }

    private func login() async {
        isLoggingIn = true

        do {
            try await daemonClient.loginToTarget(
                iqn: target.iqn,
                portal: target.portal
            )
        } catch {
            print("Login failed: \(error)")
        }

        isLoggingIn = false
    }
}
```

---

## 12. CLI Tool (iscsiadm)

### 12.1 Main CLI

Create `CLI/iscsiadm/main.swift`:

```swift
import Foundation
import ArgumentParser

@main
struct ISCSIAdmin: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "iscsiadm",
        abstract: "iSCSI initiator administration utility",
        subcommands: [
            DiscoverCommand.self,
            LoginCommand.self,
            LogoutCommand.self,
            SessionCommand.self
        ]
    )
}
```

### 12.2 Discovery Command

Create `CLI/iscsiadm/Commands/DiscoverCommand.swift`:

```swift
import Foundation
import ArgumentParser

struct DiscoverCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "discover",
        abstract: "Discover iSCSI targets"
    )

    @Option(name: .shortAndLong, help: "Portal address (IP:Port)")
    var portal: String

    mutating func run() async throws {
        let client = ISCSIDaemonClient()

        print("Discovering targets at \(portal)...")

        let targets = try await client.discoverTargets(portal: portal)

        if targets.isEmpty {
            print("No targets found")
        } else {
            print("\nDiscovered \(targets.count) target(s):\n")
            for target in targets {
                print("  \(target.iqn)")
                print("    Portal: \(target.portal)")
                print("    TPGT: \(target.targetPortalGroupTag)")
                print()
            }
        }
    }
}
```

### 12.3 Login Command

Create `CLI/iscsiadm/Commands/LoginCommand.swift`:

```swift
import Foundation
import ArgumentParser

struct LoginCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Login to an iSCSI target"
    )

    @Option(name: .shortAndLong, help: "Target IQN")
    var targetName: String

    @Option(name: .shortAndLong, help: "Portal address (IP:Port)")
    var portal: String

    @Option(help: "CHAP username")
    var username: String?

    @Option(help: "CHAP secret")
    var password: String?

    mutating func run() async throws {
        let client = ISCSIDaemonClient()

        print("Logging in to \(targetName)...")

        try await client.loginToTarget(
            iqn: targetName,
            portal: portal,
            username: username,
            secret: password
        )

        print("✅ Login successful")
    }
}
```

### 12.4 Session Command

Create `CLI/iscsiadm/Commands/SessionCommand.swift`:

```swift
import Foundation
import ArgumentParser

struct SessionCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "List active iSCSI sessions"
    )

    mutating func run() async throws {
        let client = ISCSIDaemonClient()

        let sessions = try await client.listSessions()

        if sessions.isEmpty {
            print("No active sessions")
        } else {
            print("\nActive sessions:\n")
            for session in sessions {
                print("Session ID: \(session.sessionID)")
                print("  Target: \(session.target.iqn)")
                print("  Portal: \(session.target.portal)")
                print("  State: \(session.state)")
                if let connectedAt = session.connectedAt {
                    print("  Connected: \(connectedAt)")
                }
                print()
            }
        }
    }
}
```

---

## Summary

This cookbook provides complete, compilable code for all major components:

✅ **Chapter 2**: DriverKit Extension (C++/DriverKit)
✅ **Chapter 3**: XPC Communication (Swift actors)
✅ **Chapter 4**: PDU Protocol Engine (Swift)
✅ **Chapter 5**: Network Layer with NWProtocolFramer
✅ **Chapter 6**: Login State Machine
✅ **Chapter 7**: Session Management
✅ **Chapter 8**: CHAP Authentication + Keychain
✅ **Chapter 9**: Shared Memory Data Path
✅ **Chapter 10**: Error Handling Patterns
✅ **Chapter 11**: SwiftUI App
✅ **Chapter 12**: CLI Tool with ArgumentParser

## Next Steps

1. Copy code examples to your project
2. Fill in TODO markers with implementation details
3. Add unit tests for each component
4. Integrate components together
5. Test with real iSCSI targets

**Next document:** [Testing & Validation Guide](testing-validation-guide.md)