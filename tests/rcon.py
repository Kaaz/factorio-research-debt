"""Minimal Source-RCON client for Factorio (no third-party dependencies)."""
import socket
import struct
import time

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0
SERVERDATA_AUTH_RESPONSE = 2


class RconError(Exception):
    pass


class Rcon:
    def __init__(self, host, port, password, timeout=10.0):
        self.host, self.port, self.password, self.timeout = host, port, password, timeout
        self.sock = None
        self._id = 0

    def connect(self):
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self._send(SERVERDATA_AUTH, self.password)
        # Factorio answers with a single AUTH_RESPONSE packet (id == request id on success, -1 on failure)
        pid, ptype, _ = self._recv()
        if ptype == SERVERDATA_RESPONSE_VALUE:  # some servers send an empty value packet first
            pid, ptype, _ = self._recv()
        if pid == -1:
            raise RconError("RCON authentication failed")
        return self

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def command(self, cmd):
        req_id = self._send(SERVERDATA_EXECCOMMAND, cmd)
        pid, ptype, body = self._recv()
        if pid != req_id:
            raise RconError(f"unexpected packet id {pid} (expected {req_id})")
        return body

    # -- wire format ---------------------------------------------------------
    def _send(self, ptype, body):
        self._id += 1
        payload = struct.pack("<ii", self._id, ptype) + body.encode("utf-8") + b"\x00\x00"
        self.sock.sendall(struct.pack("<i", len(payload)) + payload)
        return self._id

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise RconError("connection closed")
            buf += chunk
        return buf

    def _recv(self):
        (size,) = struct.unpack("<i", self._recv_exact(4))
        data = self._recv_exact(size)
        pid, ptype = struct.unpack("<ii", data[:8])
        body = data[8:-2].decode("utf-8", errors="replace")
        return pid, ptype, body


def wait_for_rcon(host, port, password, timeout=120.0, is_alive=None):
    """Poll until the server accepts RCON connections."""
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        if is_alive is not None and not is_alive():
            raise RconError("server process exited before RCON became available")
        try:
            return Rcon(host, port, password).connect()
        except (OSError, RconError) as e:
            last_err = e
            time.sleep(1.0)
    raise RconError(f"RCON not available after {timeout}s: {last_err}")
