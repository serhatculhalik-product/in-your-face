#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
app_path="${1:-${repository_directory}/.build/app/Meeting Incoming.app}"
binary_path="${app_path}/Contents/MacOS/InYourFace"
candidate_pid=""
pid=""

cleanup() {
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [[ ! -x "${binary_path}" ]]; then
    echo "FAIL: app executable is missing at ${binary_path}"
    exit 1
fi

if pgrep -x InYourFace >/dev/null; then
    echo "FAIL: quit existing InYourFace processes before running this smoke test"
    exit 1
fi

/usr/bin/open -n "${app_path}"

for _ in {1..40}; do
    candidate_pid="$(pgrep -x InYourFace | tail -n 1 || true)"
    [[ -n "${candidate_pid}" ]] && break
    sleep 0.05
done

if [[ -z "${candidate_pid}" ]]; then
    echo "FAIL: launch produced no InYourFace process"
    exit 1
fi

actual_path="$(ps -p "${candidate_pid}" -o command=)"
if [[ "${actual_path}" != "${binary_path}" ]]; then
    echo "FAIL: launch opened a different artifact: ${actual_path}"
    exit 1
fi
pid="${candidate_pid}"

for _ in {1..100}; do
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "FAIL: exact app process ${pid} exited during the five-second launch window"
        exit 1
    fi
    sleep 0.05
done

echo "PASS: exact app process ${pid} remained alive for five seconds"
