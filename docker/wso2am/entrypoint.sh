#!/bin/bash
set -e

DEPLOYMENT_TOML="${WORKING_DIRECTORY}/wso2-config-volume/repository/conf/deployment.toml"
ANALYTICS_ENABLED="${APIM_ANALYTICS_ENABLED:-false}"
MOESIF_KEY_VALUE="${MOESIF_KEY:-}"

case "${ANALYTICS_ENABLED}" in
  true|false)
    ;;
  *)
    echo "APIM_ANALYTICS_ENABLED must be either true or false" >&2
    exit 1
    ;;
esac

if [[ "${ANALYTICS_ENABLED}" == "true" && -z "${MOESIF_KEY_VALUE}" ]]; then
  echo "MOESIF_KEY is required when APIM_ANALYTICS_ENABLED=true" >&2
  exit 1
fi

if [[ -f "${DEPLOYMENT_TOML}" ]]; then
  awk -v enabled="${ANALYTICS_ENABLED}" -v moesif_key="${MOESIF_KEY_VALUE}" '
    BEGIN {
      section = ""
    }
    /^\[apim\.analytics\]$/ {
      section = "analytics"
      print
      next
    }
    /^\[apim\.analytics\.properties\]$/ {
      section = "analytics_properties"
      print
      next
    }
    /^\[/ {
      section = ""
    }
    section == "analytics" && /^enable[[:space:]]*=/ {
      print "enable = " enabled
      next
    }
    section == "analytics_properties" && /^moesifKey[[:space:]]*=/ {
      gsub(/\\/, "\\\\", moesif_key)
      gsub(/"/, "\\\"", moesif_key)
      print "moesifKey = \"" moesif_key "\""
      next
    }
    {
      print
    }
  ' "${DEPLOYMENT_TOML}" > "${DEPLOYMENT_TOML}.tmp"
  mv "${DEPLOYMENT_TOML}.tmp" "${DEPLOYMENT_TOML}"
else
  echo "Expected deployment.toml not found at ${DEPLOYMENT_TOML}" >&2
  exit 1
fi

exec /home/wso2carbon/docker-entrypoint.sh "$@"
