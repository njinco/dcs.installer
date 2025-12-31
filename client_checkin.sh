#!/usr/bin/env bash

NC_URL="${NC_URL:-}"
NC_API_KEY="${NC_API_KEY:-}"
DEVICE_HOSTNAME="${DEVICE_ID_OVERRIDE:-$(hostname)}"
INTERVAL_SEC="${INTERVAL_SEC:-300}"   # 5 minutes

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "NC_URL or NC_API_KEY missing; set them in the environment." >&2
  exit 1
fi

get_public_ip() {
  local ip
  local services=(
    "https://ifconfig.me"
    "https://api.ipify.org"
    "https://ipinfo.io/ip"
    "https://checkip.amazonaws.com"
    "https://icanhazip.com"
  )
  for svc in "${services[@]}"; do
    ip="$(curl -4 -sS --max-time 5 "$svc" | tr -d '[:space:]')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  done

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  fi

  echo "unknown"
}

while true; do
  TS="$(TZ='Asia/Manila' date +"%d-%m-%Y %H:%M")"
  PUBIP="$(get_public_ip)"

  echo "[$(date)] sending check-in: $DEVICE_HOSTNAME at $TS ($PUBIP)"
  RESP="$(curl -sS --max-time 10 -w "\n%{http_code}" -X POST "$NC_URL" \
    -H "xc-token: $NC_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$DEVICE_HOSTNAME\",\"last_seen\":\"$TS\",\"ip\":\"$PUBIP\"}")"

  CURL_EXIT=$?
  HTTP_CODE="${RESP##*$'\n'}"
  BODY="${RESP%$'\n'*}"

  if [[ $CURL_EXIT -ne 0 ]]; then
    echo "curl failed with exit code: $CURL_EXIT"
  else
    if [[ "$HTTP_CODE" =~ ^[0-9]{3}$ && ( "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ) ]]; then
      echo "non-success HTTP code: $HTTP_CODE"
    else
      echo "response code: $HTTP_CODE"
    fi
    if [[ -n "$BODY" ]]; then
      echo "response body: $BODY"
    fi
  fi

  sleep "$INTERVAL_SEC"
done
