# `systemd`: `SO_REUSEPORT`

- [`systemd`: `SO_REUSEPORT`](#systemd-so_reuseport)
  - [Sequence Changes and Notes in the Systemd Environment](#sequence-changes-and-notes-in-the-systemd-environment)
    - [Main Changes and Notes](#main-changes-and-notes)
  - [Implementation](#implementation)

## Sequence Changes and Notes in the Systemd Environment

The following two points are the main changes when operating in a `systemd` environment:

1. **Actor for Starting/Stopping Services:** The Orchestration Tool (O) issues commands via `systemd` instead of directly commanding the processes (NewApp, OldApp).
2. **Grace Period Management:** `systemd` takes responsibility for forceful termination (`SIGKILL`) based on `TimeoutStopSec`.

Below is a more detailed sequence that incorporates coordination with `systemd`.

```mermaid
sequenceDiagram
    participant O as Orchestration Tool (Script/Ansible)
    participant S as systemd
    participant NewApp as New Application Process (v2)
    participant OldApp as Old Application Process (v1)

    Note over O: **Deployment Start (Goal: Replace v1 with v2)**

    O->>S: 1. systemctl start new-app-v2.service
    S->>NewApp: 1a. Launch New App (v2)
    NewApp->>NewApp: 2. Set SO_REUSEPORT on Socket
    NewApp->>NewApp: 3. Bind & Listen on Shared Port (8080)
    Note over NewApp: Kernel now routes NEW traffic to both v1 and v2

    S->>O: 4. Wait for New App v2 status to be 'ready' (via Type=notify or health check)
    Note over O: New App (v2) is now ready to receive traffic

    O->>S: 5. systemctl stop old-app-v1.service
    S->>OldApp: 5a. Send Termination Signal (SIGTERM)
    Note over S: **systemd starts TimeoutStopSec countdown (e.g., 30s)**

    OldApp->>OldApp: 6. **Close Listening Socket**
    Note over OldApp: Kernel instantly stops routing NEW connections to v1. All NEW traffic goes to v2.

    OldApp->>OldApp: 7. Process remaining Active Requests

    alt Remaining requests completed
        OldApp->>S: 8. Process Exit (Exit 0)
        S->>O: 8a. Old App v1 reported as stopped
    else Timeout expires (30s)
        S->>OldApp: 8. (Forced) SIGKILL
        S->>O: 8a. Old App v1 reported as failed/killed
    end

    O->>O: 9. Deployment Complete

```

### Main Changes and Notes

1. **Delegation of Responsibility (Steps 1, 5, 8):**
   1. In the original sequence, orchestration (O) directly started and stopped the apps. In a `systemd` environment, O sends commands via **`systemctl`** to `systemd`, and `systemd` handles the actual process management (launching, sending `SIGTERM`, executing `SIGKILL`).
2. **Management of `TimeoutStopSec` (Steps 5a, 8):**
   1. `systemd` starts the `TimeoutStopSec` timer (e.g., 30 seconds) specified in the configuration file (`.service`) the moment it sends `SIGTERM`.
   2. The responsibility and actor for forceful termination (`SIGKILL`) is **`systemd`**, not the orchestration tool.
3. **Process Name Management:**
   1. To achieve this hot deployment, the orchestration tool must either manage **the old and new processes with different `systemd` unit names** or track process IDs externally to `systemd` and have the logic to switch between the old and new versions.

In summary, the **traffic switchover logic using `SO_REUSEPORT` (closing the listener)** remains unchanged within the application, but its triggering and monitoring are performed through `systemd`.

## Implementation

```bash
# Example: Logic to manage the "current production" via a symbolic link
# /etc/systemd/system/app.service -> /etc/systemd/system/app-blue.service

# 1. Check the current target (Assume Blue is running)
CURRENT=$(readlink -f /etc/systemd/system/app.service)

# 2. Start the opposite side (Green)
systemctl start app-green.service

# 3. When Green is ready, atomically replace the symbolic link
ln -sfn /etc/systemd/system/app-green.service /etc/systemd/system/app.service
systemctl daemon-reload

# 4. Stop the old one (Blue)
systemctl stop app-blue.service
```
