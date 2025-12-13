# File Descriptor Passing

- [File Descriptor Passing](#file-descriptor-passing)
  - [Mechanism of Socket Passing](#mechanism-of-socket-passing)
  - [Implementation Method in Go (Conceptual Code)](#implementation-method-in-go-conceptual-code)
    - [1. Sender (Old Process)](#1-sender-old-process)
    - [2. Receiver (New Process)](#2-receiver-new-process)
  - [Existing Libraries (Avoid Reinventing the Wheel)](#existing-libraries-avoid-reinventing-the-wheel)
  - [`SO_REUSEPORT` vs `Socket Passing`](#so_reuseport-vs-socket-passing)

This is achieved using the features of **Unix Domain Socket (UDS)** and **`SCM_RIGHTS`**, which are functionalities of Unix-like operating systems.

This allows the **file descriptor of the socket currently listening on a port** held by the running process (old version) to be physically copied and passed to another process (new version).

## Mechanism of Socket Passing

In Unix-like operating systems, "everything is a file," and an open socket is managed as a simple integer value (File Descriptor: FD).

1. The **Old Process** connects with the **New Process** via a **Unix Domain Socket**.
2. A special system call (`sendmsg`) is used to send "a reference to the FD" along with some data.
3. The **New Process** receives it and duplicates it (`dup`) into its own FD space.
4. The **New Process** recovers a `net.Listener` from that FD and starts `Accept()`ing connections on the same port.

## Implementation Method in Go (Conceptual Code)

Low-level operations are possible using Go's standard library packages like `syscall` and `net`.

### 1. Sender (Old Process)

The process extracts the file descriptor from the already listening `net.Listener` and sends it via UDS.

```go
import (
    "net"
    "syscall"
)

func sendSocket(conn *net.UnixConn, listener *net.TCPListener) error {
    // 1. Extract the file from the listener
    file, err := listener.File()
    if err != nil {
        return err
    }
    defer file.Close()

    // 2. Get the FD
    fd := int(file.Fd())

    // 3. Encode the FD as a special message called "SCM_RIGHTS"
    rights := syscall.UnixRights(fd)

    // 4. Write to the Unix socket along with some dummy data
    // (The key point is sending the FD as OOB: Out-Of-Band data)
    _, _, err = conn.WriteMsgUnix([]byte("dummy"), rights, nil)
    return err
}

```

### 2. Receiver (New Process)

The process receives the message from the UDS, extracts the attached FD, and restores it to a Go `net.Listener`.

```go
import (
    "net"
    "os"
    "syscall"
)

func receiveSocket(conn *net.UnixConn) (*net.TCPListener, error) {
    buf := make([]byte, 32)
    oob := make([]byte, syscall.CmsgSpace(4)) // Space for one FD

    // 1. Read the message and OOB data (FD)
    _, oobn, _, _, err := conn.ReadMsgUnix(buf, oob)
    if err != nil {
        return nil, err
    }

    // 2. Parse the socket control message from the OOB data
    msgs, err := syscall.ParseSocketControlMessage(oob[:oobn])
    if err != nil {
        return nil, err
    }

    // 3. Extract the FD
    fds, err := syscall.ParseUnixRights(&msgs[0])
    if err != nil {
        return nil, err
    }
    fd := fds[0]

    // 4. Create an os.File from the FD
    file := os.NewFile(uintptr(fd), "listener")
    defer file.Close()

    // 5. Restore the net.Listener from the File (Now listening!)
    l, err := net.FileListener(file)
    if err != nil {
        return nil, err
    }

    return l.(*net.TCPListener), nil
}

```

## Existing Libraries (Avoid Reinventing the Wheel)

When implementing Graceful Restart using Socket Passing in Go, it is common practice to use reliable libraries rather than writing it from scratch.

The following libraries are well-known and perform this exact "Socket Passing":

1. **cloudflare/tableflip** (Recommended)
   1. Made by Cloudflare. Specializes in Graceful Upgrades in Linux environments and provides a very clean abstraction of Socket Passing to a child process.
   2. The flow of "parent passes FD to child, child waits for parent to die" is easy to implement.
2. **facebookgo/grace**
   1. Made by Facebook. An older library that was the de facto standard for Graceful Restarting `net/http` servers (though maintenance is slightly stagnant now).

## `SO_REUSEPORT` vs `Socket Passing`

Let's compare why applications like Envoy and Nginx go to the trouble of using Socket Passing versus `SO_REUSEPORT`.

| Feature | SO_REUSEPORT (Kernel Feature) | Socket Passing (App Implementation) |
| --- | --- | --- |
| **Implementation Difficulty** | **Easy** (Option setting only) | **Difficult** (Requires implementing IPC) |
| **Connection Loss** | Essentially none (Kernel distributes) | **Absolutely none** (Socket moves while open) |
| **Listener State** | Handled as separate sockets | **Shares the identical socket** |
| **Connection Draining** | Left to the old process | Old process drains after passing the socket |
| **Statistics Inheritance** | Impossible (Separate processes) | **Possible** (Statistics data can be sent via UDS) |

**Why Envoy Chooses Socket Passing:**

Envoy needs not only to take over the port but also to **inherit "statistics" and "dynamic configuration states"** (Hot Restart) to the new process. Therefore, IPC via UDS is essential, and Socket Passing is adopted as a reliable way to transfer the socket alongside the data.
