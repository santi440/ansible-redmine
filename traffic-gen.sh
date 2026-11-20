#!/bin/bash
# Generador de trafico con baseline constante + picos + mezcla de errores.
set -u

DURATION=${DURATION:-600}        # duracion total en segundos (default 10 min)
CYCLE=${CYCLE:-5}                # segundos entre tandas
BASE=${BASE:-20}                 # requests por ciclo en el baseline
SPIKE_EVERY=${SPIKE_EVERY:-6}    # un pico cada N ciclos
SPIKE_MULT=${SPIKE_MULT:-4}      # multiplicador de requests en el pico
CONCURRENCY=${CONCURRENCY:-8}    # requests simultaneos

BASE_URL="http://127.0.0.1"
export BASE_URL
OK_URLS=("/" "/issues" "/projects" "/login")
ERR404_URLS=("/issues/999999999" "/this-route-does-not-exist" "/projects/no-existe")
ERR500="/issues?set_filter=1&f[]=campo_inexistente&op[]=~&v[]=x"

RESULTS=/tmp/traffic-gen-results.txt
: > "$RESULTS"

pick_path() {
  local r=$((RANDOM % 100))
  if   [ "$r" -lt 70 ]; then printf '%s' "${OK_URLS[$((RANDOM % ${#OK_URLS[@]}))]}"
  elif [ "$r" -lt 90 ]; then printf '%s' "${ERR404_URLS[$((RANDOM % ${#ERR404_URLS[@]}))]}"
  else printf '%s' "$ERR500"
  fi
}
export -f pick_path

fire() {
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 "${BASE_URL}$1"
}
export -f fire

start=$(date +%s)
cycle=0
echo "=== traffic-gen iniciado $(date) | duration=${DURATION}s base=${BASE}/ciclo spike=x${SPIKE_MULT} cada ${SPIKE_EVERY} ciclos ==="
while [ $(( $(date +%s) - start )) -lt "$DURATION" ]; do
  cycle=$((cycle + 1))
  if [ $(( cycle % SPIKE_EVERY )) -eq 0 ]; then
    n=$((BASE * SPIKE_MULT)); tag="PICO"
  else
    n=$BASE; tag="base"
  fi

  : > /tmp/traffic-gen-batch.txt
  for _ in $(seq 1 "$n"); do
    pick_path >> /tmp/traffic-gen-batch.txt
    printf '\0' >> /tmp/traffic-gen-batch.txt
  done

  batch_start=$(date +%s)
  xargs -0 -P "$CONCURRENCY" -I{} bash -c 'fire "$@"' _ {} < /tmp/traffic-gen-batch.txt >> "$RESULTS"
  elapsed=$(( $(date +%s) - batch_start ))

  ok=$(grep -c '^2' "$RESULTS" || true)
  e4=$(grep -c '^4' "$RESULTS" || true)
  e5=$(grep -c '^5' "$RESULTS" || true)
  echo "ciclo=$cycle tipo=$tag req=$n t=${elapsed}s | acumulado 2xx=$ok 4xx=$e4 5xx=$e5"
  sleep "$CYCLE"
done

echo "=== finalizado $(date) ==="
echo "TOTALES: 2xx=$(grep -c '^2' "$RESULTS") 4xx=$(grep -c '^4' "$RESULTS") 5xx=$(grep -c '^5' "$RESULTS")"