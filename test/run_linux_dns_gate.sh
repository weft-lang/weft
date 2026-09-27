#!/bin/sh
# Hermetic Linux/AArch64 DNS resolver gate.
#
# Builds tools/linux_aarch64_dns_transport_product.weft as a static Linux
# executable and runs it in Docker on a private internal network against
# test/fixtures/linux_dns/stub_nameserver.py. The first configured nameserver
# has no host behind it, so kernel receive deadlines and server failover run
# for real. The product must return 0 against the stub and fail closed with 71
# under an empty or malformed /etc/resolv.conf. strace pins the socket
# addresses the resolver connects to and the framed TCP fallback.
#
# Requires Docker with an arm64 engine. Set WEFT to choose the compiler.
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
weft_bin=${WEFT:-"$project_root/weft"}
image=${WEFT_DNS_GATE_IMAGE:-weft-dns-gate:bookworm}
subnet_prefix=172.29.53
stub_address=$subnet_prefix.53
dead_address=$subnet_prefix.9

case "$weft_bin" in
  /*) ;;
  *) weft_bin=$(CDPATH= cd -- "$(dirname "$weft_bin")" && pwd -P)/$(basename "$weft_bin") ;;
esac

command -v docker >/dev/null || { echo "linux DNS gate: docker is required" >&2; exit 2; }

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf '%s\n' \
    'FROM debian:bookworm' \
    'RUN apt-get update && apt-get install -y --no-install-recommends python3-minimal strace && rm -rf /var/lib/apt/lists/*' \
    | docker build --platform linux/arm64 -t "$image" - >/dev/null
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-linux-dns.XXXXXX")
network=weft-dns-gate-$$
stub=weft-dns-stub-$$
cleanup() {
  docker rm -f "$stub" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

(cd "$project_root" && "$weft_bin" build tools/linux_aarch64_dns_transport_product.weft \
  -o "$work/product" --target linux-aarch64)
cp "$project_root/test/fixtures/linux_dns/stub_nameserver.py" "$work/stub_nameserver.py"

docker network create --internal --subnet "$subnet_prefix.0/24" "$network" >/dev/null
docker run -d --name "$stub" --network "$network" --ip "$stub_address" \
  -v "$work/stub_nameserver.py:/stub_nameserver.py:ro" "$image" \
  python3 /stub_nameserver.py "$stub_address" >/dev/null
tries=0
until docker logs "$stub" 2>&1 | grep -q "stub nameserver ready"; do
  tries=$((tries + 1))
  [ "$tries" -le 50 ] || { echo "linux DNS gate: stub nameserver did not start" >&2; exit 1; }
  sleep 0.2
done

printf 'nameserver %s\nnameserver %s\noptions timeout:1 attempts:1\n' \
  "$dead_address" "$stub_address" > "$work/resolv.good"
: > "$work/resolv.empty"
printf 'nameserver\nnameserver not-an-address\n' > "$work/resolv.malformed"

run_product() {
  set +e
  docker run --rm --network "$network" \
    -v "$work/product:/product:ro" -v "$work/$1:/etc/resolv.conf:ro" -v "$work:/work" \
    "$image" sh -c "$2" >"$work/$1.out" 2>&1
  status=$?
  set -e
}

failed=0
expect_status() {
  if [ "$status" -eq "$2" ]; then
    echo "  ok $1"
  else
    echo "  fail $1: exit $status, expected $2"
    sed 's/^/    /' "$work/$3.out"
    failed=1
  fi
}

run_product resolv.good "strace -f -qq -o /work/trace -e trace=socket,connect /product"
expect_status "linux_dns_transport_matrix_passes_against_the_stub" 0 resolv.good
run_product resolv.empty /product
expect_status "linux_dns_transport_fails_closed_without_nameservers" 71 resolv.empty
run_product resolv.malformed /product
expect_status "linux_dns_transport_fails_closed_on_malformed_nameservers" 71 resolv.malformed

expect_trace() {
  if grep -q -- "$2" "$work/trace"; then echo "  ok $1"; else
    echo "  fail $1: trace lacks $2"
    failed=1
  fi
}
if grep -m 1 "connect(" "$work/trace" | grep -q "sin_addr=inet_addr(\"$dead_address\")"; then
  echo "  ok linux_dns_connects_to_the_dead_nameserver_first"
else
  echo "  fail linux_dns_connects_to_the_dead_nameserver_first"
  grep -m 1 "connect(" "$work/trace" | sed 's/^/    /'
  failed=1
fi
expect_trace "linux_dns_fails_over_to_the_stub" \
  "sin_port=htons(53), sin_addr=inet_addr(\"$stub_address\")"
expect_trace "linux_dns_opens_a_datagram_socket" "SOCK_DGRAM|SOCK_CLOEXEC"
expect_trace "linux_dns_falls_back_to_a_stream_socket" "SOCK_STREAM|SOCK_CLOEXEC"
if grep -q "connect(" "$work/trace" && ! grep "connect(" "$work/trace" | grep -qv "sin_port=htons(53)"; then
  echo "  ok linux_dns_connects_only_to_port_53"
else
  echo "  fail linux_dns_connects_only_to_port_53"
  grep "connect(" "$work/trace" | sed 's/^/    /'
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  echo "linux DNS gate failed" >&2
  exit 1
fi
echo "linux DNS gate passed"
