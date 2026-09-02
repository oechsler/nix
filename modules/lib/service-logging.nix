# Service Logging Helpers
#
# Shared shell logging for services owned by this configuration.

_:

{
  # Shared shell logging for services owned by this configuration.
  # Journald already supplies the unit name, timestamp, and PID.
  _module.args.serviceLog = ''
    log() {
      local event="$1"
      local status="$2"
      shift 2
      printf 'event=%s status=%s detail="%s"\n' "$event" "$status" "$*"
    }
  '';
}
