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
11. [DNS no resuelve en el manager](#11-dns-no-resuelve-en-el-manager)
12. [Tailscale no autentica (URL caduca)](#12-tailscale-no-autentica-url-caduca)
13. [Tailscale muestra "Logged out" tras reconectar](#13-tailscale-muestra-logged-out-tras-reconectar)
14. [Pérdida de DNS al cambiar adaptador en VirtualBox](#14-pérdida-de-dns-al-cambiar-adaptador-en-virtualbox)
15. [T-Pot rechaza la versión del sistema](#15-t-pot-rechaza-la-versión-del-sistema)
16. [T-Pot no se ejecuta como root](#16-t-pot-no-se-ejecuta-como-root)
17. [Contenedores de T-Pot no arrancan](#17-contenedores-de-t-pot-no-arrancan)
18. [Agente en bucle "Never connected" por auto-enrollment](#18-agente-en-bucle-never-connected-por-auto-enrollment)
19. [Error de `cowrie.json` en el agente](#19-error-de-cowriejson-en-el-agente)
20. [Mismatch de versión agente/manager](#20-mismatch-de-versión-agentemanager)
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

Reiniciar el dashboard

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

## 11. DNS no resuelve en el manager

### Síntoma

```bash
$ dig google.com
;; communications error to 127.0.0.53#53: timed out
;; no servers could be reached
```

Pero `ping 9.9.9.9` **sí funciona** (conectividad IP OK, solo falla resolución).

### Diagnóstico

```bash
# Ver el resolver actual
resolvectl status

# Ver qué DNS tiene cada interfaz
resolvectl status | grep -A3 "Link"

# Ver el contenido del stub
cat /etc/resolv.conf
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| Tailscale secuestra el DNS | `sudo tailscale set --accept-dns=false` |
| NetworkManager con DNS del router caído | `nmcli connection modify <UUID> ipv4.dns "9.9.9.9,1.1.1.1" ipv4.ignore-auto-dns yes` |
| systemd-resolved sin upstream | Reiniciar: `sudo systemctl restart systemd-resolved` |
| Fichero netplan mal configurado | Editar `/etc/netplan/*.yaml` y `sudo netplan apply` |

### Solución rápida (Ubuntu Desktop con NetworkManager)

```bash
# Ver la conexión activa
nmcli connection show --active

# Configurar DNS manual
sudo nmcli connection modify <UUID> \
  ipv4.dns "9.9.9.9,1.1.1.1,8.8.8.8" \
  ipv4.ignore-auto-dns yes

# Desactivar DNS de Tailscale
sudo tailscale set --accept-dns=false

# Aplicar cambios
sudo nmcli connection down <UUID>
sudo nmcli connection up <UUID>

# Verificar
dig google.com +short
```

### Verificación

```bash
resolvectl status | grep "Current DNS Server"
# Debe mostrar 9.9.9.9 (o el que hayas configurado)

dig google.com +short
# Debe devolver IPs
```

---

## 12. Tailscale no autentica (URL caduca)

### Síntoma

```bash
$ sudo tailscale up --accept-dns=false

To authenticate, visit:
https://login.tailscale.com/a/xxxxxxxxxxxx
```

- Abres la URL, autorizas en el navegador
- El panel web muestra la máquina como conectada
- **Pero `tailscale status` sigue diciendo `Logged out`**

### Causa

El flujo de autenticación por URL es **frágil**:

- Las URLs **caducan en 10-15 minutos**
- Si el navegador tiene auto-login con otra cuenta, se autoriza en el sitio equivocado
- El proceso `tailscale up` a veces no recibe la confirmación del servidor

### Solución: usar auth key

**En el navegador:**

1. Ve a `https://login.tailscale.com/admin/settings/keys`
2. **Generate auth key...**
3. Configura:
   - Reusable: ✅
   - Ephemeral: ❌
   - Pre-approved: ✅
   - Expiration: 90 días
4. Copia la key (`tskey-auth-...`)

**En el servidor:**

```bash
# Cancelar intentos previos
pkill -f "tailscale up" 2>/dev/null
tailscale logout

# Autenticar con la key
sudo tailscale up --authkey=tskey-auth-XXXXXXXXX --accept-dns=false
```

**Resultado:** autenticación instantánea, sin navegador, sin URLs.

### Verificación

```bash
tailscale status
tailscale ip -4
```

### Regla

**Para servidores y automatización → auth key.**
**Para laptops y uso manual → URL (aceptable).**

---

## 13. Tailscale muestra "Logged out" tras reconectar

### Síntoma

Tras un rato, o tras reconectar por SSH:

```bash
$ tailscale status
Logged out.
Log in at: https://login.tailscale.com/a/xxxxxxxxxxxx
```

Pero la máquina **sí aparece en el panel web** de Tailscale con IP asignada.

### Causa

Inconsistencia entre el **control plane** (servidor de Tailscale) y el
**cliente local** (`tailscaled`):

- El panel web muestra el dispositivo registrado
- El cliente local no ha persistido el token de sesión
- Puede pasar por: autenticación previa sin completar, corrupción del
  estado local, o conflictos con procesos `tailscale up` colgados

### Solución

```bash
# 1. Cancelar procesos colgados
pkill -f "tailscale up" 2>/dev/null

# 2. Reiniciar el servicio
sudo systemctl restart tailscaled
sleep 5

# 3. Verificar
tailscale status

# 4. Si sigue logged out, autenticar con auth key
tailscale logout
sudo tailscale up --authkey=tskey-auth-XXX --accept-dns=false
```

### Verificación

```bash
tailscale status
# 100.x.y.z  <hostname>  user@  linux  -
# 100.x.y.z  <otro>      user@  linux  active; direct <IP>:41641
```

### Lección

El estado de Tailscale vive en `/var/lib/tailscale/tailscaled.state`.
Si hay inconsistencias, un `systemctl restart tailscaled` suele arreglarlo.

---

## 14. Pérdida de DNS al cambiar adaptador en VirtualBox

### Síntoma

Tras cambiar el adaptador de red de una VM en VirtualBox
(ej. de Host-Only a Adaptador Puente):

- La VM **obtiene IP por DHCP** correctamente
- **Pero la resolución DNS falla**
- `ping 8.8.8.8` funciona
- `dig google.com` falla con timeout

### Causa

Al cambiar el adaptador, NetworkManager o systemd-networkd reconfiguran la
interfaz, pero:

- El DNS del router no se propaga al stub de systemd-resolved
- O Tailscale (si está instalado) sobrescribe el DNS con su propio upstream
- Puede haber caché de conexiones antiguas

### Solución

```bash
# 1. Ver el DNS actual de la interfaz
resolvectl status | grep -A3 "Link"

# 2. Ver si Tailscale está interfiriendo
tailscale status

# 3. Configurar DNS manual con NetworkManager
nmcli connection show --active
sudo nmcli connection modify <UUID> \
  ipv4.dns "9.9.9.9,1.1.1.1,8.8.8.8" \
  ipv4.ignore-auto-dns yes
sudo nmcli connection down <UUID> && sudo nmcli connection up <UUID>

# 4. Si Tailscale interfiere
sudo tailscale set --accept-dns=false

# 5. Verificar
dig google.com +short
```

### Alternativa con netplan

Si usas systemd-networkd en lugar de NetworkManager:

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [9.9.9.9, 1.1.1.1, 8.8.8.8]
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
sudo systemctl restart systemd-resolved
```

### Verificación

```bash
resolvectl status | grep "Current DNS Server"
dig google.com +short
```

### Lección

- **Siempre** verificar DNS tras cambiar de red en una VM.
- `resolvectl status` es el comando clave.
- En Ubuntu Desktop, NetworkManager manda → usar `nmcli`.
- En Ubuntu Server, systemd-networkd manda → usar `netplan`.
- Si Tailscale está instalado, revisar `--accept-dns` inmediatamente.

---

## 15. T-Pot rechaza la versión del sistema

### Síntoma

Al lanzar el instalador de T-Pot:

```
### T-Pot supports Ubuntu 26.04, this system runs 24.04.
### Please install T-Pot on the current release of your distribution.
```

### Causa

T-Pot exige **la última LTS de Ubuntu**. Cada release de T-Pot se alinea
con la versión LTS más reciente.

### Solución

Actualizar la VPS:

```bash
# Verificar versión actual
lsb_release -rs

# Actualizar la distribución
sudo apt update && sudo apt upgrade -y
sudo do-release-upgrade

# Tras el reinicio
lsb_release -rs
# 26.04
```

### Precauciones

- Hacer un **snapshot** de la VPS antes del upgrade (desde el panel del
  proveedor).
- Abrir la **consola VNC** del proveedor en otra pestaña por si se pierde
  el acceso SSH.
- El upgrade tarda 30-60 min.

### Alternativa descartada

Usar una versión antigua de T-Pot (`git clone --branch v24.04.1`).
Descartado por:

- Versión sin actualizaciones de seguridad
- Puede faltar soporte de honeypots nuevos
- Sin mejoras recientes

### Verificar tras el upgrade

```bash
lsb_release -a
uname -r
systemctl --failed
tailscale status
```

---

## 16. T-Pot no se ejecuta como root

### Síntoma

Al ejecutar el instalador con `sudo`:

```
This script should not be run as root. Please run it as a regular user.
```

### Causa

El script comprueba el UID y aborta si es 0 (root). Está por diseño:
quiere ejecutarse desde un usuario normal que solicite `sudo` cuando haga
falta.

### Solución

Crear un usuario normal con sudo:

```bash
sudo adduser tadmin
sudo usermod -aG sudo tadmin
```

Añadir la clave SSH pública a ese usuario:

```bash
cat ~/.ssh/id_ed25519.pub | ssh tadmin@<VPS_IP> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Conectar como `tadmin` y ejecutar **sin `sudo`**:

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP>
cd ~/tpotce
./install.sh -t i -u tadmin -p '<PASSWORD>'
```

### Truco para no meter la contraseña cada vez

```bash
sudo -v              # refresca el timestamp de sudo
./install.sh ...     # el script usará el timestamp sin pedir contraseña
```

### Verificar

Mientras se ejecuta, si pide contraseña es porque el timestamp ha
caducado. Mete la contraseña y sigue.

---

## 17. Contenedores de T-Pot no arrancan

### Síntoma

Tras la instalación, `sudo docker ps` muestra:

- Menos contenedores de los esperados (deberían ser ~23)
- Algunos con estado `Restarting` o `Exited`
- Otros con `(unhealthy)`

### Diagnóstico

```bash
# Ver todos los contenedores (incluyendo los que han fallado)
sudo docker ps -a

# Ver logs de un contenedor problemático
sudo docker logs <nombre_contenedor> --tail 50

# Ver estado del servicio T-Pot
sudo systemctl status tpot --no-pager

# Ver uso de recursos
free -h
df -h /
```

### Causas y soluciones

| Causa | Solución |
|---|---|
| **RAM insuficiente** | Verificar `free -h`. Añadir swap o reducir perfil de T-Pot. |
| **Disco lleno** | `df -h /` → limpiar logs antiguos o ampliar disco. |
| **Contenedor con puerto ocupado** | `sudo ss -tlnp \| grep <PUERTO>` → matar el proceso que ocupa el puerto. |
| **Imagen corrupta** | `sudo docker pull ghcr.io/telekom-security/<imagen>:24.04.1` |
| **Dependencia caída** | Reiniciar el servicio: `sudo systemctl restart tpot` |

### Reiniciar T-Pot completo

```bash
# Parar todos los contenedores
sudo systemctl stop tpot

# Verificar que no queda ninguno
sudo docker ps

# Arrancar de nuevo
sudo systemctl start tpot

# Ver estado
sudo systemctl status tpot
```

### Verificar que arrancan todos

```bash
# Esperar 2-3 minutos tras el arranque
sleep 180

# Contar contenedores activos
sudo docker ps -q | wc -l
# Esperado: ~23
```

### Si un contenedor concreto falla siempre

```bash
# Ver su log detallado
sudo docker logs <nombre> --tail 100

# Probar arrancarlo manualmente
sudo docker start <nombre>

# Ver por qué murió
sudo docker inspect <nombre> | jq '.[0].State'
```

---

## 18. Agente en bucle "Never connected" por auto-enrollment

### Síntoma

En el manager:

```
ID: 003, Name: vps-tpot, IP: 100.112.220.3, Never connected
```

Y en el log del manager:

```
wazuh-authd: WARNING: Duplicate name 'vps-tpot', rejecting enrollment.
```

El agente está conectando cada 60s pero el manager lo rechaza una y otra vez.

### Causa

El agente tiene activado el **auto-enrollment**. Cuando la conexión inicial
falla (o se corta), el agente intenta registrarse de nuevo. Como ya existe
un agente con el mismo nombre, el manager rechaza el registro. Resultado:
bucle infinito.

### Diagnóstico

```bash
# En el manager — ¿hay duplicados?
sudo /var/ossec/bin/manage_agents -l

# En el manager — ¿qué dice el log?
sudo grep "Duplicate name" /var/ossec/logs/ossec.log | tail -5

# En el agente — ¿tiene clave?
sudo cat /var/ossec/etc/client.keys
```

### Solución

1. Eliminar el agente del manager (`manage_agents` → R).
2. Desactivar auto-enrollment en la VPS (`/var/ossec/etc/ossec.conf`):

```xml
<enrollment>
  <enabled>no</enabled>
</enrollment>
```

3. Borrar `client.keys` en la VPS:

```bash
sudo systemctl stop wazuh-agent
sudo rm -f /var/ossec/etc/client.keys
```

4. Re-registrar limpio en el manager:

```bash
sudo /var/ossec/bin/manage_agents
# A → vps-tpot → <VPS_IP> → y
# E → ID → COPIAR CLAVE
# Q
```

5. Importar la nueva clave en la VPS:

```bash
sudo /var/ossec/bin/manage_agents -i <NUEVA_CLAVE>
sudo systemctl start wazuh-agent
```

6. Verificar:

```bash
sudo /var/ossec/bin/agent_control -l
# ID: 003, Name: vps-tpot, IP: 100.112.220.3, Active
```

### Lección

Desactivar auto-enrollment al registrar agentes manualmente con clave
pre-compartida. Ver [Incidente 12](04-incidents.md#incidente-12-agente-en-bucle-never-connected-por-auto-enrollment).

---

## 19. Error de `cowrie.json` en el agente

### Síntoma

En el log del agente:

```
ERROR: (1103): Could not open file
'/home/tadmin/tpotce/data/cowrie/log/cowrie.json'
due to [(2)-(No such file or directory)].
```

### Causa

T-Pot 24.04.1 **no despliega Cowrie como contenedor independiente**. Los
honeypots SSH están dentro del contenedor `honeypots` y escriben en
`honeypots/log/ssh.log`, no en `cowrie.json`.

### Solución

1. Verificar qué logs de T-Pot existen realmente:

```bash
# En la VPS
sudo find /home/tadmin/tpotce/data -name "*.json" -o -name "*.log" 2>/dev/null | head -20
```

2. Eliminar el bloque `localfile` de `cowrie.json` de `/var/ossec/etc/ossec.conf`:

```xml
<!-- ELIMINAR este bloque -->
<localfile>
  <log_format>json</log_format>
  <location>/home/tadmin/tpotce/data/cowrie/log/cowrie.json</location>
</localfile>
```

3. Sustituirlo por el log correcto:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/home/tadmin/tpotce/data/honeypots/log/ssh.log</location>
</localfile>
```

4. Reiniciar el agente:

```bash
sudo systemctl restart wazuh-agent
```

5. Verificar que no hay errores:

```bash
sudo tail -20 /var/ossec/logs/ossec.log | grep -iE "error|analyzing"
```

### Lección

Verificar qué honeypots despliega cada versión de T-Pot antes de configurar
`localfiles`. Ver [Incidente 13](04-incidents.md#incidente-13-error-de-cowriejson--t-pot-no-usa-cowrie-en-esta-versión).

---

## 20. Mismatch de versión agente/manager

### Síntoma

El agente conecta (visible en `tcpdump`) y envía el handshake, pero el
manager cierra la conexión sin responder. En el log del agente:

```
Version detected -> ... Wazuh v4.14.9
```

Y en el manager:

```bash
dpkg -l | grep wazuh-manager
# wazuh-manager  4.14.8-1
```

### Causa

Diferencia de versión entre agente y manager. El agente es más reciente
que el manager, y el cambio de protocolo puede causar problemas de
handshake.

### Diagnóstico

```bash
# Versión del manager
dpkg -l | grep -E "wazuh-(manager|indexer|dashboard)" | awk '{print $2, $3}'

# Versión del agente (en la VPS)
dpkg -l | grep wazuh-agent | awk '{print $2, $3}'

# Versión reportada por el agente
sudo /var/ossec/bin/wazuh-control info | grep VERSION
```

### Solución

**Opción A — Actualizar el manager:**

```bash
# En el manager
sudo apt update
sudo apt upgrade wazuh-manager wazuh-indexer wazuh-dashboard -y
sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard
```

**Opción B — Degradar el agente:**

```bash
# En la VPS
sudo apt install --allow-downgrades wazuh-agent=4.14.8-1 -y
sudo systemctl restart wazuh-agent
```

### Verificación

```bash
# Ambos deben mostrar la misma versión
dpkg -l | grep wazuh
```

### Lección

Mantener agente y manager en la misma versión siempre que sea posible.
Ver [Incidente 14](04-incidents.md#incidente-14-mismatch-de-versión-agente-4149-vs-manager-4148).


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
- [Documentación oficial T-Pot](https://github.com/telekom-security/tpotce)
- [Tailscale](https://tailscale.com/)
- [Incidentes documentados](04-incidents.md)
- [Validación del agente](03-agent-validation.md)
- [Configuración de la VPS](06-vps-setup.md)
- [Instalación de T-Pot](07-tpot-installation.md)
- [Agente Wazuh en la VPS](08-wazuh-agent-vps.md)
