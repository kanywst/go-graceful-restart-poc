# Ext-Authz Zero Downtime Deployment Strategy

- [Ext-Authz Zero Downtime Deployment Strategy](#ext-authz-zero-downtime-deployment-strategy)
  - [1. Kubernetes Environment (Standard Best Practice)](#1-kubernetes-environment-standard-best-practice)
  - [2. VM/Systemd Environment (Using SO\_REUSEPORT)](#2-vmsystemd-environment-using-so_reuseport)
  - [3. VM/Systemd Environment (Without SO\_REUSEPORT)](#3-vmsystemd-environment-without-so_reuseport)
    - [Processing Sequence: Graceful Shutdown with LB Coordination](#processing-sequence-graceful-shutdown-with-lb-coordination)
    - [Decisive Difference from `SO_REUSEPORT`](#decisive-difference-from-so_reuseport)
  - [Conclusion](#conclusion)

Since the Ext-Authz server does not have long-lived connections, complex **application implementation** like Socket Passing, which Envoy uses, **is unnecessary**. Instead, adopting a standard Zero Downtime Deployment (ZDD) strategy utilizing **orchestration and infrastructure layer features** is the best approach.

## 1. Kubernetes Environment (Standard Best Practice)

Kubernetes' Rolling Update feature achieves ZDD without application modification by manipulating the Endpoints list. This mechanism is highly effective because the Ext-Authz Pod's IP address is the routing target for Envoy.

```mermaid
sequenceDiagram
    participant K as Kubernetes Control Plane (Endpoint Controller)
    participant KB as Kubelet (on Node)
    participant E as Envoy Proxy (Client of Ext-Authz)
    participant Old as Ext-Authz Pod (v1)
    participant New as Ext-Authz Pod (v2)

    Note over K: **Rolling Update Start**

    K->>New: 1. Launch New Pod (v2)
    New->>K: 2. Ready State (Health Check OK)
    Note over K,E: Kubelet/Controller adds v2 IP to Endpoints list.

    K->>Old: 3. Termination Start
    Note over K: Endpoint Controller removes v1 IP from Endpoints list.

    E->>E: 4. Envoy detects Endpoint change
    Note over E: Envoy instantly stops routing NEW requests to v1.

    K->>KB: 5. SIGTERM Signal
    KB->>Old: 6. Send SIGTERM

    Old->>Old: 7. Graceful Shutdown (Listener.Close + Drain short requests)
    Note over Old: Waits for terminationGracePeriodSeconds (e.g., 30s)

    Old-->>KB: 8. Process Exit (Completed)
    KB->>K: 9. Termination Complete (Pod Deleted)

```

| Step | Action | ZDD Guarantee |
| --- | --- | --- |
| **New Traffic Switchover** | The Endpoint Controller **immediately removes** the v1 IP address from the **Endpoints list** (Step 4). | **Envoy instantly** starts sending requests only to the new Pod (v2). |
| **Drain** | v1 receives `SIGTERM` and completes **short** in-flight requests within the grace period (e.g., 30s) before exiting (Step 7). | In-flight authorization requests are not interrupted. |

## 2. VM/Systemd Environment (Using SO_REUSEPORT)

`SO_REUSEPORT` is the cleanest approach in a VM environment because traffic can be switched instantly using OS kernel features, without relying on load balancer latency.

```mermaid
sequenceDiagram
    participant O as Orchestration Tool (Script/Ansible)
    participant OS as OS Kernel
    participant Old as Ext-Authz Process (v1)
    participant New as Ext-Authz Process (v2)

    Note over O: **Deployment Start**

    O->>New: 1. Launch New App (v2)
    New->>New: 2. Set SO_REUSEPORT on Socket
    New->>OS: 3. Bind & Listen on Shared Port (8080)
    Note over OS: New connections are now load-balanced between v1 and v2.

    O->>New: 4. Wait for v2 Readiness Check Success

    O->>Old: 5. Send Termination Signal (SIGTERM)
    Note over O,Old: **Graceful Shutdown Starts for v1**

    Old->>Old: 6. **Close Listening Socket**
    Note over OS: OS Kernel instantly routes ALL NEW connections to v2 (the only one still listening).

    Old->>Old: 7. Process remaining Active Requests
    Note over Old: Waits up to TimeoutStopSec (e.g., 30s)

    alt Remaining requests completed
        Old->>O: 8. Process Exit (Exit 0)
    else Timeout expires (30s)
        O->>Old: 8. (Forced) SIGKILL
    end

    O->>O: 9. Deployment Complete

```

| Step | Action | ZDD Guarantee |
| --- | --- | --- |
| **New Traffic Switchover** | The OS kernel instantly switches new requests to v2 the **moment v1 closes its listening socket** (Step 6). | Stops accepting new requests **at the fastest speed** without relying on external LB propagation delay. |
| **Drain** | v1 completes in-flight **short-lived** requests before exiting (Step 7). | In-flight authorization requests are not interrupted. |

## 3. VM/Systemd Environment (Without SO_REUSEPORT)

As previously discussed, for a VM/Systemd environment without `SO_REUSEPORT`, the alternative zero-downtime deployment strategy relies on **Load Balancer (LB) Coordination**.

This method intentionally manipulates the application's **health check response** to force the LB to switch traffic.

### Processing Sequence: Graceful Shutdown with LB Coordination

```mermaid
sequenceDiagram
    participant O as Orchestration Tool (Script/Ansible)
    participant LB as Load Balancer
    participant Old as Ext-Authz Process (v1)
    participant New as Ext-Authz Process (v2)

    Note over O: **Deployment Start**

    O->>New: 1. Launch New App (v2)
    New->>LB: 2. Health Check OK (Ready)
    Note over LB: LB adds v2 to rotation.

    O->>Old: 3. Send Termination Signal (SIGTERM)
    Note over O,Old: **Graceful Shutdown Starts for v1**

    Old->>Old: 4. **Listener.Close() & Start Graceful Timer**
    Old->>Old: 5. **Intentionally Fail Health Check Endpoint (e.g., return 503)**

    LB->>Old: 6. Health Check Request
    Old-->>LB: 7. Health Check Fails (e.g., HTTP 503)

    LB->>LB: 8. **LB detects failure and removes v1 from rotation**
    Note over LB: New traffic is now sent only to v2. This step depends on LB propagation delay.

    Old->>Old: 9. Process remaining Active Requests
    Note over Old: Waits for LB Drain Timeout + App Drain Time (e.g., total 60s)

    alt Remaining requests completed
        Old->>O: 10. Process Exit (Exit 0)
    else Timeout expires (Systemd TimeoutStopSec)
        O->>Old: 10. (Forced) SIGKILL
    end

    O->>O: 11. Deployment Complete

```

### Decisive Difference from `SO_REUSEPORT`

| Item | Using `SO_REUSEPORT` | Using LB Coordination |
| --- | --- | --- |
| **Traffic Switcher** | **OS Kernel** | **Load Balancer (LB)** |
| **Switch Reliability/Speed** | **Instantaneous.** The moment v1 closes the listener. | **Delayed.** Depends on the time it takes for the LB to retry the health check and propagate the change across the network (tens of seconds). |
| **Application Role** | Close the listener upon `SIGTERM`. | Close the listener **and intentionally fail the health check** upon `SIGTERM`. |

For this reason, from a ZDD perspective, **using `SO_REUSEPORT` is superior** because it avoids LB propagation delay.

## Conclusion

Downtime for the Ext-Authz server must be avoided, but since it lacks long-lived connections, **overhead-intensive techniques like Socket Passing are unnecessary.**

Adopting a standard ZDD strategy using **Kubernetes Rolling Update** or **`SO_REUSEPORT` with orchestration in a VM environment** is the most efficient approach.
