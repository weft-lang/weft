# test/linked/budget.sh -- declared compile-phase runaway stops.
#
# A linked program that legitimately compiles a large slice of the compiler
# declares its compile stop with `-- Compile budget: N s` (1..3600) on its own
# line. The declaration can only extend the host stop, never shorten it, and a
# malformed declaration is an error rather than silently ignored.

# Print the compile stop in seconds for program $1 under host stop $2. Returns
# nonzero, printing nothing, for a malformed declaration.
linked_compile_budget() {
  local file="$1"
  local host="$2"
  local line
  local declared
  line=$(grep -m1 '^-- Compile budget:' "$file" || true)
  if [ -z "$line" ]; then
    echo "$host"
    return 0
  fi
  declared=$(printf '%s\n' "$line" | sed -nE 's/^-- Compile budget: ([0-9]{1,4}) s$/\1/p')
  if ! [[ "$declared" =~ ^[0-9]+$ ]] || [ "$declared" -lt 1 ] || [ "$declared" -gt 3600 ]; then
    return 1
  fi
  if [ "$declared" -gt "$host" ]; then echo "$declared"; else echo "$host"; fi
}
