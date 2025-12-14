# Graceful Shutdown using `SO_REUSEPORT`

- [Graceful Shutdown using `SO_REUSEPORT`](#graceful-shutdown-using-so_reuseport)
  - [VM Sequence](#vm-sequence)
    - [Key Points of the Sequence and the Role of Orchestration](#key-points-of-the-sequence-and-the-role-of-orchestration)

## VM Sequence

This diagram illustrates the orchestration flow during a new version deployment, showing how the old process is stopped and traffic is instantly switched to the new process.

```mermaid
sequenceDiagram
    participant O as Orchestration Tool (Script/Ansible)
    participant NewApp as New Application Process (v2)
    participant OldApp as Old Application Process (v1)

    Note over O: **Deployment Start (Goal: Replace v1 with v2)**

    O->>NewApp: 1. Launch New App (v2)
    NewApp->>NewApp: 2. Set SO_REUSEPORT on Socket
    NewApp->>NewApp: 3. Bind & Listen on Shared Port (8080)
    Note over NewApp: Kernel now routes NEW traffic to both v1 and v2

    O->>NewApp: 4. Wait for v2 Readiness/Health Check Success
    Note over O: New App (v2) is now ready to receive traffic

    O->>OldApp: 5. Send Termination Signal (SIGTERM)
    Note over O,OldApp: **Graceful Shutdown Starts for v1**

    OldApp->>OldApp: 6. **Close Listening Socket**
    Note over OldApp: Kernel instantly stops routing NEW connections to v1. All NEW traffic goes to v2.

    OldApp->>OldApp: 7. Process remaining Active Requests
    Note over OldApp: Waits up to TimeoutStopSec (e.g., 30s)

    alt Remaining requests completed
        OldApp->>O: 8. Process Exit (Exit 0)
    else Timeout expires (30s)
        O->>OldApp: 8. (Forced) SIGKILL
    end

    O->>O: 9. Deployment Complete

```

### Key Points of the Sequence and the Role of Orchestration

1. **Simultaneous Binding (Steps 2, 3):**
   1. `SO_REUSEPORT` allows the new application (v2) to bind to the same port as the old application (v1). This enables the new process to start up without interrupting traffic.
2. **Instant of Traffic Switchover (Step 6):**
   1. When the orchestration layer sends `SIGTERM` (Step 5) and the application (v1) **closes its listening socket** (Step 6), the kernel automatically switches the routing of **new connections** exclusively to the surviving new process (v2).
   2. At this moment, no coordination with an external load balancer is required, and the **zero-downtime** switchover is complete.
3. **Responsibility for Shutdown (Steps 7, 8):**
   1. The old process (v1), after stopping its listener, is responsible for completing any existing in-flight processing within the configured grace period.
   2. The orchestration tool waits for the process to exit voluntarily.
