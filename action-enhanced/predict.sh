#!/usr/bin/env bash
# Runs the cost prediction image and adds its PREDICTION_TABLE output to the
# calling step. Inputs come from the environment: PREDICTION_PATH (relative to
# the workspace), LOG_LEVEL and, optionally, KUBECOST_API_PATH.
#
# The image calls /clusterInfo and /getConfigs, which Kubecost v3 no longer
# serves. With KUBECOST_API_PATH set, the image talks to Kubecost through
# kubecost-v3-proxy.py on 127.0.0.1, which translates those two calls on v3
# and passes everything else through. Without it, the image runs offline.
set -euo pipefail

# The image of kubecost/cost-prediction-action v0.1.1, pinned by digest.
IMAGE=gcr.io/kubecost1/cost-prediction-action@sha256:14dade8604cf9a1beaacb0cfe2b156237da1a2cf499bb94a68ab16ec7d155d9d
PROXY_PORT=19090

out=$(mktemp -d)
: > "$out/output"
proxy_pid=''
cleanup() {
  if [[ -n "$proxy_pid" ]]; then kill "$proxy_pid" 2>/dev/null || true; fi
  rm -rf "$out"
}
trap cleanup EXIT

network=none
api=''
if [[ -n "${KUBECOST_API_PATH:-}" ]]; then
  if [[ ! "$KUBECOST_API_PATH" =~ ^(https?://[^/?#]+)(/[^?#]*)?$ ]]; then
    echo '::error::kubecost_api_path must be an http(s) URL, e.g. https://kubecost.example.com/model'
    exit 1
  fi
  origin=${BASH_REMATCH[1]} prefix=${BASH_REMATCH[2]%/}
  KUBECOST_UPSTREAM=$origin PROXY_HOST=127.0.0.1 PROXY_PORT=$PROXY_PORT \
    python3 "$GITHUB_ACTION_PATH/kubecost-v3-proxy.py" &
  proxy_pid=$!
  for _ in $(seq 1 50); do
    if (: > "/dev/tcp/127.0.0.1/$PROXY_PORT") 2>/dev/null; then break; fi
    sleep 0.1
  done
  network=host
  api="http://127.0.0.1:${PROXY_PORT}${prefix}"
fi

docker run --rm --network "$network" \
  -v "$GITHUB_WORKSPACE:/github/workspace:ro" -w /github/workspace \
  -v "$out:/github/file_commands" \
  -e PREDICTION_PATH -e LOG_LEVEL -e KUBECOST_API_PATH="$api" \
  -e GITHUB_OUTPUT=/github/file_commands/output \
  "$IMAGE"

cat "$out/output" >> "$GITHUB_OUTPUT"
