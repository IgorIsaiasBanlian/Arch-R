#!/bin/bash

#==============================================================================
# Arch R - Generate Panel DTBO Overlays
#==============================================================================
# Generates DTBO overlay files for ALL panel variants using archr-dtbo.py
#
# Sources:
#   - R36S originals: DTS in config/archr-dts/R36S-DTB/DTS/
#   - R36S clones: DTBs in config/archr-dts/R36S-Clones-DTB/
#
# Output:
#   - output/panels/original/  -> overlays for original R36S image
#   - output/panels/clone/     -> overlays for clone R36S image
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
DTS_DIR="${ROOT_DIR}/config/archr-dts/R36S-DTB/DTS"
CLONES_DIR="${ROOT_DIR}/config/archr-dts/R36S-Clones-DTB"
OUTPUT_ORIG="${ROOT_DIR}/config/mipi-generator/output/original"
OUTPUT_CLONE="${ROOT_DIR}/config/mipi-generator/output/clone"
DTBO_TOOL="$SCRIPT_DIR/archr-dtbo.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[PANEL]${NC} $1"; }
warn() { echo -e "${YELLOW}[PANEL] WARNING:${NC} $1"; }
error() { echo -e "${RED}[PANEL] ERROR:${NC} $1"; exit 1; }

# Check prerequisites
command -v dtc &>/dev/null || error "dtc not found"
command -v python3 &>/dev/null || error "python3 not found"
python3 -c "import fdt" 2>/dev/null || error "Python fdt package not found. Install with: pip3 install fdt"
[ -f "$DTBO_TOOL" ] || error "archr-dtbo.py not found at: $DTBO_TOOL"

mkdir -p "$OUTPUT_ORIG" "$OUTPUT_CLONE"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

GENERATED=0
FAILED=0

#------------------------------------------------------------------------------
# Helper: generate overlay from DTS file (compile DTS->DTB, then run dtbo.py)
#------------------------------------------------------------------------------
generate_from_dts() {
    local dts_file="$1"
    local out_file="$2"
    local flags="$3"
    local label="$4"

    if [ ! -f "$dts_file" ]; then
        warn "  DTS not found: $dts_file"
        FAILED=$((FAILED + 1))
        return 1
    fi

    local tmp_dtb="$TMPDIR/$(basename "${dts_file%.dts}").dtb"
    if ! dtc -I dts -O dtb -@ "$dts_file" -o "$tmp_dtb" 2>/dev/null; then
        warn "  Failed to compile DTS: $(basename "$dts_file")"
        FAILED=$((FAILED + 1))
        return 1
    fi

    if python3 "$DTBO_TOOL" "$tmp_dtb" $flags -o "$out_file" 2>/dev/null; then
        local sz=$(stat -c%s "$out_file")
        log "  OK: $(basename "$out_file") (${sz} bytes) [$label]"
        GENERATED=$((GENERATED + 1))
    else
        warn "  archr-dtbo.py failed: $(basename "$out_file")"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

#------------------------------------------------------------------------------
# Helper: generate overlay from pre-compiled DTB
#------------------------------------------------------------------------------
generate_from_dtb() {
    local dtb_file="$1"
    local out_file="$2"
    local flags="$3"
    local label="$4"

    if [ ! -f "$dtb_file" ]; then
        warn "  DTB not found: $dtb_file"
        FAILED=$((FAILED + 1))
        return 1
    fi

    if python3 "$DTBO_TOOL" "$dtb_file" $flags -o "$out_file" 2>/dev/null; then
        local sz=$(stat -c%s "$out_file")
        log "  OK: $(basename "$out_file") (${sz} bytes) [$label]"
        GENERATED=$((GENERATED + 1))
    else
        warn "  archr-dtbo.py failed: $(basename "$out_file")"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

#------------------------------------------------------------------------------
# Original R36S panels (DTS files)
#------------------------------------------------------------------------------
log "=== Original R36S Panel Overlays ==="
log "Source: $DTS_DIR"
log "Output: $OUTPUT_ORIG"
log ""

# Panel index -> DTS filename
declare -A ORIG_PANELS=(
    [panel0]="Panel0.dts"
    [panel1]="Panel1.dts"
    [panel2]="Panel2.dts"
    [panel3]="Panel3.dts"
    [panel4]="Panel4.dts"
    [panel4-v22]="Panel4-V22.dts"
    [panel5]="Panel5.dts"
    [r35s-rumble]="R35S-Rumble.dts"
    [r36s-plus]="R36S-Plus.dts"
    [r46h]="R46H.dts"
    [rgb20s]="RGB20S.dts"
)

ORIG_ORDER=(panel0 panel1 panel2 panel3 panel4 panel4-v22 panel5 r35s-rumble r36s-plus r46h rgb20s)

for key in "${ORIG_ORDER[@]}"; do
    dts="${ORIG_PANELS[$key]}"
    log "Original ${key}: ${dts}"
    generate_from_dts "$DTS_DIR/$dts" "$OUTPUT_ORIG/${key}.dtbo" "" "$key"
done

# Panel 6: no DTS source, use stock DTB
log "Original panel6: R36S/Panel 6/rk3326-r35s-linux.dtb"
generate_from_dtb "${ROOT_DIR}/config/archr-dts/R36S-DTB/R36S/Panel 6/rk3326-r35s-linux.dtb" "$OUTPUT_ORIG/panel6.dtbo" "" "panel6"

#------------------------------------------------------------------------------
# Clone R36S panels (pre-compiled DTBs)
#------------------------------------------------------------------------------
log ""
log "=== Clone R36S Panel Overlays ==="
log "Source: $CLONES_DIR"
log "Output: $OUTPUT_CLONE"
log ""

declare -A CLONE_PANELS=(
    [clone_panel_1]="Panel 1/rf3536k4ka.dtb"
    [clone_panel_2]="Panel 2/rf3536k4ka.dtb"
    [clone_panel_3]="Panel 3/rf3536k4ka.dtb"
    [clone_panel_4]="Panel 4/rf3536k4ka.dtb"
    [clone_panel_5]="Panel 5/rf3536k4ka.dtb"
    [clone_panel_6]="Panel 6/rf3536k4ka.dtb"
    [clone_panel_7]="Panel 7/rf3536k4ka.dtb"
    [clone_panel_8]="Panel 8/rf3536k4ka.dtb"
    [clone_panel_9]="Panel 9/rf3536k4ka.dtb"
    [clone_panel_10]="Panel 10/rf3536k3ka.dtb"
    [r36_max]="R36 Max/rf3536k4ka.dtb"
    [rx6s]="RX6S/rf351g3ka.dtb"
)

CLONE_ORDER=(clone_panel_1 clone_panel_2 clone_panel_3 clone_panel_4 clone_panel_5
             clone_panel_6 clone_panel_7 clone_panel_8 clone_panel_9 clone_panel_10
             r36_max rx6s)

for key in "${CLONE_ORDER[@]}"; do
    dtb="${CLONE_PANELS[$key]}"
    log "Clone ${key}: ${dtb}"
    generate_from_dtb "$CLONES_DIR/$dtb" "$OUTPUT_CLONE/${key}.dtbo" "" "$key"
done

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== Panel Generation Complete ==="
log "Generated: ${GENERATED}  Failed: ${FAILED}"
log ""
log "Original overlays: $OUTPUT_ORIG/"
ls -1 "$OUTPUT_ORIG"/*.dtbo 2>/dev/null | while read f; do
    log "  $(basename "$f") ($(stat -c%s "$f") bytes)"
done
log ""
log "Clone overlays: $OUTPUT_CLONE/"
ls -1 "$OUTPUT_CLONE"/*.dtbo 2>/dev/null | while read f; do
    log "  $(basename "$f") ($(stat -c%s "$f") bytes)"
done
