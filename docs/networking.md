# Networking in Weft

Weft splits network authority instead of exposing one ambient `Net` capability.
`DnsResolve` resolves a canonical name, `TcpConnect` opens outbound streams,
`TcpListen` opens inbound listeners, and the established-resource effects
operate only on resources already owned by the caller. Possessing a
`TcpStream` therefore does not grant authority to connect elsewhere.

Addresses are typed values. Numeric candidates are pure and do not need DNS
authority:

```weft run
use stdlib/dns as dns
use stdlib/dns.{DnsAnyFamily}
use stdlib/net_address as net
use stdlib/net_address.{IpV4}
use stdlib/result.{Err, Ok}

fn main() -> i64 {
  match dns.numeric_candidates(
    IpV4(net.ipv4(127, 0, 0, 1)),
    443,
    DnsAnyFamily
  ) {
    Ok(candidates) -> if candidates.len() == 1 { 0 } else { 1 }
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
use stdlib/dns as dns
use stdlib/dns.{DnsAnyFamily, DnsError, DnsResolve}
use stdlib/dns/policy as dns_policy
use stdlib/dns/policy.{Target}
use stdlib/idna.{DomainName}
use stdlib/net_address.{SocketAddress}
use stdlib/result.{Result}
use stdlib/tcp as tcp
use stdlib/tcp.{TcpConnect, TcpConnectOptions, TcpError, TcpListen, TcpListenOptions, TcpListener, TcpStream}
use stdlib/tcp/connect_policy as connect_policy
use stdlib/tcp/listen_policy as listen_policy
use stdlib/vector as vector
use stdlib/vector.{Vector}

fn resolve_allowed(host: DomainName) -[DnsResolve]> Result<Vector<SocketAddress>, DnsError> {
  let mut targets = vector.new<Target>()
  targets.push(dns_policy.Target(host, 443))
  with dns_policy(dns_policy.allow_only(targets)) {
    dns.resolve(host, 443, DnsAnyFamily)
  }
}

fn connect_allowed(
  address: SocketAddress,
  options: TcpConnectOptions
) -[TcpConnect]> Result<owned TcpStream, TcpError> {
  let mut addresses = vector.new<SocketAddress>()
  addresses.push(address)
  with connect_policy(connect_policy.allow_only(addresses)) {
    tcp.connect(address, options)
  }
}

fn listen_allowed(
  address: SocketAddress,
  options: TcpListenOptions
) -[TcpListen]> Result<owned TcpListener, TcpError> {
  let mut addresses = vector.new<SocketAddress>()
  addresses.push(address)
  with listen_policy(listen_policy.allow_only(addresses)) {
    tcp.listen(address, options)
  }
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
the structured task handler suspends ordinary effectful functions over the
same TCP surface. Its related capabilities live together under
`stdlib/task/`: `task/cancellation` provides cooperative cancellation and
deadlines, `task/shutdown` names portable shutdown signals, and `task/channel`
provides bounded typed channels with backpressure.

See [Concurrency in Weft](concurrency.md) for the distinction between
deterministic `Par` work and effectful `TaskScope` scheduling, including the
shared structured-lifetime rules and handler choices.

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
