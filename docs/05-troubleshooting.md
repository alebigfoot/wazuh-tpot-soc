# Guía de resolución rápida (Troubleshooting)

Referencia rápida de los problemas más comunes al operar este laboratorio
Wazuh. Cada sección incluye: síntoma, diagnóstico y solución.

> **Contexto:** documento vivo. Se actualiza cada vez que aparece un problema
> nuevo y merece la pena sistematizar la respuesta.

---

## Índice

1. [El manager no arranca](#1-el-manager-no-arranca)
2. [El manager dice "Another instance is locking"](#2-el-manager-dice-another-instance-is-locking)
3. [El dashboard no carga](#3-el-dashboard-no-carga)
4. [El dashboard muestra "No API available to connect"](#4-el-dashboard-muestra-no-api-available-to-connect)
5. [El dashboard muestra "version_conflict_engine_exception"](#5-el-dashboard-muestra-version_conflict_engine_exception)
6. [El Indexer está caído (ECONNREFUSED 127.0.0.1:9200)](#6-el-indexer-está-caído-econnrefused-1270019200)
7. [El agente no conecta al manager](#7-el-agente-no-conecta-al-manager)
8. [El agente aparece como "Never connected"](#8-el-agente-aparece-como-never-connected)
9. [Los eventos no llegan al dashboard](#9-los-eventos-no-llegan-al-dashboard)
10. [Diagnóstico general del sistema](#10-diagnóstico-general-del-sistema)

---

## 1. El manager no arranca

### Síntoma

```
$ sudo systemctl status wazuh-manager
Active: failed (Result: timeout)
```

O:

```
$ sudo systemctl start wazuh-manager
Job for wazuh-manager.service failed because the control process exited with error code.
```

### Diagnóstico

```bash
# Ver logs recientes
sudo journalctl -u wazuh-manager -n 80 --no-pager | tail -40

# Ver estado detallado
sudo systemctl status wazuh-manager --no-pager

# Ver log interno
sudo tail -40 /var/ossec/logs/ossec.log
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| **Timeout de systemd** (arranca pero systemd lo mata) | Ampliar timeout (ver sección 1.1) |
| **Locks huérfanos** (`Another instance is locking`) | Ver sección 2 |
| **Puerto ocupado** | `sudo ss -tlnp \| grep 1514` y matar el proceso |
| **Config corrupta** | `sudo /var/ossec/bin/wazuh-control start` para ver error directo |

### 1.1 Ampliar timeout de systemd

```bash
sudo mkdir -p /etc/systemd/system/wazuh-manager.service.d

sudo tee /etc/systemd/system/wazuh-manager.service.d/override.conf > /dev/null <<'EOF'
[Service]
TimeoutStartSec=300
TimeoutStopSec=120
EOF

sudo systemctl daemon-reload
sudo systemctl restart wazuh-manager
```

Verificar:

```bash
sudo systemctl show wazuh-manager | grep -i timeout
```

---

## 2. El manager dice "Another instance is locking"

### Síntoma

```
ERROR: Another instance is locking...
```

### Causa

Ficheros `.pid` huérfanos en `/var/ossec/var/run/` de un arranque anterior
que systemd mató por timeout.

### Solución

```bash
# 1. Confirmar que no hay procesos vivos
ps -ef | grep -iE "wazuh|ossec" | grep -v grep

# 2. Si hay procesos vivos, matarlos
sudo pkill -9 -f wazuh-analysisd
sudo pkill -9 -f wazuh-remoted
sudo pkill -9 -f wazuh-authd
sudo pkill -9 -f wazuh-db
sudo pkill -9 -f wazuh-execd
sudo pkill -9 -f wazuh-modulesd
sudo pkill -9 -f wazuh-apid

# 3. Borrar locks
sudo find /var/ossec/var/run/ -name "*.pid" -delete

# 4. Arrancar
sudo systemctl start wazuh-manager
```

---

## 3. El dashboard no carga

### Síntoma

- `https://127.0.0.1` no responde
- O responde: `Wazuh dashboard server is not ready yet`
- O error 502 Bad Gateway

### Diagnóstico

```bash
# Estado del servicio
sudo systemctl status wazuh-dashboard --no-pager | head -15

# ¿Escucha en el puerto 443?
sudo ss -tlnp | grep 443

# Logs recientes
sudo journalctl -u wazuh-dashboard --since "5 minutes ago" --no-pager | tail -40
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| **Indexer caído** (ECONNREFUSED 9200) | Ver sección 6 |
| **API no responde** | Ver sección 4 |
| **Timeout de arranque** | `sudo systemctl restart wazuh-dashboard`, esperar 90s |
| **Config corrupta** | Ver sección 5 |

### Solución rápida

```bash
sudo systemctl restart wazuh-dashboard
sleep 90
sudo ss -tlnp | grep 443
```

Luego en Firefox: **Ctrl + Shift + R** (recarga forzada).

---

## 4. El dashboard muestra "No API available to connect"

### Síntoma

El dashboard carga pero muestra:

```
Check API connection ❌
[API connection] No API available to connect
```

### Diagnóstico

```bash
# ¿La API responde manualmente?
curl -k -u wazuh:wazuh https://localhost:55000/

# ¿El puerto 55000 escucha?
sudo ss -tlnp | grep 55000

# ¿Qué configuración tiene el plugin?
sudo cat /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml

# ¿Hay errores 403 en los logs?
sudo journalctl -u wazuh-dashboard --since "5 minutes ago" --no-pager | grep -iE "403|api|error" | tail -20
```

### Causa

El plugin Wazuh del dashboard no puede autenticarse contra la API.
Suele pasar tras reinstalar el manager o cambiar contraseñas.

### Solución

Editar el fichero de configuración del plugin:

```bash
sudo nano /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
```

Debe contener:

```yaml
hosts:
  - default:
      url: https://localhost
      port: 55000
      username: wazuh
      password: wazuh
      run_as: false
```

Dar permisos correctos:

```bash
sudo chown wazuh-dashboard:wazuh-dashboard \
  /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
sudo chmod 600 /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
```

Reiniciar el dashboard:

```bash
sudo systemctl restart wazuh-dashboard
sleep 90
```

---

## 5. El dashboard muestra "version_conflict_engine_exception"

### Síntoma

El dashboard muestra:

```
[Alerts index pattern] version conflict, document already exists
[Statistics index pattern] version conflict, document already exists
```

### Causa

El índice `.kibana_*` mantiene index-patterns huérfanos con IDs que
colisionan con los que el dashboard intenta crear. Suele pasar tras un reset
parcial del dashboard.

### Solución — Reset completo de `.kibana_*`

**⚠️ Antes de hacer esto:** los **datos de eventos** (`wazuh-alerts-*`) NO
se tocan. Solo se borra la **configuración del dashboard**.

```bash
# 1. Parar el dashboard
sudo systemctl stop wazuh-dashboard
sleep 5

# 2. Backup del índice actual
curl -sk -u admin:<PASSWORD> \
  "https://localhost:9200/.kibana_1/_search?pretty&size=100" \
  > ~/kibana1-backup.json

# 3. Borrar índices de configuración
curl -sk -X DELETE -u admin:<PASSWORD> "https://localhost:9200/.kibana_1"
curl -sk -X DELETE -u admin:<PASSWORD> "https://localhost:9200/.kibana_2"

# 4. Limpiar caché en disco
sudo rm -rf /usr/share/wazuh-dashboard/data/

# 5. Arrancar
sudo systemctl start wazuh-dashboard
sleep 120
```

Tras esto, el dashboard pedirá reconfigurar la conexión a la API.

---

## 6. El Indexer está caído (ECONNREFUSED 127.0.0.1:9200)

### Síntoma

El dashboard muestra:

```
[ConnectionError]: connect ECONNREFUSED 127.0.0.1:9200
```

O al hacer curl:

```
curl: (7) Failed to connect to localhost port 9200
```

### Diagnóstico

```bash
# ¿Escucha el puerto 9200?
sudo ss -tlnp | grep 9200

# Estado del servicio
sudo systemctl status wazuh-indexer --no-pager | head -15

# Logs recientes
sudo journalctl -u wazuh-indexer --since "15 minutes ago" --no-pager | tail -40
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| **Timeout de arranque** | Ampliar timeout (ver sección 6.1) |
| **Sin RAM** | `free -h` y liberar memoria |
| **Índice corrupto** | Revisar logs, posible recuperación manual |
| **Heap insuficiente** | Ajustar `/etc/wazuh-indexer/jvm.options` |

### 6.1 Ampliar timeout del Indexer

```bash
sudo mkdir -p /etc/systemd/system/wazuh-indexer.service.d

sudo tee /etc/systemd/system/wazuh-indexer.service.d/override.conf > /dev/null <<'EOF'
[Service]
TimeoutStartSec=600
TimeoutStopSec=180
EOF

sudo systemctl daemon-reload
sudo systemctl restart wazuh-indexer
```

Esperar **3-4 minutos** (el Indexer tarda en arrancar).

Verificar:

```bash
sudo systemctl status wazuh-indexer --no-pager | head -10
sudo ss -tlnp | grep 9200
curl -sk -u admin:<PASSWORD> https://localhost:9200/_cluster/health?pretty
```

### 6.2 Si el Indexer no arranca por RAM

```bash
# Ver RAM
free -h

# Ver heap configurado
sudo grep -E "^-Xm" /etc/wazuh-indexer/jvm.options

# Reducir heap si es necesario (editar)
sudo nano /etc/wazuh-indexer/jvm.options
# -Xms512m
# -Xmx512m
```

---

## 7. El agente no conecta al manager

### Síntoma

En el manager:

```bash
sudo /var/ossec/bin/agent_control -l
# ID: 001, Name: agent-test, IP: 192.168.56.104, Never connected
```

O en el log del agente:

```
ERROR: (1216): Unable to connect to '[192.168.56.103]:1514/tcp'
```

### Diagnóstico

**En el agente:**

```bash
# ¿Ping al manager?
ping -c 3 192.168.56.103

# ¿Puerto 1514 accesible?
nc -zv 192.168.56.103 1514

# Log del agente
sudo tail -30 /var/ossec/logs/ossec.log
```

**En el manager:**

```bash
# ¿Escucha en 1514?
sudo ss -tlnp | grep 1514

# ¿Firewall bloquea?
sudo ufw status verbose
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| **Manager caído** | Ver sección 1 |
| **Puerto no escucha** | Verificar `wazuh-remoted` |
| **Firewall** | `sudo ufw allow from 192.168.56.0/24` |
| **Red mal configurada** | Verificar adaptadores Host-Only |
| **Clave incorrecta** | Re-importar clave (ver sección 8) |

### Solución rápida

```bash
# En el manager, permitir todo el rango Host-Only
sudo ufw allow from 192.168.56.0/24

# Reiniciar el agente
sudo systemctl restart wazuh-agent

# Verificar
sudo tail -10 /var/ossec/logs/ossec.log
```

---

## 8. El agente aparece como "Never connected"

### Síntoma

El agente está registrado en el manager, pero nunca conecta.

### Causas

1. Clave mal importada
2. Nombre del agente duplicado
3. IP incorrecta en el registro
4. Manager no acepta la conexión

### Solución

**En el manager — eliminar el agente:**

```bash
sudo /var/ossec/bin/manage_agents
# R → Remove agent
# ID: 001
```

**Re-registrar:**

```bash
sudo /var/ossec/bin/manage_agents
# A → Add agent
#   Name: agent-test
#   IP: 192.168.56.104
# E → Extract key for agent 001
# Q → Quit
```

**En el agente — importar nueva clave:**

```bash
# Borrar la clave antigua
sudo rm /var/ossec/etc/client.keys

# Importar la nueva
sudo /var/ossec/bin/manage_agents -i <NUEVA_CLAVE>

# Reiniciar
sudo systemctl restart wazuh-agent
```

---

## 9. Los eventos no llegan al dashboard

### Síntoma

El agente está Active pero no aparecen eventos en Discover.

### Diagnóstico

**En el agente:**

```bash
# ¿El agente está enviando?
sudo tail -30 /var/ossec/logs/ossec.log

# Forzar eventos
sudo touch /etc/test-$(date +%s).txt
sudo chmod 777 /etc/test-*.txt
```

**En el manager:**

```bash
# ¿Se reciben eventos?
sudo tail -30 /var/ossec/logs/alerts/alerts.log
sudo tail -30 /var/ossec/logs/archives/archives.log
```

**En el dashboard — Discover:**

- Verificar que el índice seleccionado es `wazuh-alerts-*`
- Rango temporal: **Last 24 hours** (o ampliar)
- Filtrar por `agent.name: "agent-test"`

### Causas y soluciones

| Causa | Solución |
|---|---|
| **FIM no configurado** | Revisar `/var/ossec/etc/ossec.conf` del agente |
| **Rango temporal demasiado corto** | Cambiar a Last 24h |
| **Filtro incorrecto** | Quitar filtros, buscar `agent.name` |
| **Indexer sin espacio** | `df -h /` y liberar |

---

## 10. Diagnóstico general del sistema

Comando de cabecera para tener una **vista completa del estado**:

```bash
echo "=== Servicios ==="
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard

echo ""
echo "=== Puertos ==="
sudo ss -tlnp | grep -E "443|1514|1515|55000|9200"

echo ""
echo "=== Cluster ==="
curl -sk -u admin:<PASSWORD> https://localhost:9200/_cluster/health?pretty | head -15

echo ""
echo "=== API ==="
TOKEN=$(curl -sk -X POST -u wazuh:wazuh "https://localhost:55000/security/user/authenticate?raw=true")
curl -sk -H "Authorization: Bearer $TOKEN" https://localhost:55000/ | head -3

echo ""
echo "=== Agentes ==="
sudo /var/ossec/bin/agent_control -l

echo ""
echo "=== Recursos ==="
free -h
df -h /
```

Guarda esto como script: `automation/scripts/health-check.sh`

---

## Comandos rápidos de referencia

| Quiero... | Comando |
|---|---|
| Ver agentes conectados | `sudo /var/ossec/bin/agent_control -l` |
| Ver demonios del manager | `sudo /var/ossec/bin/wazuh-control status` |
| Estado cluster | `curl -sk -u admin:<PASS> https://localhost:9200/_cluster/health?pretty` |
| Ver si API responde | `curl -k -u wazuh:wazuh https://localhost:55000/` |
| Estado servicios | `sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard` |
| Ver logs del manager | `sudo tail -50 /var/ossec/logs/ossec.log` |
| Ver logs del agente | `sudo tail -50 /var/ossec/logs/ossec.log` |
| Limpiar locks manager | `sudo find /var/ossec/var/run/ -name "*.pid" -delete` |
| Reiniciar todo | `sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard` |

---

## Referencias

- [Documentación oficial Wazuh](https://documentation.wazuh.com/)
- [Incidentes documentados](04-incidents.md)
- [Validación del agente](03-agent-validation.md)
