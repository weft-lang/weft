#!/usr/bin/env python3
"""Hermetic authoritative nameserver for the Linux DNS transport gate.

Serves the fixed zone that tools/linux_aarch64_dns_transport_product.weft
expects, over UDP and two-byte-framed TCP on port 53:

  truncated.weft.test  A     UDP answers TC=1 with no records; TCP carries
                             198.51.100.7, so only the framed retry succeeds
  missing.weft.test    any   NXDOMAIN
  refused.weft.test    any   REFUSED
  nodata.weft.test     any   NOERROR with no records
  weft-dns.test        A     192.0.2.10
  weft-dns.test        AAAA  2001:db8::10

Every other question is answered NOERROR with no records. Each answer echoes
the query's transaction id and question section exactly.
"""
import socket
import struct
import sys
import threading

A_RECORDS = {"truncated.weft.test": "198.51.100.7", "weft-dns.test": "192.0.2.10"}
AAAA_RECORDS = {"weft-dns.test": "2001:db8::10"}
NXDOMAIN = {"missing.weft.test"}
REFUSED = {"refused.weft.test"}
TRUNCATED_OVER_UDP = {"truncated.weft.test"}
TYPE_A = 1
TYPE_AAAA = 28


def question(message):
    """Return (id, flags, lowercase name, qtype, raw question bytes)."""
    ident, flags = struct.unpack(">HH", message[:4])
    position = 12
    labels = []
    while message[position] != 0:
        length = message[position]
        labels.append(message[position + 1:position + 1 + length].decode("ascii").lower())
        position += 1 + length
    position += 1
    qtype = struct.unpack(">H", message[position:position + 2])[0]
    return ident, flags, ".".join(labels), qtype, message[12:position + 4]


def answer(message, transport):
    ident, flags, name, qtype, raw_question = question(message)
    rcode, truncated, records = 0, False, []
    if name in REFUSED:
        rcode = 5
    elif name in NXDOMAIN:
        rcode = 3
    elif transport == "udp" and name in TRUNCATED_OVER_UDP:
        truncated = True
    elif qtype == TYPE_A and name in A_RECORDS:
        records.append((TYPE_A, socket.inet_pton(socket.AF_INET, A_RECORDS[name])))
    elif qtype == TYPE_AAAA and name in AAAA_RECORDS:
        records.append((TYPE_AAAA, socket.inet_pton(socket.AF_INET6, AAAA_RECORDS[name])))
    response_flags = 0x8000 | 0x0400 | (flags & 0x0100) | rcode
    if truncated:
        response_flags |= 0x0200
    reply = struct.pack(">HHHHHH", ident, response_flags, 1, len(records), 0, 0) + raw_question
    for rtype, rdata in records:
        reply += b"\xc0\x0c" + struct.pack(">HHIH", rtype, 1, 60, len(rdata)) + rdata
    return reply


def serve_udp(sock):
    while True:
        data, peer = sock.recvfrom(4096)
        sock.sendto(answer(data, "udp"), peer)


def read_exact(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def serve_tcp_connection(connection):
    with connection:
        header = read_exact(connection, 2)
        if header is not None:
            query = read_exact(connection, struct.unpack(">H", header)[0])
            if query is not None:
                reply = answer(query, "tcp")
                connection.sendall(struct.pack(">H", len(reply)) + reply)


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0"
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind((host, 53))
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind((host, 53))
    tcp.listen(16)
    threading.Thread(target=serve_udp, args=(udp,), daemon=True).start()
    print("stub nameserver ready", flush=True)
    while True:
        connection, _ = tcp.accept()
        threading.Thread(target=serve_tcp_connection, args=(connection,), daemon=True).start()


if __name__ == "__main__":
    main()
