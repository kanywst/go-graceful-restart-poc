# Core Signals in Linux/Unix

The biggest difference between these signals lies in whether **the application can ignore the signal or customize its handling (catchability)**.

## Key Termination Signal Differences

| Signal Name | Number | Purpose | Catchability | Role in Kubernetes |
| --- | --- | --- | --- | --- |
| **`SIGTERM`** | 15 | **Graceful Termination Request** | **Catchable** | The signal **first** sent by the Kubelet. It politely requests the application to shut down safely within the grace period. |
| **`SIGKILL`** | 9 | **Immediate Termination** | **Uncatchable** | The signal **last** sent by the Kubelet. If the process does not terminate within the grace period, the OS forcibly terminates the process. |
| **`SIGINT`** | 2 | **Interruption** | **Catchable** | Typically used for **manual interruptions** from the user (e.g., Ctrl+C). Like `SIGTERM`, applications can execute custom shutdown logic. |

### 1. SIGTERM (Terminate Signal)

`SIGTERM` is a **polite request** to "please terminate."

* **Catchable**: An application can execute its own handler (custom logic) upon receiving this signal.
* **Purpose**: Used to initiate a Graceful Shutdown. The application, upon receiving `SIGTERM`, executes logic such as rejecting new connections, completing in-flight requests, and cleaning up resources, before exiting voluntarily.
* **Kubernetes**: This is the first signal sent by the Kubelet during Pod termination, acting as the trigger for the Graceful Shutdown sequence.

### 2. SIGKILL (Kill Signal)

`SIGKILL` is a **forceful command** to "stop immediately!"

* **Uncatchable**: This signal **cannot** be caught, ignored, or delayed at the application level. The Linux kernel terminates the process directly.
* **Purpose**: Used by the system to forcefully terminate runaway processes or processes that ignore `SIGTERM`. The application is given no chance to clean up its in-flight work.
* **Kubernetes**: If the application fails to terminate within the `terminationGracePeriodSeconds`, the Kubelet sends this signal, resulting in the container's immediate and forceful termination.

### 3. SIGINT (Interrupt Signal)

`SIGINT` is the "interrupt" signal.

* **Catchable**: An application can set up its own handler for this signal.
* **Purpose**: Typically sent to a process when a user presses `Ctrl+C` in a terminal, requesting the process to stop. Many applications are designed to perform shutdown processes similar to `SIGTERM` when receiving `SIGINT`.
* **Kubernetes**: While Kubelet's standard termination process uses `SIGTERM`, local debugging or container startup scripts might rely on `SIGINT` handling to initiate a shutdown.

## Summary

From the perspective of a Graceful Shutdown in Kubernetes, a **safe application** is one that correctly handles the following sequence:

1. **Receives `SIGTERM`, completes its work within the grace period, and exits voluntarily.**
2. **Does not linger until `SIGKILL` arrives.**

Application developers must implement a handler for `SIGTERM` (to reject new connections and complete existing work) to properly respond to planned termination initiated by Kubernetes.
