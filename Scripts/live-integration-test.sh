#!/bin/bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly ARTIFACT_ROOT="${AISS_ARTIFACT_DIR:-${PROJECT_ROOT}/.build/live-integration/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
readonly TEST_DOMAIN="io.github.qubyyang.awesome-ios-sim.live-integration"
readonly TEST_MARKER="live-$RANDOM-$$"

DEVICE_UDID=""
DEVICE_CREATED=0

log() {
    printf '[live-integration] %s\n' "$*"
}

fail() {
    printf '[live-integration] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

cleanup_device() {
    if [[ "$DEVICE_CREATED" -ne 1 || -z "$DEVICE_UDID" ]]; then
        return
    fi

    if [[ "${AISS_KEEP_DEVICE:-0}" == "1" ]]; then
        log "Keeping dedicated simulator ${DEVICE_UDID} because AISS_KEEP_DEVICE=1"
        return
    fi

    log "Deleting dedicated simulator ${DEVICE_UDID}"
    xcrun simctl shutdown "$DEVICE_UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$DEVICE_UDID"
    DEVICE_CREATED=0
}

trap cleanup_device EXIT INT TERM

require_command jq
require_command swift
require_command xcodebuild
require_command xcrun

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        fail "Set DEVELOPER_DIR to a full Xcode installation"
    fi
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    fail "DEVELOPER_DIR does not point to a usable full Xcode installation: ${DEVELOPER_DIR}"
fi

mkdir -p "$ARTIFACT_ROOT"
cd "$PROJECT_ROOT"

log "Artifacts: ${ARTIFACT_ROOT}"
xcodebuild -version | tee "$ARTIFACT_ROOT/xcode-version.txt"

log "Discovering an available iOS runtime and compatible iPhone device type"
xcrun simctl list runtimes --json > "$ARTIFACT_ROOT/runtimes.json"
RUNTIME_IDENTIFIER="${AISS_RUNTIME_IDENTIFIER:-$(
    jq -r '
        [.runtimes[] | select(.isAvailable == true and (.identifier | contains(".iOS-")))]
        | sort_by(.version | split(".") | map(tonumber))
        | last
        | .identifier // empty
    ' "$ARTIFACT_ROOT/runtimes.json"
)}"
[[ -n "$RUNTIME_IDENTIFIER" ]] || fail "No available iOS Simulator runtime was found"

DEVICE_TYPE_IDENTIFIER="${AISS_DEVICE_TYPE_IDENTIFIER:-$(
    jq -r --arg runtime "$RUNTIME_IDENTIFIER" '
        .runtimes[]
        | select(.identifier == $runtime)
        | [.supportedDeviceTypes[] | select(.productFamily == "iPhone")]
        | (map(select(.name == "iPhone 17 Pro")) + .)
        | first
        | .identifier // empty
    ' "$ARTIFACT_ROOT/runtimes.json"
)}"
[[ -n "$DEVICE_TYPE_IDENTIFIER" ]] || fail "No compatible iPhone device type was found for ${RUNTIME_IDENTIFIER}"

log "Building release CLI and MCP server"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
readonly CLI="${BIN_DIR}/ios-sim-state"
readonly MCP="${BIN_DIR}/ios-sim-state-mcp"
[[ -x "$CLI" ]] || fail "CLI executable was not produced at ${CLI}"
[[ -x "$MCP" ]] || fail "MCP executable was not produced at ${MCP}"

DEVICE_NAME="awesome-ios-sim-live-$RANDOM-$$"
log "Creating isolated simulator ${DEVICE_NAME}"
DEVICE_UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE_IDENTIFIER" "$RUNTIME_IDENTIFIER")"
[[ "$DEVICE_UDID" =~ ^[0-9A-Fa-f-]{36}$ ]] || fail "simctl returned an invalid UDID: ${DEVICE_UDID}"
DEVICE_CREATED=1
printf '%s\n' "$DEVICE_UDID" > "$ARTIFACT_ROOT/device-udid.txt"

log "Checking live CLI inventory and initial shutdown snapshot"
"$CLI" inventory --compact > "$ARTIFACT_ROOT/inventory.json"
jq -e --arg udid "$DEVICE_UDID" '.devices | any(.udid == $udid and .state == "Shutdown")' \
    "$ARTIFACT_ROOT/inventory.json" >/dev/null
"$CLI" snapshot --device "$DEVICE_UDID" --compact > "$ARTIFACT_ROOT/snapshot-before.json"
jq -e --arg udid "$DEVICE_UDID" '.device.udid == $udid and .state.power == "shutdown"' \
    "$ARTIFACT_ROOT/snapshot-before.json" >/dev/null

log "Checking live MCP inventory over stdio"
jq -cn '{
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
        name: "simulator_inventory",
        arguments: {},
        _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {name: "live-integration", version: "1.0"},
            "io.modelcontextprotocol/clientCapabilities": {}
        }
    }
}' | "$MCP" > "$ARTIFACT_ROOT/mcp-inventory-response.json"
jq -e --arg udid "$DEVICE_UDID" '
    .result.isError == false
    and (.result.structuredContent.devices | any(.udid == $udid))
' "$ARTIFACT_ROOT/mcp-inventory-response.json" >/dev/null

log "Generating a destructive plan scoped only to the dedicated simulator"
jq -n \
    --arg udid "$DEVICE_UDID" \
    --arg marker "$TEST_MARKER" \
    --arg domain "$TEST_DOMAIN" \
    '{
        apiVersion: "awesome-ios-sim/v1alpha1",
        kind: "SimulatorState",
        metadata: {name: "live-integration-mutation"},
        target: {udid: $udid},
        spec: {
            power: "booted",
            eraseBeforeApply: true,
            preferences: [{domain: $domain, key: "marker", value: $marker}],
            statusBar: {time: "09:41", batteryLevel: 87}
        }
    }' > "$ARTIFACT_ROOT/mutation.profile.json"

"$CLI" plan \
    --profile "$ARTIFACT_ROOT/mutation.profile.json" \
    --device "$DEVICE_UDID" \
    --compact > "$ARTIFACT_ROOT/mutation.plan.json"
jq -e --arg udid "$DEVICE_UDID" '
    .targetUDID == $udid
    and [.operations[].action] == ["erase", "boot", "setPreference", "setStatusBar"]
    and .operations[0].risk == "destructive"
    and ([.operations[].requiresConfirmation] | all)
' "$ARTIFACT_ROOT/mutation.plan.json" >/dev/null

log "Proving apply is a dry-run without --confirm"
"$CLI" apply \
    --plan "$ARTIFACT_ROOT/mutation.plan.json" \
    --compact > "$ARTIFACT_ROOT/dry-run.report.json"
jq -e '.status == "dryRun" and (.receipts | length == 0)' \
    "$ARTIFACT_ROOT/dry-run.report.json" >/dev/null
"$CLI" snapshot --device "$DEVICE_UDID" --compact > "$ARTIFACT_ROOT/snapshot-after-dry-run.json"
jq -e '.state.power == "shutdown"' "$ARTIFACT_ROOT/snapshot-after-dry-run.json" >/dev/null

log "Applying the reviewed plan with explicit confirmation"
"$CLI" apply \
    --plan "$ARTIFACT_ROOT/mutation.plan.json" \
    --confirm \
    --journal "$ARTIFACT_ROOT/mutation.journal.json" \
    --compact > "$ARTIFACT_ROOT/mutation.report.json"
jq -e '
    .status == "succeeded"
    and [.receipts[].action] == ["erase", "boot", "setPreference", "setStatusBar"]
    and ([.receipts[].exitCode] | all(. == 0))
' "$ARTIFACT_ROOT/mutation.report.json" >/dev/null

log "Verifying booted power, preference write, and status bar override"
"$CLI" snapshot --device "$DEVICE_UDID" --compact > "$ARTIFACT_ROOT/snapshot-after-apply.json"
jq -e '.state.power == "booted"' "$ARTIFACT_ROOT/snapshot-after-apply.json" >/dev/null
PREFERENCE_VALUE="$(xcrun simctl spawn "$DEVICE_UDID" defaults read "$TEST_DOMAIN" marker)"
[[ "$PREFERENCE_VALUE" == "$TEST_MARKER" ]] || fail "Preference verification failed"
xcrun simctl status_bar "$DEVICE_UDID" list > "$ARTIFACT_ROOT/status-bar.txt"
grep -q '09:41' "$ARTIFACT_ROOT/status-bar.txt" || fail "Status bar time override was not reported"
grep -q '87' "$ARTIFACT_ROOT/status-bar.txt" || fail "Status bar battery override was not reported"

log "Checking live MCP snapshot after mutation"
jq -cn --arg udid "$DEVICE_UDID" '{
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
        name: "simulator_snapshot",
        arguments: {udid: $udid},
        _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {name: "live-integration", version: "1.0"},
            "io.modelcontextprotocol/clientCapabilities": {}
        }
    }
}' | "$MCP" > "$ARTIFACT_ROOT/mcp-snapshot-response.json"
jq -e --arg udid "$DEVICE_UDID" '
    .result.isError == false
    and .result.structuredContent.device.udid == $udid
    and .result.structuredContent.state.power == "booted"
' "$ARTIFACT_ROOT/mcp-snapshot-response.json" >/dev/null

log "Verifying exact convergence for the readable power capability"
jq -n --arg udid "$DEVICE_UDID" '{
    apiVersion: "awesome-ios-sim/v1alpha1",
    kind: "SimulatorState",
    metadata: {name: "live-integration-convergence"},
    target: {udid: $udid},
    spec: {power: "booted"}
}' > "$ARTIFACT_ROOT/convergence.profile.json"
"$CLI" plan \
    --profile "$ARTIFACT_ROOT/convergence.profile.json" \
    --device "$DEVICE_UDID" \
    --compact > "$ARTIFACT_ROOT/convergence.plan.json"
jq -e '(.diff | length == 0) and (.operations | length == 0)' \
    "$ARTIFACT_ROOT/convergence.plan.json" >/dev/null

log "Reconciling the dedicated simulator back to shutdown through MCP"
jq -n --arg udid "$DEVICE_UDID" '{
    apiVersion: "awesome-ios-sim/v1alpha1",
    kind: "SimulatorState",
    metadata: {name: "live-integration-shutdown"},
    target: {udid: $udid},
    spec: {power: "shutdown"}
}' > "$ARTIFACT_ROOT/shutdown.profile.json"
jq -cn --arg udid "$DEVICE_UDID" --slurpfile profile "$ARTIFACT_ROOT/shutdown.profile.json" '{
    jsonrpc: "2.0",
    id: 3,
    method: "tools/call",
    params: {
        name: "simulator_plan",
        arguments: {profile: $profile[0], udid: $udid},
        _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {name: "live-integration", version: "1.0"},
            "io.modelcontextprotocol/clientCapabilities": {}
        }
    }
}' | "$MCP" > "$ARTIFACT_ROOT/mcp-shutdown-plan-response.json"
jq -e '.result.isError == false' "$ARTIFACT_ROOT/mcp-shutdown-plan-response.json" >/dev/null
jq '.result.structuredContent' \
    "$ARTIFACT_ROOT/mcp-shutdown-plan-response.json" > "$ARTIFACT_ROOT/shutdown.plan.json"
jq -e '[.operations[].action] == ["shutdown"]' "$ARTIFACT_ROOT/shutdown.plan.json" >/dev/null
jq -cn --slurpfile plan "$ARTIFACT_ROOT/shutdown.plan.json" '{
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: {
        name: "simulator_apply",
        arguments: {plan: $plan[0], confirm: true},
        _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {name: "live-integration", version: "1.0"},
            "io.modelcontextprotocol/clientCapabilities": {}
        }
    }
}' | "$MCP" > "$ARTIFACT_ROOT/mcp-shutdown-apply-response.json"
jq -e '
    .result.isError == false
    and .result.structuredContent.status == "succeeded"
    and [.result.structuredContent.receipts[].action] == ["shutdown"]
' "$ARTIFACT_ROOT/mcp-shutdown-apply-response.json" >/dev/null
"$CLI" snapshot --device "$DEVICE_UDID" --compact > "$ARTIFACT_ROOT/snapshot-final.json"
jq -e '.state.power == "shutdown"' "$ARTIFACT_ROOT/snapshot-final.json" >/dev/null

if [[ "${AISS_KEEP_DEVICE:-0}" != "1" ]]; then
    cleanup_device
    xcrun simctl list devices --json > "$ARTIFACT_ROOT/devices-after-cleanup.json"
    jq -e --arg udid "$DEVICE_UDID" '[.devices[][] | select(.udid == $udid)] | length == 0' \
        "$ARTIFACT_ROOT/devices-after-cleanup.json" >/dev/null
fi

log "PASS: CLI and MCP live integration completed against ${RUNTIME_IDENTIFIER}"
log "Artifacts retained at ${ARTIFACT_ROOT}"
