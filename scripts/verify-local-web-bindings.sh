#!/usr/bin/env bash
set -euo pipefail

EXPECTED_PORTS=(8081 9119 8384 8888 9999 3002 13378)
WAIT_SECONDS="${WAIT_SECONDS:-60}"
START_TS="$(date +%s)"

tailscale_ipv4="$(tailscale ip -4 2>/dev/null || true)"
tailscale_ipv6="$(tailscale ip -6 2>/dev/null || true)"

is_allowed_listener() {
  local port="$1"
  local listener="$2"
  if [[ "${listener}" == "127.0.0.1:${port}" ]]; then
    return 0
  fi

  if [[ "${port}" == "13378" ]]; then
    if [[ -n "${tailscale_ipv4}" && "${listener}" == "${tailscale_ipv4}:${port}" ]]; then
      return 0
    fi
    if [[ -n "${tailscale_ipv6}" && "${listener}" == "[${tailscale_ipv6}]:${port}" ]]; then
      return 0
    fi
  fi

  return 1
}

while true; do
  missing=()
  bad_bindings=()

  for port in "${EXPECTED_PORTS[@]}"; do
    listeners="$(ss -ltnH "( sport = :${port} )" | awk '{print $4}')"
    if [[ -z "${listeners}" ]]; then
      missing+=("${port}")
      continue
    fi

    while IFS= read -r listener; do
      [[ -z "${listener}" ]] && continue
      if ! is_allowed_listener "${port}" "${listener}"; then
        bad_bindings+=("${port}:${listener}")
      fi
    done <<< "${listeners}"
  done

  if (( ${#missing[@]} == 0 && ${#bad_bindings[@]} == 0 )); then
    echo "✓ Verified localhost-only web bindings: ${EXPECTED_PORTS[*]}"
    exit 0
  fi

  now="$(date +%s)"
  if (( now - START_TS >= WAIT_SECONDS )); then
    if (( ${#missing[@]} > 0 )); then
      echo "Missing listener(s) after ${WAIT_SECONDS}s: ${missing[*]}" >&2
    fi
    if (( ${#bad_bindings[@]} > 0 )); then
      echo "Non-localhost listener(s) after ${WAIT_SECONDS}s: ${bad_bindings[*]}" >&2
    fi
    exit 1
  fi

  sleep 2
done
