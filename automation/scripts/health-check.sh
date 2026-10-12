#!/usr/bin/env bash
# health-check.sh - Diagnóstico rápido del SOC Wazuh
set -euo pipefail

# Credenciales (ajusta o exporta antes de ejecutar)
ADMIN_USER="${WAZUH_INDEXER_USER:-admin}"
ADMIN_PASS="${WAZUH_INDEXER_PASSWORD:-CHANGE_ME}"
API_USER="${WAZUH_API_USER:-wazuh}"
API_PASS="${WAZUH_API_PASSWORD:-wazuh}"

echo "==============================================="
echo "  Wazuh SOC Health Check - $(date)"
echo "==============================================="
echo ""

echo "=== [1] Servicios activos ==="
for s in wazuh-indexer wazuh-manager wazuh-dashboard; do
  if systemctl is-active --quiet "$s"; then
    echo "  [OK]   $s"
  else
    echo "  [FAIL] $s"
  fi
done

echo ""
echo "=== [2] Puertos escuchando ==="
if ss -tlnp 2>/dev/null | grep -qE "1514"; then
  echo "  [OK]   1514 (remoted)"
else
  echo "  [FAIL] 1514 (remoted) NO ESCUCHA"
fi
if ss -tlnp 2>/dev/null | grep -qE "1515"; then
  echo "  [OK]   1515 (authd)"
else
  echo "  [FAIL] 1515 (authd) NO ESCUCHA"
fi
if ss -tlnp 2>/dev/null | grep -qE "55000"; then
  echo "  [OK]   55000 (API)"
else
  echo "  [FAIL] 55000 (API) NO ESCUCHA"
fi
if ss -tlnp 2>/dev/null | grep -qE "9200"; then
  echo "  [OK]   9200 (Indexer)"
else
  echo "  [FAIL] 9200 (Indexer) NO ESCUCHA"
fi
if ss -tlnp 2>/dev/null | grep -qE ":443"; then
  echo "  [OK]   443 (Dashboard)"
else
  echo "  [FAIL] 443 (Dashboard) NO ESCUCHA"
fi

echo ""
echo "=== [3] Cluster ==="
curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "https://localhost:9200/_cluster/health?pretty" 2>/dev/null \
  | grep -E '"status"|"number_of_nodes"' || echo "  [FAIL] No responde"

echo ""
echo "=== [4] API ==="
TOKEN=$(curl -sk -X POST -u "${API_USER}:${API_PASS}" \
  "https://localhost:55000/security/user/authenticate?raw=true" 2>/dev/null || echo "")
if [ -n "$TOKEN" ] && [[ "$TOKEN" != *"{"* ]]; then
  echo "  [OK]   API responde"
  curl -sk -H "Authorization: Bearer ${TOKEN}" \
    https://localhost:55000/ 2>/dev/null | head -c 200
  echo ""
else
  echo "  [FAIL] API no responde o credenciales incorrectas"
fi

echo ""
echo "=== [5] Agentes conectados ==="
/var/ossec/bin/agent_control -l 2>/dev/null || echo "  [FAIL] agent_control no disponible"

echo ""
echo "=== [6] Recursos ==="
free -h | head -2
echo ""
df -h / | tail -1

echo ""
echo "==============================================="
echo "  Health check completado"
echo "==============================================="
