# Networking in Weft

Weft splits network authority instead of exposing one ambient `Net` capability.
`DnsResolve` resolves a canonical name, `TcpConnect` opens outbound streams,
`TcpListen` opens inbound listeners, and the established-resource effects
operate only on resources already owned by the caller. Possessing a
`TcpStream` therefore does not grant authority to connect elsewhere.

Addresses are typed values. Numeric candidates are pure and do not need DNS
authority:

```weft run
use stdlib/dns.{DnsAnyFamily, dns_numeric_candidates}
use stdlib/net_address.{IpV4, SocketAddress, ipv4_address}
use stdlib/result.{Err, Ok}
use stdlib/vector.{vector_len}
use stdlib/vector/handles.{Vector}

fn main() -> i64 {
  match dns_numeric_candidates(
    IpV4(ipv4_address(127, 0, 0, 1)),
    443,
    DnsAnyFamily
  ) {
    Ok(candidates) -> if vector_len<SocketAddress>(candidates) == 1 { 0 } else { 1 }
    Err(error) -> 2
  }
}
```

## Narrow authority with value policies

Static effects state the maximum authority a function may use. A policy handler
can narrow that authority to exact values, but it cannot grant an effect the
caller lacks. DNS policies snapshot canonical `(DomainName, port)` targets;
outbound and inbound TCP policies use distinct exact endpoint allowlists.
Allowed requests delegate to the enclosing resolver/connector/listener, while
denied requests return `DnsPolicyDenied` or `TcpPolicyDenied` without reaching
the platform handler.

```weft check
use stdlib/dns.{DnsAnyFamily, DnsError, DnsPolicyAllowOnly, DnsPolicyTarget, DnsResolve, dns_resolve, dns_with_policy}
use stdlib/idna.{DomainName}
use stdlib/net_address.{SocketAddress}
use stdlib/result.{Result}
use stdlib/tcp.{TcpConnect, TcpConnectPolicyAllowOnly, TcpConnectOptions, TcpError, TcpListen, TcpListenOptions, TcpListenPolicyAllowOnly, TcpListener, TcpStream, tcp_connect, tcp_connect_with_policy, tcp_listen, tcp_listen_with_policy}
use stdlib/vector.{vector_new, vector_push}
use stdlib/vector/handles.{Vector}

fn resolve_allowed(host: DomainName) -[DnsResolve]> Result<Vector<SocketAddress>, DnsError> {
  let targets = vector_new<DnsPolicyTarget>()
  vector_push<DnsPolicyTarget>(targets, DnsPolicyTarget(host, 443))
  dns_with_policy(
    DnsPolicyAllowOnly(targets),
    () => dns_resolve(host, 443, DnsAnyFamily)
  )
}

fn connect_allowed(
  address: SocketAddress,
  options: TcpConnectOptions
) -[TcpConnect]> Result<owned TcpStream, TcpError> {
  let addresses = vector_new<SocketAddress>()
  vector_push<SocketAddress>(addresses, address)
  tcp_connect_with_policy(
    TcpConnectPolicyAllowOnly(addresses),
    () => tcp_connect(address, options)
  )
}

fn listen_allowed(
  address: SocketAddress,
  options: TcpListenOptions
) -[TcpListen]> Result<owned TcpListener, TcpError> {
  let addresses = vector_new<SocketAddress>()
  vector_push<SocketAddress>(addresses, address)
  tcp_listen_with_policy(
    TcpListenPolicyAllowOnly(addresses),
    () => tcp_listen(address, options)
  )
}

fn main() -> i64 { 0 }
```

The policy functions deliberately retain `DnsResolve`, `TcpConnect`, or
`TcpListen` in their output effect set because allowed work still requires an
enclosing interpretation. Deterministic DNS and application handlers can sit
outside the same policy wrapper in tests. The production handler uses the
platform resolver on macOS and Weft's bounded static DNS resolver on Linux,
without changing application source. `weft doc stdlib/dns.weft` and
`weft doc stdlib/tcp.weft` render these checker-owned authority, ownership,
and residual-effect facts.

## Resource and readiness semantics

`TcpStream` and `TcpListener` are opaque `owned` resources. Explicit close
consumes the owner even if the platform reports an error; ordinary return,
early return, and effect abort run the same exactly-once `Drop` path. Reads and
writes use borrowed byte slices and report partial progress, EOF, interruption,
would-block, timeout, reset, and platform failures as typed values.

The runtime uses package-internal one-shot readiness: kqueue on macOS and epoll
on Linux. Registrations carry resource identity, interest, generation, and a
process-lifetime poller epoch, so descriptor or mapping reuse cannot make stale
readiness current. This is scheduler mechanism, not a second public async API:
the structured `Spawn` handler suspends ordinary effectful functions over the
same TCP surface, with typed cancellation, deadlines, shutdown signals, and
bounded channels.

## HTTPS, HTTP, and web streams

The alpha web floor is validating TLS 1.2 plus hardened HTTP/1.1. The current
TLS backend is the content-pinned Mbed TLS 3.6.7 static archive on both targets;
ordinary SDK users do not install OpenSSL, Mbed TLS, a C toolchain, or a host
linker. Client setup requires secure randomness, time, trust roots, SNI, and
canonical hostname or IP verification. Production verification has no
permissive fallback. TLS 1.3 is not in the current alpha protocol floor.

URLs consume the same Unicode 17 UTS #46 `DomainName` identity as DNS and
certificate verification. Unicode and A-label spellings therefore converge on
one canonical lowercase ASCII host, while URL path/query/fragment codecs retain
their exact UTF-8 and percent-encoding rules. No backend performs an
independent locale conversion or hostname normalization.

The public HTTP layers separate outbound `HttpClient` from inbound
`HttpServer` authority. Pure `stdlib/http` values and parsers share one
framing truth with production and replay handlers; `stdlib/http/endpoint`
owns client/server transport, pooling, redirects, upgrades, and connection
reuse. `stdlib/http/json`, `stdlib/sse/stream`, and
`stdlib/websocket/stream` join bounded semantic adapters to an exact owned
body or upgraded connection. Their transitions return the owner on completion,
retry, cancellation, and typed failure, so streaming does not hide whole-body
buffering or resource loss.

Every layer has explicit limits. HTTP bounds start lines, fields, headers,
bodies, trailers, and connection reuse; JSON callers choose a whole-document
bound; SSE defaults to 16 KiB per unfinished line and 1 MiB per event;
WebSocket defaults to 16 MiB per frame and 64 MiB per reassembled message while
payload delivery remains fragment-bounded. Applications can select stricter
limits and must match the typed rejection variants.

The checked [HTTPS JSON/SSE/WebSocket example](../examples/https_json_streams.weft)
runs a local validating client and server through JSON exchange, chunked SSE,
WebSocket upgrade, fragmented Unicode text, ping/pong, trailers, and the close
handshake. Deterministic replay and fault handlers exercise the same public
semantic transitions without network authority.

HTTP/2, HTTP/3, QUIC, WebTransport, gRPC, proxy auto-discovery, browser-complete
cookies/cache, and compression breadth are not part of the first alpha.
