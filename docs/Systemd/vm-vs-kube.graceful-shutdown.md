# Graceful Shutdown: Kubernetes vs VM

- [Graceful Shutdown: Kubernetes vs VM](#graceful-shutdown-kubernetes-vs-vm)
  - [1. VM vs Kubernetes Shutdown Differences](#1-vm-vs-kubernetes-shutdown-differences)
  - [2. Applying the "30-Second Rule" in Systemd](#2-applying-the-30-second-rule-in-systemd)

## 1. VM vs Kubernetes Shutdown Differences

The fundamental goal of a graceful shutdown is the same (ensure service availability and good UX), but there are differences in **who manages the timer and who enforces termination**.

| Item | Kubernetes Pod | VM (Systemd Service) |
| --- | --- | --- |
| **Timer Manager** | The Kubelet starts the timer. | `systemd` starts the timer. |
| **Signals Used** | `SIGTERM` first, followed by `SIGKILL` on expiry. | `SIGTERM` first (or configured signal), followed by `SIGKILL` on expiry. |
| **Grace Period** | `terminationGracePeriodSeconds` (Default 30s). | `TimeoutStopSec` (Default 90s). |
| **Network Isolation** | The Endpoint Controller **automatically** removes the Pod from routing. | Dependent on Load Balancer configuration (LB Deregistration Delay) and requires **manual or scripted control** (Application responsibility). |

## 2. Applying the "30-Second Rule" in Systemd

While the Kubernetes default is 30 seconds, `systemd`'s default grace period is set longer at 90 seconds. However, for latency-sensitive applications like Web services, the shorter 30-second duration should be consciously applied in `systemd` to balance **safety and rapid resource release**.
