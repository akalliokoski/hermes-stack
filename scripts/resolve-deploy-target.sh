#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/resolve-deploy-target.sh [candidate ...]

Resolve a trusted, reachable VPS SSH target for deployment.

Required environment:
  DEPLOY_SSH_USER              SSH user for the VPS
  DEPLOY_SSH_KEY               Path to private key
  DEPLOY_KNOWN_HOSTS           Path to pinned known_hosts file

Optional environment:
  EXPECTED_REMOTE_HOSTNAME     Expected `hostname -s` value, default: vps
  CONNECT_TIMEOUT              SSH connect/banner timeout seconds, default: 10
  GITHUB_ENV                   When set, writes DEPLOY_TARGET=<target>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEPLOY_SSH_USER="${DEPLOY_SSH_USER:-}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
DEPLOY_KNOWN_HOSTS="${DEPLOY_KNOWN_HOSTS:-}"
EXPECTED_REMOTE_HOSTNAME="${EXPECTED_REMOTE_HOSTNAME:-vps}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"

[[ -n "${DEPLOY_SSH_USER}" ]] || { echo "DEPLOY_SSH_USER is required" >&2; exit 2; }
[[ -n "${DEPLOY_SSH_KEY}" ]] || { echo "DEPLOY_SSH_KEY is required" >&2; exit 2; }
[[ -n "${DEPLOY_KNOWN_HOSTS}" ]] || { echo "DEPLOY_KNOWN_HOSTS is required" >&2; exit 2; }
[[ -f "${DEPLOY_SSH_KEY}" ]] || { echo "SSH key not found: ${DEPLOY_SSH_KEY}" >&2; exit 2; }
[[ -s "${DEPLOY_KNOWN_HOSTS}" ]] || { echo "known_hosts is empty or missing: ${DEPLOY_KNOWN_HOSTS}" >&2; exit 2; }

validate_target() {
  local candidate="$1"
  [[ "${candidate}" =~ ^[A-Za-z0-9.-]+$ ]]
}

ssh_common_options=(
  -i "${DEPLOY_SSH_KEY}"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${DEPLOY_KNOWN_HOSTS}"
  -o ConnectTimeout="${CONNECT_TIMEOUT}"
  -o ConnectionAttempts=1
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=1
)

diagnose_candidate() {
  local candidate="$1"
  local log="$2"

  if grep -Fq "Connection timed out during banner exchange" "${log}"; then
    echo "Candidate ${candidate}: TCP/22 accepted, but SSH banner timed out. sshd, host firewall, or host load may be unhealthy." >&2
  elif grep -Fq "Connection timed out" "${log}" || grep -Fq "Operation timed out" "${log}"; then
    echo "Candidate ${candidate}: TCP connection timed out before SSH could start." >&2
  elif grep -Fq "Host key verification failed" "${log}"; then
    echo "Candidate ${candidate}: host key verification failed. Refresh pinned known_hosts only after verifying the VPS identity." >&2
  elif grep -Fq "Permission denied" "${log}"; then
    echo "Candidate ${candidate}: SSH authentication failed for ${DEPLOY_SSH_USER}." >&2
  elif grep -Fq "tailnet policy does not permit" "${log}"; then
    echo "Candidate ${candidate}: Tailscale SSH is reachable, but tailnet ACLs do not permit this SSH login." >&2
  elif grep -Fq "Could not resolve hostname" "${log}"; then
    echo "Candidate ${candidate}: hostname did not resolve." >&2
  else
    echo "Candidate ${candidate}: SSH probe failed:" >&2
    sed 's/^/  /' "${log}" >&2
  fi
}

seen_candidates=""
for candidate in "$@"; do
  [[ -n "${candidate}" ]] || continue

  if [[ -n "${seen_candidates}" ]] && printf '%s\n' "${seen_candidates}" | grep -Fx -- "${candidate}" >/dev/null; then
    continue
  fi
  seen_candidates="${seen_candidates}${candidate}"$'\n'

  if ! validate_target "${candidate}"; then
    echo "Skipping invalid deploy target candidate: ${candidate}" >&2
    continue
  fi

  if ! ssh-keygen -F "${candidate}" -f "${DEPLOY_KNOWN_HOSTS}" >/dev/null; then
    echo "Skipping deploy target candidate without pinned known_hosts entry: ${candidate}" >&2
    continue
  fi

  echo "Trying deploy target: ${candidate}" >&2
  probe_log="$(mktemp)"
  remote_hostname=""
  if remote_hostname="$(ssh "${ssh_common_options[@]}" "${DEPLOY_SSH_USER}@${candidate}" "hostname -s" 2>"${probe_log}")"; then
    if [[ "${remote_hostname}" == "${EXPECTED_REMOTE_HOSTNAME}" ]]; then
      if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "DEPLOY_TARGET=${candidate}" >> "${GITHUB_ENV}"
      fi
      echo "${candidate}"
      rm -f "${probe_log}"
      exit 0
    fi

    echo "Candidate ${candidate} resolved to unexpected host '${remote_hostname}'" >&2
  else
    diagnose_candidate "${candidate}" "${probe_log}"
  fi

  rm -f "${probe_log}"
done

cat >&2 <<EOF
Unable to resolve a trusted deploy target.

Recovery note: if every candidate reports banner timeout or TCP timeout, GitHub
Actions cannot apply repo scripts yet because the deploy path itself depends on
SSH. Use the provider console/rescue shell to restore sshd or networking, then
rerun the workflow.
EOF
exit 1
