# SO_REUSEPORT vs File Descriptor Passing

- [SO\_REUSEPORT vs File Descriptor Passing](#so_reuseport-vs-file-descriptor-passing)
  - [Supplement: Distinguishing Roles](#supplement-distinguishing-roles)

| Feature | `SO_REUSEPORT` | Socket Passing (FD Passing) |
| --- | --- | --- |
| **Technology Classification** | **Socket Option** | **Inter-Process Communication (IPC)** |
| **Purpose** | Sharing the **Listening** role | Handing over **Established Connections** |
| **Target** | **Newly arriving connections** | **Existing or listening sockets** |
| **Principle of Operation** | The OS kernel permits multiple processes to `bind/listen` on the same port and **load balances new traffic** among them. | Uses Unix Domain Sockets and `SCM_RIGHTS` to **physically transfer the file descriptor of the socket to another process**. |
| **Advantages** | Easy to implement. Switching of new traffic occurs instantly at the kernel level. | Can transfer statistics and configuration simultaneously. **Can update the process without dropping existing long-term connections** because the socket ID remains the same. |
| **Disadvantages** | **Cannot take over existing connections** (the old process must complete its drain period). | Complex to implement. Requires inter-process communication. |

## Supplement: Distinguishing Roles

1. **Role of `SO_REUSEPORT`:**
   1. This mechanism "shares the port," instructing the OS to **"immediately switch the destination for new connections to the new process!"** the moment the new process starts up.
2. **Role of Socket Passing:**
   1. This provides a solution to one of the **most difficult challenges in zero downtime deployment**—**"What to do with long-lived connections currently being processed?"**—by offering: "Take over the processing without dropping the connection!" Envoy adopts Socket Passing because it prioritizes this capability to take over existing connections.

Therefore, these are fundamentally different technologies, and in high-performance systems, they are sometimes used in combination.
