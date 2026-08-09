#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/site/install.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

stub_bin="$test_root/bin"
test_home="$test_root/home"
test_tmp="$test_root/tmp"
work_dir="$test_root/work"
curl_log="$test_root/curl.log"
ditto_log="$test_root/ditto.log"
danger_log="$test_root/danger.log"
mkdir -p "$stub_bin" "$test_home" "$test_tmp" "$work_dir"
: >"$curl_log"
: >"$ditto_log"
: >"$danger_log"

write_checksum() {
  local archive="$1"
  shasum -a 256 "$archive" | awk '{print $1}' >"$archive.sha256"
}

cat >"$stub_bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

url=""
output=""
while (( $# > 0 )); do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$url" >>"$CMDCMD_TEST_CURL_LOG"
if [[ "${CMDCMD_TEST_CURL_MODE:-copy}" == "fail" ]]; then
  exit 91
fi
if [[ -z "$output" || -z "$url" ]]; then
  exit 92
fi
if [[ "$url" == *.sha256 ]]; then
  cp "$CMDCMD_TEST_REMOTE_ARCHIVE.sha256" "$output"
else
  cp "$CMDCMD_TEST_REMOTE_ARCHIVE" "$output"
fi
STUB

cat >"$stub_bin/ditto" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$CMDCMD_TEST_DITTO_LOG"
if [[ "${1:-}" != "-x" || "${2:-}" != "-k" || $# -ne 4 ]]; then
  exit 94
fi
if ! cmp -s "$3" "$CMDCMD_TEST_EXPECTED_ARCHIVE"; then
  exit 95
fi

# Stop the installer immediately after archive selection and checksum
# verification, before it can inspect or mutate an installed relay.
exit 73
STUB

for command_name in launchctl pkill pgrep codesign; do
  cat >"$stub_bin/$command_name" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CMDCMD_TEST_DANGER_LOG"
exit 96
STUB
done
chmod +x "$stub_bin"/*

run_installer_until_extraction() {
  local expected_archive="$1"
  local remote_archive="$2"
  local curl_mode="$3"
  shift 3

  set +e
  (
    cd "$work_dir"
    env \
      HOME="$test_home" \
      TMPDIR="$test_tmp" \
      PATH="$stub_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      CMDCMD_RELAY_ARCHIVE_NAME="fixture.zip" \
      CMDCMD_RELAY_RELEASE_URL="https://downloads.example.invalid/cmdcmd" \
      CMDCMD_TEST_CURL_LOG="$curl_log" \
      CMDCMD_TEST_CURL_MODE="$curl_mode" \
      CMDCMD_TEST_REMOTE_ARCHIVE="$remote_archive" \
      CMDCMD_TEST_DITTO_LOG="$ditto_log" \
      CMDCMD_TEST_EXPECTED_ARCHIVE="$expected_archive" \
      CMDCMD_TEST_DANGER_LOG="$danger_log" \
      "$@" \
      bash -s <"$installer"
  )
  local status=$?
  set -e

  if [[ $status -ne 73 ]]; then
    echo "Installer did not stop at the extraction stub (status $status)." >&2
    return 1
  fi
}

ambient_archive="$work_dir/dist/cmdcmd-relay/CmdCmdRelay-macOS.zip"
remote_archive="$test_root/remote.zip"
mkdir -p "$(dirname "$ambient_archive")"
printf 'ambient archive must not be selected\n' >"$ambient_archive"
write_checksum "$ambient_archive"
printf 'remote release archive\n' >"$remote_archive"
write_checksum "$remote_archive"

run_installer_until_extraction "$remote_archive" "$remote_archive" copy

release_url="https://downloads.example.invalid/cmdcmd"
if ! grep -Fxq "$release_url/fixture.zip" "$curl_log"; then
  echo "Public installer did not request the remote archive." >&2
  exit 1
fi
if ! grep -Fxq "$release_url/fixture.zip.sha256" "$curl_log"; then
  echo "Public installer did not request the remote checksum." >&2
  exit 1
fi
if [[ $(wc -l <"$curl_log") -ne 2 ]]; then
  echo "Public installer made unexpected curl calls." >&2
  exit 1
fi

: >"$curl_log"
local_archive="$test_root/operator-selected.zip"
printf 'explicit local archive\n' >"$local_archive"
write_checksum "$local_archive"

run_installer_until_extraction \
  "$local_archive" \
  "$remote_archive" \
  fail \
  CMDCMD_RELAY_LOCAL_ARCHIVE="$local_archive"

if [[ -s "$curl_log" ]]; then
  echo "Explicit local archive mode unexpectedly called curl." >&2
  exit 1
fi
if [[ -s "$danger_log" ]]; then
  echo "Installer reached a process, launchd, or signing command." >&2
  cat "$danger_log" >&2
  exit 1
fi
if [[ $(wc -l <"$ditto_log") -ne 2 ]]; then
  echo "Expected exactly one extraction attempt per installer case." >&2
  exit 1
fi

echo "Installer archive source tests passed."
