# shellcheck shell=bash
# Console output helpers.

if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

STEP_CURRENT=0
STEP_TOTAL=0

info() { printf '%b\n' "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
success() { printf '%b\n' "    ${GREEN}✓${RESET} $*"; }
warn() { printf '%b\n' "    ${YELLOW}!${RESET} $*"; }
error() {
  printf '%b\n' "${RED}Error:${RESET} $*" >&2
  exit 1
}
step() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  printf '\n'
  info "[$STEP_CURRENT/$STEP_TOTAL] $*"
}
label_bool() { [[ "$1" == "true" ]] && printf '%b\n' "${GREEN}enabled${RESET}" || printf '%b\n' "${DIM}disabled${RESET}"; }
