# SO_REUSEPORT

- [SO\_REUSEPORT](#so_reuseport)
  - [Overview](#overview)
  - [Usage](#usage)

## Overview

`SO_REUSEPORT` is a TCP/IP socket option that **allows multiple independent sockets to bind to the same IP address and port number** simultaneously.

This is because, in traditional socket programming, even when `SO_REUSEADDR` was set, its primary purpose was the reuse of sockets in the **TIME\_WAIT** state, and it was generally not possible for multiple processes to share the listening port simultaneously.

## Usage

Applying the `SO_REUSEPORT` option to the listening socket is what enables multiple different server processes (or threads) to bind to the same IP address and port and wait for connections.
