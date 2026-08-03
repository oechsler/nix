# Unified display brightness controller
#
# Provides shared backlight, DDC/CI, and gamma brightness actions.
# Manual adjustment and idle dimming use the same backend priority.
{ pkgs }:

pkgs.writeShellScript "display-brightness-controller" ''
  state_dir="''${XDG_RUNTIME_DIR:-/tmp}/display-brightness"
  gamma_pidfile="$state_dir/gamma.pid"
  ${pkgs.coreutils}/bin/mkdir -p "$state_dir"

  has_backlight() {
    set -- /sys/class/backlight/*
    [ -e "$1" ]
  }

  clear_gamma() {
    if [ -s "$gamma_pidfile" ]; then
      kill "$(<"$gamma_pidfile")" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -f "$gamma_pidfile"
    fi
    ${pkgs.hyprsunset}/bin/hyprsunset -i >/dev/null 2>&1 || true
  }

  set_gamma() {
    local target="$1"
    if [ -s "$gamma_pidfile" ]; then
      kill "$(<"$gamma_pidfile")" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -f "$gamma_pidfile"
    fi
    if [ "$target" -ge 100 ]; then
      ${pkgs.hyprsunset}/bin/hyprsunset -i >/dev/null 2>&1 || true
      return
    fi
    local gamma
    gamma=$(printf "%d.%02d" $((target / 100)) $((target % 100)))
    ${pkgs.hyprsunset}/bin/hyprsunset -g "$gamma" >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$gamma_pidfile"
  }

  init_ddc() {
    [ -e "$state_dir/ready" ] && return
    exec 7>"$state_dir/init.lock"
    ${pkgs.util-linux}/bin/flock 7
    [ -e "$state_dir/ready" ] && return

    local buses_tmp="$state_dir/buses.tmp.$$"
    local displays_tmp="$state_dir/displays.tmp.$$"
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.ddcutil}/bin/ddcutil detect --terse 2>/dev/null \
      | ${pkgs.gawk}/bin/awk '$1 == "I2C" && $2 == "bus:" { sub("/dev/i2c-", "", $3); print $3 }' \
      > "$buses_tmp"

    : > "$displays_tmp"
    while read -r bus; do
      values=$(${pkgs.coreutils}/bin/timeout 3 ${pkgs.ddcutil}/bin/ddcutil --bus "$bus" getvcp 10 --terse 2>/dev/null | ${pkgs.gawk}/bin/awk '$1 == "VCP" { print $4, $5; exit }')
      set -- $values
      [ -n "$1" ] && [ -n "$2" ] && printf '%s %s %s\n' "$bus" "$1" "$2" >> "$displays_tmp"
    done < "$buses_tmp"

    if [ -s "$displays_tmp" ]; then
      ${pkgs.coreutils}/bin/mv "$displays_tmp" "$state_dir/displays"
      if [ ! -s "$state_dir/target" ]; then
        ${pkgs.gawk}/bin/awk 'NR == 1 { print int(100 * $2 / $3); exit }' "$state_dir/displays" > "$state_dir/target"
      fi
    else
      ${pkgs.coreutils}/bin/rm -f "$displays_tmp"
    fi
    ${pkgs.coreutils}/bin/rm -f "$buses_tmp"
    ${pkgs.coreutils}/bin/touch "$state_dir/ready"
  }

  write_ddc_percent() {
    local target="$1"
    local pids=""
    local failed=0
    while read -r bus _ maximum; do
      value=$((target * maximum / 100))
      ${pkgs.coreutils}/bin/timeout 2 ${pkgs.ddcutil}/bin/ddcutil --bus "$bus" setvcp 10 "$value" --noverify >/dev/null 2>&1 &
      pids="$pids $!"
    done < "$state_dir/displays"
    for pid in $pids; do
      wait "$pid" || failed=1
    done
    return "$failed"
  }

  restore_ddc_values() {
    local source="$1"
    local pids=""
    while read -r bus current _; do
      ${pkgs.coreutils}/bin/timeout 2 ${pkgs.ddcutil}/bin/ddcutil --bus "$bus" setvcp 10 "$current" --noverify >/dev/null 2>&1 &
      pids="$pids $!"
    done < "$source"
    for pid in $pids; do
      wait "$pid" 2>/dev/null || true
    done
  }

  update_ddc_state() {
    local target="$1"
    local displays_tmp="$state_dir/displays.tmp.$$"
    ${pkgs.gawk}/bin/awk -v target="$target" '{ print $1, int(target * $3 / 100), $3 }' "$state_dir/displays" > "$displays_tmp"
    ${pkgs.coreutils}/bin/mv "$displays_tmp" "$state_dir/displays"
  }

  apply_target() {
    exec 9>"$state_dir/apply.lock"
    ${pkgs.util-linux}/bin/flock -n 9 || return
    exec 8>"$state_dir/ddc.lock"
    ${pkgs.util-linux}/bin/flock -w 3 8 || return
    [ -s "$state_dir/idle-backend" ] && return

    while [ -s "$state_dir/target" ]; do
      target=$(<"$state_dir/target")
      if [ -s "$state_dir/displays" ]; then
        if write_ddc_percent "$target"; then
          update_ddc_state "$target"
          clear_gamma
        else
          restore_ddc_values "$state_dir/displays"
          set_gamma "$target"
          return
        fi
      else
        set_gamma "$target"
      fi
      latest=$(<"$state_dir/target")
      [ "$latest" = "$target" ] && return
    done
  }

  adjust() {
    local direction="$1"
    case "$direction" in
      up|down) ;;
      *) exit 2 ;;
    esac

    if has_backlight; then
      if [ "$direction" = "up" ]; then
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%+ -q
      else
        ${pkgs.brightnessctl}/bin/brightnessctl -e4 -n2 set 5%- -q
      fi
      brightness=$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.gawk}/bin/awk -F, '{ print substr($4, 1, length($4) - 1) }')
      exec ${import ./brightness-notify.nix { inherit pkgs; }} "$brightness"
    fi

    init_ddc
    exec 9>"$state_dir/target.lock"
    ${pkgs.util-linux}/bin/flock 9
    [ -s "$state_dir/idle-backend" ] && return
    brightness=''${brightness:-100}
    [ -s "$state_dir/target" ] && brightness=$(<"$state_dir/target")
    if [ "$direction" = "up" ]; then
      brightness=$((brightness + 5))
      [ "$brightness" -gt 100 ] && brightness=100
    else
      brightness=$((brightness - 5))
      [ "$brightness" -lt 0 ] && brightness=0
    fi
    printf '%s\n' "$brightness" > "$state_dir/target"
    ${pkgs.util-linux}/bin/flock -u 9
    ${import ./brightness-notify.nix { inherit pkgs; }} "$brightness" &
    "$0" apply >/dev/null 2>&1 &
  }

  dim() {
    local target="''${1:-30}"
    local step_percent="''${2:-5}"
    local step_delay="''${3:-0.05}"
    exec 9>"$state_dir/target.lock"
    ${pkgs.util-linux}/bin/flock 9
    [ -s "$state_dir/idle-backend" ] && return

    if has_backlight; then
      printf 'backlight\n' > "$state_dir/idle-backend"
      ${pkgs.brightnessctl}/bin/brightnessctl -s
      current=$(${pkgs.brightnessctl}/bin/brightnessctl get)
      maximum=$(${pkgs.brightnessctl}/bin/brightnessctl max)
      target_value=$((maximum * target / 100))
      step=$((maximum * step_percent / 100))
      [ "$step" -lt 1 ] && step=1
      while [ "$current" -gt "$target_value" ]; do
        current=$((current - step))
        [ "$current" -lt "$target_value" ] && current="$target_value"
        ${pkgs.brightnessctl}/bin/brightnessctl set "$current" -q
        ${pkgs.coreutils}/bin/sleep "$step_delay"
      done
      return
    fi

    init_ddc
    exec 8>"$state_dir/ddc.lock"
    ${pkgs.util-linux}/bin/flock -w 3 8 || return
    if [ -s "$state_dir/displays" ]; then
      ${pkgs.coreutils}/bin/cp "$state_dir/displays" "$state_dir/idle-ddc-state"
      if write_ddc_percent "$target"; then
        update_ddc_state "$target"
        clear_gamma
        printf 'ddc\n' > "$state_dir/idle-backend"
        return
      fi
      restore_ddc_values "$state_dir/idle-ddc-state"
      ${pkgs.coreutils}/bin/rm -f "$state_dir/idle-ddc-state"
    fi
    set_gamma "$target"
    printf 'gamma\n' > "$state_dir/idle-backend"
  }

  restore() {
    [ -s "$state_dir/idle-backend" ] || return
    exec 9>"$state_dir/target.lock"
    ${pkgs.util-linux}/bin/flock 9
    backend=$(<"$state_dir/idle-backend")
    case "$backend" in
      backlight)
        ${pkgs.brightnessctl}/bin/brightnessctl -r
        ;;
      ddc)
        exec 8>"$state_dir/ddc.lock"
        ${pkgs.util-linux}/bin/flock -w 3 8 || return
        if [ -s "$state_dir/idle-ddc-state" ]; then
          restore_ddc_values "$state_dir/idle-ddc-state"
          ${pkgs.coreutils}/bin/mv "$state_dir/idle-ddc-state" "$state_dir/displays"
          ${pkgs.gawk}/bin/awk 'NR == 1 { print int(100 * $2 / $3); exit }' "$state_dir/displays" > "$state_dir/target"
        fi
        ;;
      gamma)
        target=100
        [ -s "$state_dir/target" ] && target=$(<"$state_dir/target")
        set_gamma "$target"
        ;;
    esac
    ${pkgs.coreutils}/bin/rm -f "$state_dir/idle-backend"
  }

  case "''${1:-}" in
    init)
      has_backlight || init_ddc
      ;;
    adjust)
      shift
      adjust "$@"
      ;;
    apply)
      apply_target
      ;;
    dim)
      shift
      dim "$@"
      ;;
    restore)
      restore
      ;;
    *)
      exit 2
      ;;
  esac
''
