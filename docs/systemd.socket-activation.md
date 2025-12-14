# Systemd: Socket Activation

- [Systemd: Socket Activation](#systemd-socket-activation)
  - [Overview](#overview)
  - [Sequence](#sequence)
  - [Steps](#steps)
    - [1. Go Code Modification](#1-go-code-modification)
    - [2. Create Socket Unit (`my-app.socket`)](#2-create-socket-unit-my-appsocket)
    - [3. Create Service Unit (`my-app.service`)](#3-create-service-unit-my-appservice)
    - [4. Execution Commands](#4-execution-commands)
    - [Who Handles the Kill?](#who-handles-the-kill)

## Overview

In a normal `systemctl restart`, Systemd terminates the old process before starting the new one, resulting in a brief downtime.

However, by utilizing **Socket Activation**, Systemd holds the listening socket, and the socket remains open even during a restart. When the new process starts, Systemd passes the **socket File Descriptor (FD)** to the new process, which then uses it to accept traffic.

## Sequence

```mermaid
sequenceDiagram
    participant OS as OS/Kernel
    participant S as Systemd (authz-server.socket)
    participant O as Old Authz (v1 Process)
    participant N as New Authz (v2 Process)
    participant C as Client

    Note over O: v1 is running, accepting traffic via FD passed by Systemd
    C->>O: 1. Client Request Handled by v1

    Note over OS: **2. yum update authz-server executed**
    OS->>OS: 2.1. New Binary written to disk (/usr/local/bin/authz-server)
    Note over OS: v1 process remains active, using old binary loaded into memory
    
    Note over S: **3. systemctl restart authz-server.service executed**
    S->>N: 3.1. Launch New Process (v2) from new binary
    
    S->>N: 3.2. **Pass Socket FD to v2** (FD Passing)
    N->>N: 3.3. v2 starts Accept()ing traffic on the shared port

    Note over O,N: v1 and v2 are now running in parallel (Zero-Downtime Window)

    S->>O: 4. Send Termination Signal (SIGTERM)
    O->>O: 4.1. v1 initiates Graceful Shutdown (Stops listening/Accept() & Drains connections)

    C->>S: 5. New Connection Arrives during transition
    S->>N: 5.1. Kernel routes new traffic exclusively to v2 (v1's listener is closed)

    O-->>O: 6. v1 finishes handling in-flight requests
    O-->>S: 6.1. v1 Process Exits (Graceful Shutdown Complete)

    N->>N: 7. v2 Serves ALL Traffic with the Updated Binary
```

## Steps

We assume the Go binary is located at `/usr/local/bin/my-app` and uses port 8080.

### 1. Go Code Modification

The Go code (`main.go`) must be modified to **reconstruct the listener using the FD passed by Systemd**.

```go
// main.go Listener Creation Modification (for Systemd compatibility)
import "os"
// ...
func main() {
    // Systemd passes LISTEN_FDS environment variable and the FD index (0)
    // We switch from SO_REUSEPORT to FD Inheritance logic here
    if os.Getenv("LISTEN_FDS") != "" {
        // Reconstruct the listener using the passed FD (index 0 corresponds to FD 3 by systemd convention)
        f := os.NewFile(uintptr(3), "") 
        listener, _ := net.FileListener(f)
        // ...
    } else {
        // Normal startup (fallback, if not started by systemd)
        listener, _ := net.Listen("tcp", ":8080")
    }
    // ...
}
```

### 2. Create Socket Unit (`my-app.socket`)

This defines the socket configuration and the `SO_REUSEPORT` option.

`/etc/systemd/system/my-app.socket`

```ini
[Unit]
Description=My Application Socket (8080)

[Socket]
# Wait for TCP connections on port 8080
ListenStream=8080

# ★ Have Systemd set the SO_REUSEPORT option ★
# This allows multiple my-app.service instances to share the port
SocketOptions=SO_REUSEPORT

# Define which service to launch upon connection (or restart)
Service=my-app.service

[Install]
WantedBy=sockets.target
```

### 3. Create Service Unit (`my-app.service`)

This defines the application's launch configuration.

`/etc/systemd/system/my-app.service`

```ini
[Unit]
Description=My Application Service
# Set dependency so my-app.socket starts first
Requires=my-app.socket

[Service]
# Path to the Go binary
ExecStart=/usr/local/bin/my-app

# Set service type compatible with Socket Activation
Type=notify

# Graceful termination via SIGTERM
KillMode=mixed
TimeoutStopSec=10s

# Defines that the service will be activated by this socket
# Systemd will pass the socket FD
Sockets=my-app.socket

# Environment settings
User=app_user
Group=app_user
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### 4. Execution Commands

1. **Reload configuration files**:

    ```bash
    sudo systemctl daemon-reload
    ```

2. **Enable the socket**:

    ```bash
    sudo systemctl enable my-app.socket
    ```

3. **Start the service (via socket)**:

    ```bash
    sudo systemctl start my-app.socket
    ```

4. **Zero-Downtime Restart**:

    ```bash
    # Systemd gracefully terminates the old process and starts the new one
    sudo systemctl restart my-app.service
    ```

### Who Handles the Kill?

In the socket activation scenario, **Systemd handles the Kill**.

1. The `systemctl restart my-app.service` command is executed.
2. Systemd sends a `SIGTERM` to the old process **before** killing it.
3. The Go binary receives `SIGTERM` and executes its Graceful Shutdown logic (`server.Shutdown()`), completing in-flight requests and terminating voluntarily.
4. The new process, already started and accepting traffic using the FD passed by Systemd, ensures zero downtime.
