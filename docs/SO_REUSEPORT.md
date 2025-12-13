# SO_REUSEPORT

- [SO\_REUSEPORT](#so_reuseport)
  - [Overview](#overview)
  - [Usage](#usage)
  - [Challenges](#challenges)

## Overview

`SO_REUSEPORT` is a TCP/IP socket option that **allows multiple independent sockets to bind to the same IP address and port number** simultaneously.

This is because, in traditional socket programming, even when `SO_REUSEADDR` was set, its primary purpose was the reuse of sockets in the **TIME\_WAIT** state, and it was generally not possible for multiple processes to share the listening port simultaneously.

## Usage

Applying the `SO_REUSEPORT` option to the listening socket is what enables multiple different server processes (or threads) to bind to the same IP address and port and wait for connections.

## Challenges

1. Complete Connection Preservation (No Dropped Connections):
   1. With `SO_REUSEPORT` or `systemd` switchovers, there is a non-zero risk of slight packet loss or connection errors occurring depending on the timing.
      1. Long-lived Connections:
         1. Envoy handles a large number of long-maintained connections, such as gRPC and HTTP/2. Forcing the termination of these connections significantly impacts the entire system, requiring an extremely smooth transition (Draining).
         2. By using Socket Passing, the socket itself is never closed, which theoretically allows for zero loss of TCP connections.
2. Inheritance of Statistics (Stats) and State:
   1. Envoy emphasizes Observability. By performing memory sharing at the binary level, counters and statistics can be inherited by the new process without being reset. This is impossible with `systemd`-level management.
3. Platform Independence (Portability):
   1. Depending on `systemd` means that the same behavior cannot be guaranteed in environments without `systemd` (such as older Linux, inside containers, or non-Linux environments).
   2. By embedding the logic within the binary, the same high-quality Hot Restart can be provided anywhere—in Kubernetes, VMs, or manual executions.
