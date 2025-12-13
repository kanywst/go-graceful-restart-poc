# Golang: Implementation of File Descriptor Passing

- [Golang: Implementation of File Descriptor Passing](#golang-implementation-of-file-descriptor-passing)
  - [1. Overview: What is File Descriptor Passing (FD Passing)?](#1-overview-what-is-file-descriptor-passing-fd-passing)
    - [Technical Concept](#technical-concept)
    - [Core Technology for Realization](#core-technology-for-realization)
  - [2. Implementation in Go (Using the `sys/unix` Package)](#2-implementation-in-go-using-the-sysunix-package)
    - [Definition of the `fdpassing.Fd`](#definition-of-the-fdpassingfd)
    - [2.1. FD Sender (`Send` Method)](#21-fd-sender-send-method)
    - [2.2. FD Receiver (`Recv` Method)](#22-fd-receiver-recv-method)
  - [3. Sample Program Execution and Communication Flow Sample](#3-sample-program-execution-and-communication-flow-sample)
    - [Confirmation of Execution Results](#confirmation-of-execution-results)

## 1. Overview: What is File Descriptor Passing (FD Passing)?

### Technical Concept

FD Passing is a technique for **transferring a file descriptor (an integer identifier) of a resource (file, socket, pipe, etc.) already opened in one process to another process** via a special feature of Unix domain sockets.

Normally, each process has its own FD table, but this technique allows the receiving process to access the same resource and continue communication processing. It is also possible to transfer sockets between different languages, such as Go and C.

### Core Technology for Realization

The feature that enables this functionality is **`SCM_RIGHTS`**, a control message feature of **Unix domain sockets**.

## 2. Implementation in Go (Using the `sys/unix` Package)

In Go, FD Passing is implemented using the `golang.org/x/sys/unix` package, which provides low-level operations for the standard library.

### Definition of the `fdpassing.Fd`

StructThis struct wraps a Go `net.UnixConn` and provides functionality for sending and receiving FDs.

```go
package fdpassing

import (
    "net"
    "golang.org/x/sys/unix"
)

// Fd is a struct for passing file descriptors using Unix domain sockets.
type Fd struct {
    conn *net.UnixConn
}

// NewFd creates a new Fd instance from a given Unix domain socket connection.
func NewFd(conn *net.UnixConn) *Fd {
    fd := new(Fd)
    fd.conn = conn
    return fd
}

```

### 2.1. FD Sender (`Send` Method)

The process sends the file descriptor (`fd`) it holds via the Unix domain socket.

```go
// Send transmits a file descriptor over the Unix domain socket.
func (me *Fd) Send(fd int) error {
    var (
        dummy  = make([]byte, 1)
        // Create the SCM_RIGHTS control message and store the FD
        rights = unix.UnixRights(fd)
        err    error
    )
    // Use WriteMsgUnix to send the rights (FD) along with dummy data
    _, _, err = me.conn.WriteMsgUnix(dummy, rights, nil)
    if err != nil {
        return err
    }
    return nil
}

```

### 2.2. FD Receiver (`Recv` Method)

The receiver receives the control message via the Unix domain socket and recovers the FD.

```go
// Recv receives a file descriptor over the Unix domain socket.
func (me *Fd) Recv() (int, error) {
    var (
        dummy = make([]byte, 1)
        // Prepare buffer for control message
        oob   = make([]byte, unix.CmsgSpace(4)) 
    )
    // Use ReadMsgUnix to read the message and OOB data (control message)
    _, _, flags, _, err := me.conn.ReadMsgUnix(dummy, oob)
    if err != nil {
        return -1, err
    }
    // ... (Error check omitted) ...

    // Parse the control message
    msgs, err := unix.ParseSocketControlMessage(oob)
    if err != nil {
        return -1, err
    }
    // ... (Message count check omitted) ...

    // Extract the FD (UnixRights) from the parsed control message
    fds, err := unix.ParseUnixRights(&msgs[0])
    if err != nil {
        return -1, err
    }
    // ... (FD count check omitted) ...

    return fds[0], nil // Return the received FD
}

```

## 3. Sample Program Execution and Communication Flow Sample

The sample program demonstrates the procedure for delegating connection responsibility between two processes: a TCP server (`tcpserver`) and a UDS server (`udsserver`).

| Process Name | Role |
| --- | --- |
| **`tcp-server` (Sender)** | `Accept()`s a client connection on TCP port `:8888`, obtains the FD of the established socket without closing it, and then sends that FD to `uds-server` via UDS. |
| **`uds-server` (Receiver)** | Waits on the UDS, receives the FD from `tcp-server`. It recovers the `net.Conn` from the FD using `os.NewFile` and `net.FileConn`, and **continues the communication process**. |
| **`tcp-client`** | Connects to TCP port `:8888` and communicates without knowing that the socket has been transferred. |

### Confirmation of Execution Results

The execution log confirms that the connection handling seamlessly moves between the processes.

1. `tcp-server` `Accept`s the client connection.
2. `tcp-server` `passing`s `fd=8` to `uds-server`.
3. `uds-server` receives it as `fd=7`, and uses this FD to send "hello" to the client.
4. The client receives "hello" and replies with "HELLO".
5. `uds-server` receives "HELLO" and completes the communication.

This flow shows that the **responsibility for processing moved from `tcp-server` to `uds-server` without the TCP connection being terminated**. This is the fundamental technology used for zero downtime deployment in applications like Envoy's hot restart.
