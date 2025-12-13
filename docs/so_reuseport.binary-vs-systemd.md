# `SO_REUSEPORT`: Binary vs Systemd

- [`SO_REUSEPORT`: Binary vs Systemd](#so_reuseport-binary-vs-systemd)
  - [Comparison: Binary Management vs. Systemd Management](#comparison-binary-management-vs-systemd-management)
  - [Conclusion: Recommended Approach](#conclusion-recommended-approach)
    - [Preparation for Choosing Systemd Management](#preparation-for-choosing-systemd-management)

This choice determines the **responsibility for "who controls the process lifecycle and at what granularity."**

## Comparison: Binary Management vs. Systemd Management

| Feature | Method A: Binary-Level Management (Direct Process Control) | Method B: Systemd-Level Management (Service Control) |
| --- | --- | --- |
| **Definition** | A deployment tool enters the VM directly (e.g., via SSH), identifies the PID, and starts/stops the process using `nohup` or `&` (`kill -TERM <PID>`). | A deployment tool delegates process lifecycle management to `systemd` via `systemctl start/stop` commands. |
| **Orchestration Setup** | **Process ID (PID) Tracking:** Requires logic (e.g., utilizing PID files) to reliably identify and manage the PIDs of both old and new processes. | **Service Unit Definition:** Requires preparing and managing the naming conventions for the **service unit files** (or instances) of the old and new versions. |
| **Grace Period/Termination** | The orchestration tool itself must **implement a timer** and needs code logic to wait 30 seconds after `SIGTERM`, then send `SIGKILL` upon timeout. | Can be **delegated to `systemd`'s `TimeoutStopSec**`. The orchestration tool only needs to wait for `systemctl stop` to complete. |
| **Log Management** | Requires building a separate mechanism for the deployment tool to correctly redirect application output (`stdout`/`stderr`) to files and manage log rotation. | **Journald** integration is automatic via `systemd`, simplifying log management. |
| **Reboot Resilience** | Processes must be restarted manually or via custom scripts after a VM reboot. | Automatic restart is possible via `systemd` directives such as **`Restart=always`**. |
| **Deployment Complexity** | High (Requires low-level OS commands and process tracking). | Low to Moderate (Abstracted by high-level `systemctl` commands, leading to better stability). |

## Conclusion: Recommended Approach

In most cases, **Method B (Systemd-Level Management) is strongly recommended** because `systemd` is the standard for process management in Linux environments, offering rich features like log management, automated restarts, and a forceful termination timer (`TimeoutStopSec`).

### Preparation for Choosing Systemd Management

1. **Determine Unit File Strategy:** As confirmed in the question "Binary-level management or Systemd-level management," define a **naming convention for the unit files** (or instance units) to run old and new processes in parallel, such as `app-v1.service` and `app-v2.service`.
2. **Set `TimeoutStopSec`:** Explicitly include `TimeoutStopSec=30s` in all service units, delegating the responsibility for forceful termination to `systemd`.

Although Method B involves the overhead of creating more unit files during the preparation phase, the subsequent stability of deployment execution, operational phase, and root cause analysis in case of errors are significantly improved.
