# Incidencias y resolución

Registro de problemas reales encontrados durante la construcción del laboratorio
y de cómo se resolvieron. Los errores documentados valen más que el camino
feliz: demuestran criterio técnico y capacidad de diagnóstico.

---

## Índice

1. [Wazuh agent destruye Wazuh manager al instalarse en el mismo host](#incidente-1-wazuh-agent-destruye-wazuh-manager-al-instalarse-en-el-mismo-host)
2. [Dashboard roto tras reinstalar el manager (403 + version_conflict)](#incidente-2-dashboard-roto-tras-reinstalar-el-manager-403--version_conflict)
3. [Manager no arranca por timeout de systemd](#incidente-3-manager-no-arranca-por-timeout-de-systemd)
4. [Locks huérfanos tras timeout](#incidente-4-locks-huérfanos-tras-timeout)
5. [Indexer no arranca por timeout de systemd](#incidente-5-indexer-no-arranca-por-timeout-de-systemd)
6. [DNS roto tras cambiar adaptador de red en VirtualBox](#incidente-6-dns-roto-tras-cambiar-adaptador-de-red-en-virtualbox)
7. [Tailscale — autenticación por URL no sincroniza](#incidente-7-tailscale--autenticación-por-url-no-sincroniza)
8. [Sesión de Tailscale caduca entre sesiones SSH](#incidente-8-sesión-de-tailscale-caduca-entre-sesiones-ssh)
9. [T-Pot rechaza Ubuntu 24.04 — requiere 26.04](#incidente-9-t-pot-rechaza-ubuntu-2404--requiere-2604)
10. [T-Pot no se puede instalar desde root](#incidente-10-t-pot-no-se-puede-instalar-desde-root)
11. [Manager sin clave SSH — no se puede autenticar por clave](#incidente-11-manager-sin-clave-ssh--no-se-puede-autenticar-por-clave)
12. [Agente en bucle "Never connected" por auto-enrollment](#incidente-12-agente-en-bucle-never-connected-por-auto-enrollment)
13. [Error de `cowrie.json` — T-Pot no usa Cowrie en esta versión](#incidente-13-error-de-cowriejson--t-pot-no-usa-cowrie-en-esta-versión)
14. [Mismatch de versión agente (4.14.9) vs manager (4.14.8)](#incidente-14-mismatch-de-versión-agente-4149-vs-manager-4148)
15. [Manager no arranca por `Field 'protocol' is static`](#incidente-15-manager-no-arranca-por-field-protocol-is-static)
16. [Reglas custom no disparan sin `<if_sid>`](#incidente-16-reglas-custom-no-disparan-sin-if_sid)
---
---
## Incidente 1: Wazuh agent destruye Wazuh manager al instalarse en el mismo host

**Fecha:** 2026-10-08

### Síntoma

Tras ejecutar `apt install wazuh-agent` en la misma máquina donde corría
`wazuh-manager`:

- El servicio `wazuh-manager` desapareció:
  `Unit wazuh-manager.service could not be found`.
- El paquete `wazuh-manager` quedó marcado como `rc` en `dpkg -l`
  (removed, config remaining).
- Los binarios del manager en `/var/ossec/bin/` (`agent_control`,
  `wazuh-remoted`, `wazuh-analysisd`, etc.) desaparecieron, sustituidos por
  los del agente (`wazuh-agentd`, `wazuh-execd`, etc.).

### Causa

Los paquetes `wazuh-manager` y `wazuh-agent` **comparten rutas**
(`/var/ossec/`), usuario (`wazuh`) y algunos binarios con el mismo nombre
(`manage_agents`, `wazuh-control`). Al instalar el agente, `apt` detecta un
conflicto con `wazuh-manager` y lo **desinstala automáticamente**, dejando
la configuración en `/var/ossec/etc/`.

### Solución aplicada

```bash
# 1. Desinstalar el agente
sudo systemctl stop wazuh-agent
sudo systemctl disable wazuh-agent
sudo apt remove --purge wazuh-agent -y
sudo apt autoremove -y

# 2. Reinstalar el manager conservando la configuración
sudo apt update
sudo apt install --reinstall wazuh-manager -y

# 3. Arrancar y verificar
sudo systemctl daemon-reload
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager
```

Tras esto, los binarios del manager volvieron a `/var/ossec/bin/` y el
servicio arrancó correctamente.

### Lección

**Nunca instalar `wazuh-agent` en el mismo host donde corre `wazuh-manager`.**

Regla general:

- **Producción:** agente y manager en máquinas distintas.
- **Laboratorio:** si no hay más remedio, usar contenedores Docker para
  aislar agentes, o una VM separada exclusivamente para agentes de prueba.

---

## Incidente 2: Dashboard roto tras reinstalar el manager (403 + version_conflict)

**Fecha:** 2026-10-08

### Síntoma

Tras recuperar el manager (Incidente 1), el dashboard mostraba:

- `[API connection] No API available to connect`
- `[Alerts index pattern] version conflict, document already exists`
- `[Statistics index pattern] version conflict, document already exists`

Además, los logs del dashboard mostraban en bucle:

```
{"tags":["error","plugins","wazuh","monitoring"],
 "message":"Request failed with status code 403"}
```

### Causa

Al reinstalar `wazuh-manager` se regeneraron las credenciales internas y la
configuración del plugin Wazuh del dashboard quedó desincronizada:

1. El índice `.kibana_1` mantenía *index-patterns* huérfanos con IDs que
   colisionaban con los que el dashboard intentaba crear.
2. El fichero `wazuh.yml` del plugin seguía apuntando a credenciales antiguas
   (por defecto `wazuh-wui`), que la nueva API rechazaba con
   **403 Forbidden**.

### Solución aplicada

**Parte A — Reset del índice del dashboard:**

```bash
sudo systemctl stop wazuh-dashboard

# Backup antes de borrar
curl -sk -u admin:<PASSWORD> \
  "https://localhost:9200/.kibana_1/_search?pretty&size=100" \
  > ~/kibana1-backup.json

# Borrar índices
curl -sk -X DELETE -u admin:<PASSWORD> "https://localhost:9200/.kibana_1"
curl -sk -X DELETE -u admin:<PASSWORD> "https://localhost:9200/.kibana_2"

# Limpiar caché en disco
sudo rm -rf /usr/share/wazuh-dashboard/data/

sudo systemctl start wazuh-dashboard
sleep 120
```

**Parte B — Corregir credenciales del plugin:**

```bash
sudo nano /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
```

Contenido correcto:

```yaml
hosts:
  - default:
      url: https://localhost
      port: 55000
      username: wazuh
      password: wazuh
      run_as: false
```

```bash
sudo chown wazuh-dashboard:wazuh-dashboard \
  /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
sudo chmod 600 /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
sudo systemctl restart wazuh-dashboard
```

Tras esto:

- El plugin regeneró `.kibana_1` con sus 20+ documentos.
- Los errores `403` desaparecieron de los logs.
- El dashboard mostró los 6 módulos de Wazuh operativos.

### Lección

Tras cualquier operación que **regenera credenciales del manager**
(reinstall, cambio de contraseñas, restauración desde backup):

1. Verificar que la API responde manualmente:
   ```bash
   curl -k -u wazuh:wazuh https://localhost:55000/
   ```
2. Revisar y actualizar el fichero `wazuh.yml` del plugin Wazuh del dashboard.
3. Si hay errores de `version_conflict` en la UI, resetear `.kibana_*`.

---

## Incidente 3: Manager no arranca por timeout de systemd

**Fecha:** 2026-10-12

### Síntoma

Tras la recuperación del Incidente 1, `systemctl status wazuh-manager` mostraba:

```
Active: failed (Result: timeout)
Failed to start Wazuh manager.
```

Los demonios arrancaban (`authd`, `db`, `execd`, `analysisd`) pero systemd
mataba el servicio antes de completar el arranque.

### Causa

`wazuh-analysisd` tarda ~35-40 segundos en cargar las 8451 reglas por
defecto. El `TimeoutStartSec` por defecto de systemd es insuficiente en
entornos virtualizados.

### Solución aplicada

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

### Lección

Ampliar `TimeoutStartSec` en hosts virtualizados con recursos limitados.
Verificar siempre con `systemctl show wazuh-manager | grep -i timeout`.

---

## Incidente 4: Locks huérfanos tras timeout

**Fecha:** 2026-10-12

### Síntoma

Tras varios arranques fallidos del manager, intentar arrancarlo de nuevo:

```
ERROR: Another instance is locking...ess.
If you are sure that no other ins[tance]...lock
```

### Causa

Cuando systemd mata el servicio por timeout, los demonios internos quedan
huérfanos y dejan ficheros `.pid` en `/var/ossec/var/run/`. En el siguiente
intento, los nuevos procesos ven esos `.pid` y creen que ya hay otro manager
corriendo.

### Solución aplicada

```bash
# Confirmar que no hay procesos Wazuh vivos
ps -ef | grep -iE "wazuh|ossec" | grep -v grep

# Borrar todos los locks
sudo find /var/ossec/var/run/ -name "*.pid" -delete

# Arrancar limpio
sudo systemctl start wazuh-manager
```

### Lección

Consecuencia directa del Incidente 3. Si el manager falla al arrancar con
"Another instance is locking", limpiar `/var/ossec/var/run/*.pid` tras
confirmar que no hay procesos vivos.

---

## Incidente 5: Indexer no arranca por timeout de systemd

**Fecha:** 2026-10-12

### Síntoma

El Indexer quedaba en estado `failed (Result: timeout)` tras reinicios.
El dashboard mostraba:

```
[ConnectionError]: connect ECONNREFUSED 127.0.0.1:9200
Wazuh dashboard server is not ready yet
```

El puerto 9200 no estaba escuchando aunque el servicio dijera `active`.

### Causa

OpenSearch tarda >90s en arrancar en VMs con recursos limitados,
especialmente cuando tiene que recuperar índices tras una caída brusca.
Mismo problema que el Incidente 3 pero con otro componente.

### Solución aplicada

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

### Lección

**Aplicar el mismo override a TODOS los servicios Wazuh que tarden en
arrancar.** Manager e Indexer necesitan más de 90s en este laboratorio.
Dejarlos por defecto es una fuente constante de falsos `failed`.

Verificación:

```bash
sudo systemctl show wazuh-indexer | grep -i timeout
# TimeoutStartUSec=10min
```
---

## Incidente 6: DNS roto tras cambiar adaptador de red en VirtualBox

**Fecha:** 2026-10-13

### Síntoma

Tras cambiar el adaptador de red de la VM del manager de **Host-Only** a
**Adaptador Puente**, la máquina obtenía IP por DHCP correctamente
(`192.168.1.141`) pero **la resolución DNS fallaba**:

```
$ dig google.com
;; communications error to 127.0.0.53#53: timed out
;; no servers could be reached
```

El `ping` a IPs directas (`9.9.9.9`, `1.1.1.1`) funcionaba, pero los
nombres no se resolvían.

### Causa

Cadena de eventos:

1. Al cambiar el adaptador, NetworkManager tomó el control de la interfaz.
2. **Tailscale** arrancó y sobrescribió los DNS de `enp0s8` con los suyos
   (`100.90.1.1`, `100.100.1.1`), que están dentro de la red Tailscale.
3. Como solo había 1 dispositivo en el tailnet (el propio manager), esos
   DNS no tenían upstream utilizable y devolvían timeout.
4. `systemd-resolved` mostraba `127.0.0.53` como stub, pero el upstream
   real era el DNS de Tailscale, que no resolvía.

### Solución aplicada

**Parte A — Configurar DNS manual con NetworkManager:**

```bash
# Ver la conexión activa
nmcli connection show --active

# Configurar DNS y deshabilitar los auto-DNS
sudo nmcli connection modify <UUID> \
  ipv4.dns "9.9.9.9,1.1.1.1,8.8.8.8" \
  ipv4.ignore-auto-dns yes

# Aplicar
sudo nmcli connection down <UUID>
sudo nmcli connection up <UUID>
```

**Parte B — Desactivar el DNS de Tailscale:**

```bash
sudo tailscale set --accept-dns=false
# (o, según versión: sudo tailscale up --accept-dns=false)
```

**Parte C — Arreglar permisos de netplan** (warning relacionado):

```bash
sudo chmod 600 /etc/netplan/*.yaml
```

### Lección

- **Tailscale por defecto secuestra el DNS.** En un lab de un solo nodo
  es contraproducente. Siempre usar `--accept-dns=false`.
- Al cambiar de red (bridge, host-only, NAT), **verificar el DNS** es tan
  importante como verificar la IP.
- `resolvectl status` es el comando clave para diagnosticar problemas de DNS
  en Ubuntu moderno.

---

## Incidente 7: Tailscale — autenticación por URL no sincroniza

**Fecha:** 2026-10-14

### Síntoma

Al autenticar una VPS en Tailscale con el flujo estándar:

```bash
sudo tailscale up --accept-dns=false
```

El comando mostraba una **URL de autenticación**:

```
To authenticate, visit:
https://login.tailscale.com/a/xxxxxxxxxxxx
```

Y se quedaba esperando. Tras abrir la URL en el navegador, autenticarse
con la cuenta correcta y pulsar "Connect" en el panel web:

- La VPS aparecía en `https://login.tailscale.com/admin/machines`
- **Pero la terminal seguía diciendo `Logged out`**
- `tailscale status` seguía mostrando "Log in at: <URL>"

### Causa

El proceso `tailscale up` en la VPS **no recibió la confirmación del servidor**
de Tailscale. Posibles motivos:

1. La URL de autenticación **caduca en 10-15 minutos**. Si tardas más, expira.
2. Si el navegador tiene auto-login con **otra cuenta** distinta a la del
   manager, la autorización se registra en el dispositivo equivocado.
3. El proceso `tailscale up` puede quedar colgado esperando indefinidamente
   si el evento de confirmación se pierde (raro, pero ocurre).

### Solución aplicada

Usar **auth keys** en lugar del flujo por URL:

1. En el panel: `https://login.tailscale.com/admin/settings/keys`
2. **Generate auth key...** con:
   - Reusable: ✅
   - Ephemeral: ❌
   - Pre-approved: ✅
   - Expiration: 90 días
3. Copiar la key (`tskey-auth-...`).
4. En la VPS:

```bash
tailscale logout
tailscale up --authkey=tskey-auth-XXXXXXXXX --accept-dns=false
```

Resultado: autenticación **instantánea**, sin navegador, sin URLs caducables.

### Lección

- **Para servidores y automatización, usar auth keys**, no el flujo por URL.
- Las URLs de Tailscale caducan rápido y dependen del navegador.
- Las auth keys se pueden revocar en cualquier momento desde el panel.
- Etiquetar las keys con un nombre descriptivo (`vps-contabo`, `lab-manager`…)
  facilita gestionarlas.

---

## Incidente 8: Sesión de Tailscale caduca entre sesiones SSH

**Fecha:** 2026-10-14

### Síntoma

Al reconectar por SSH a la VPS después de un rato, `tailscale status`
reportaba:

```
Logged out.
Log in at: https://login.tailscale.com/a/xxxxxxxxxxxx
```

Pero la VPS aparecía correctamente en el panel de administración de
Tailscale, con IP asignada.

### Causa

Estado inconsistente entre el **control plane** (servidores de Tailscale)
y el **cliente local** (`tailscaled` en la VPS):

- El panel mostraba el dispositivo porque estaba registrado
- El cliente local no había persistido correctamente el token de sesión

Suele pasar cuando:

- La autenticación inicial no termina de sincronizar
- El estado en `/var/lib/tailscale/tailscaled.state` queda corrupto
- Hay conflictos con otras sesiones previas de `tailscale up`

### Solución aplicada

1. Cerrar cualquier proceso `tailscale up` colgado:

```bash
pkill -f "tailscale up"
```

2. Reiniciar el servicio:

```bash
systemctl restart tailscaled
sleep 5
```

3. Autenticar con auth key (evita todo el ciclo de URLs):

```bash
tailscale logout
tailscale up --authkey=tskey-auth-XXX --accept-dns=false
```

4. Verificar:

```bash
tailscale status
# 100.x.y.z  vmi3664658  user@  linux  -
# 100.x.y.z  soc-virtualbox  user@  linux  active; direct ...
```

### Lección

- El estado de Tailscale se guarda en `/var/lib/tailscale/tailscaled.state`.
- Si hay inconsistencias, `systemctl restart tailscaled` suele resolver.
- **Auth keys > URLs** para cualquier operación que deba ser reproducible.
- Verificar con `tailscale status` antes de dar por buena la conexión.

---

## Incidente 9: T-Pot rechaza Ubuntu 24.04 — requiere 26.04

**Fecha:** 2026-10-14

### Síntoma

Al lanzar el instalador de T-Pot en una VPS con Ubuntu 24.04, el script
aborta inmediatamente con:

```
### T-Pot supports Ubuntu 26.04, this system runs 24.04.
### Please install T-Pot on the current release of your distribution.
```

### Causa

La versión actual de T-Pot (24.04.1) **solo soporta la LTS más reciente
de Ubuntu**. Las versiones anteriores de T-Pot aceptaban también 22.04 y
24.04, pero la actual ha endurecido este requisito.

### Solución aplicada

Actualizar la VPS a Ubuntu 26.04:

```bash
# Actualizar paquetes actuales
sudo apt update && sudo apt upgrade -y

# Actualizar la distribución (tarda ~45 min)
sudo do-release-upgrade
```

Tras el reinicio:

```bash
lsb_release -rs
# 26.04
```

Y reintentar el instalador de T-Pot.

### Lección

- **Verificar los requisitos del sistema antes de instalar**. La página
  del proyecto o el `README` suele indicar la versión soportada.
- T-Pot es estricto con las versiones: seguir la más reciente del
  fabricante evita problemas.
- Antes de hacer `do-release-upgrade`, **hacer un snapshot** de la VPS
  desde el panel del proveedor.

---

## Incidente 10: T-Pot no se puede instalar desde root

**Fecha:** 2026-10-14

### Síntoma

Al ejecutar el instalador con `sudo`:

```bash
sudo ./install.sh -t i -u tadmin -p 'PASS'
```

El script aborta con:

```
This script should not be run as root. Please run it as a regular user.
```

### Causa

El instalador de T-Pot comprueba el UID del usuario actual:

```bash
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run as root. Please run it as a regular user."
  exit 1
fi
```

Cuando se ejecuta con `sudo`, `id -u` devuelve `0` (root), y el script
aborta por diseño.

El motivo es que T-Pot hace cambios profundos en el sistema (usuarios,
SSH, firewall) y quiere hacerlo desde un contexto controlado, no desde
root directo.

### Solución aplicada

Crear primero un usuario normal con permisos sudo:

```bash
sudo adduser tadmin
sudo usermod -aG sudo tadmin
```

Añadir la clave SSH pública al usuario:

```bash
cat ~/.ssh/id_ed25519.pub | ssh tadmin@<VPS_IP> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Conectar como `tadmin` y ejecutar el instalador **sin `sudo`**:

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP>
cd ~/tpotce
./install.sh -t i -u tadmin -p '<PASSWORD>'
```

El propio script solicitará `sudo` internamente cuando lo necesite.

### Lección

- Algunos instaladores **rechazan ejecutarse como root** por diseño. Es
  una medida de seguridad que evita errores difíciles de revertir.
- Si un script comprueba el UID, **leer su documentación** para saber
  cómo debe ejecutarse.
- Truco para evitar meter la contraseña muchas veces:
  ```bash
  sudo -v              # refresca el timestamp de sudo
  ./install.sh ...     # ejecuta sin sudo (usa el timestamp anterior)
  ```

---

## Incidente 11: Manager sin clave SSH — no se puede autenticar por clave

**Fecha:** 2026-10-14

### Síntoma

Al intentar conectar desde el manager a la VPS por clave SSH:

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP>
```

El comando falla con:

```
Warning: Identity file /home/soc/.ssh/id_ed25519 not accessible: No such file or directory.
tadmin@<VPS_IP>'s password:
```

Es decir: **la clave no existe** y hay que autenticarse por contraseña.

### Causa

En el manager **nunca se había generado una clave SSH**. El directorio
`~/.ssh/` solo contenía:

- `known_hosts` (registro de servidores visitados)
- `known_hosts.old`

Sin claves, todos los comandos con `-i ~/.ssh/id_ed25519` fallan y el
sistema cae al método alternativo (contraseña).

### Solución aplicada

Generar la clave:

```bash
ssh-keygen -t ed25519 -C "soc-manager" -f ~/.ssh/id_ed25519
```

(Pulsar Enter dos veces para no poner passphrase en un lab.)

Verificar:

```bash
ls -la ~/.ssh/
# id_ed25519
# id_ed25519.pub
```

Y añadir la clave pública a los usuarios de la VPS:

```bash
cat ~/.ssh/id_ed25519.pub | ssh tadmin@<VPS_IP> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

cat ~/.ssh/id_ed25519.pub | ssh root@<VPS_IP> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Verificar conexión sin contraseña:

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP> "hostname"
```

### Lección

- **Generar una clave SSH al preparar cualquier entorno nuevo.** Es un
  paso trivial pero se olvida con frecuencia.
- Sin clave pública, cualquier automatización que dependa de SSH se
  bloquea pidiendo contraseña interactiva.
- El directorio `~/.ssh/` con solo `known_hosts` indica claramente que
  nunca se ha generado clave en ese host.

---

## Incidente 12: Agente en bucle "Never connected" por auto-enrollment

**Fecha:** 2026-10-19

### Síntoma

El agente aparecía como `Never connected` aunque:

- Ping al manager funcionaba.
- Puerto 1514 respondía (`nc -zv` succeeded).
- La clave en `client.keys` era idéntica en ambos extremos.
- El log del agente mostraba `Trying to connect` cada 60s.

En el log del manager aparecía:

```
wazuh-authd: WARNING: Duplicate name 'vps-tpot', rejecting enrollment.
```

### Causa

El agente tenía activado el auto-enrollment. Como ya existía un agente con el
mismo nombre, el manager rechazaba el registro. Resultado: bucle infinito.

### Solución aplicada

1. Eliminar el agente del manager (`manage_agents` → R).
2. Desactivar auto-enrollment en la VPS (`/var/ossec/etc/ossec.conf`).
3. Borrar `client.keys` en la VPS.
4. Re-registrar limpio en el manager y copiar nueva clave.
5. Importar nueva clave en la VPS y arrancar.
6. Verificar que aparece `Active`.

### Lección

Desactivar auto-enrollment al registrar agentes manualmente con clave pre-compartida.

---

## Incidente 13: Error de `cowrie.json` — T-Pot no usa Cowrie en esta versión

**Fecha:** 2026-10-19

### Síntoma

```
ERROR: (1103): Could not open file
'/home/tadmin/tpotce/data/cowrie/log/cowrie.json'
due to [(2)-(No such file or directory)].
```

### Causa

T-Pot 24.04.1 no despliega Cowrie como contenedor independiente. Los honeypots
SSH van dentro del contenedor `honeypots` y escriben en `ssh.log`.

### Solución aplicada

Eliminar el bloque `localfile` de `cowrie.json` y usar
`honeypots/log/ssh.log` en su lugar.

### Lección

Verificar qué honeypots despliega cada versión de T-Pot antes de configurar
`localfiles`.

---

## Incidente 14: Mismatch de versión agente (4.14.9) vs manager (4.14.8)

**Fecha:** 2026-10-19

### Síntoma

El agente conectaba (visible en `tcpdump`) y enviaba el handshake, pero el
manager cerraba la conexión sin responder. El log del agente mostraba
`Version detected -> Wazuh v4.14.9`, mientras el manager estaba en `4.14.8`.

### Causa

Diferencia de versión entre agente y manager. El agente era más reciente que
el manager, y el cambio de protocolo podía causar problemas de handshake.

### Solución aplicada

Actualizar el manager a la misma versión que el agente (`4.14.9`) o degradar
el agente a `4.14.8`.

### Lección

Mantener agente y manager en la misma versión siempre que sea posible.

---

## Incidente 15: Manager no arranca por `Field 'protocol' is static`

**Fecha:** 2026-10-26

### Síntoma

Tras crear una regla custom en `local_rules.xml`, el manager no arrancaba:

```
wazuh-analysisd: ERROR: Failure to read rule 100014. Field 'protocol' is static.
wazuh-analysisd: CRITICAL: (1220): Error loading the rules: 'etc/rules/local_rules.xml'.
Failed to start wazuh-manager.service.
```

### Causa

En la regla custom se usaba el campo `protocol` directamente:

```xml
<field name="protocol">ssh</field>
```

Pero `protocol` es un campo **reservado** del sistema de decodificación de
Wazuh. No se puede usar como nombre de campo en una regla.

### Solución aplicada

Usar `data.protocol` en lugar de `protocol`:

```xml
<field name="data.protocol">ssh</field>
```

Y reiniciar el manager:

```bash
sudo systemctl restart wazuh-manager
```

### Lección

Algunos nombres de campo son reservados en Wazuh (`protocol`, `action`, `id`,
`status`, etc.). Si una regla no carga con el error `Field 'X' is static`,
usar `data.X` o renombrar el campo.

---

## Incidente 16: Reglas custom no disparan sin `<if_sid>`

**Fecha:** 2026-10-26

### Síntoma

Las reglas custom se cargaban correctamente (el contador de reglas
aumentaba) pero **no disparaban** con los eventos reales. Al probar con
`wazuh-logtest`:

```
**Phase 3: Completed filtering (rules).
    id: '86600'                    ← la regla por defecto de Suricata
    description: 'Suricata messages.'
```

En lugar de:

```
    id: '100010'
    description: 'T-Pot/Suricata: SNMP scan desde 141.153.237.4...'
```

### Causa

Wazuh evalúa las reglas en orden jerárquico. Las reglas del ruleset base
(como `86600` para Suricata) tienen prioridad y **consumen el evento**
antes de que llegue a las reglas custom.

Sin `<if_sid>`, las reglas custom nunca se evalúan para eventos que ya
coinciden con una regla base.

### Solución aplicada

Añadir `<if_sid>` con el ID de la regla base que procesa el evento:

```xml
<rule id="100010" level="7">
  <if_sid>86600</if_sid>
  <field name="event_type">snmp</field>
  <field name="snmp.community">public</field>
  <description>T-Pot/Suricata: SNMP scan desde $(data.src_ip) con community public</description>
  <mitre>
    <id>T1046</id>
  </mitre>
</rule>
```

Esto indica a Wazuh: *"cuando la regla 86600 haya disparado, evalúa también
esta regla si se cumple la condición adicional"*.

### Verificación

```bash
sudo /var/ossec/bin/wazuh-logtest
# Pegar el JSON de SNMP
```

Salida esperada:

```
**Phase 3: Completed filtering (rules).
    id: '100010'
    level: '7'
    description: 'T-Pot/Suricata: SNMP scan desde 141.153.237.4 con community public'
    mitre.id: ['T1046']
```

### Lección

En Wazuh, las reglas custom que operan sobre un decoder específico
(Suricata, JSON, Syslog, etc.) **necesitan `<if_sid>`** con el ID de la
regla base. Sin él, el evento no llega a la regla custom.

Referencia: [Documentación de Wazuh sobre `if_sid`](https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html)


## Plantilla para próximos incidentes

```markdown
## Incidente N: <título corto>

**Fecha:** YYYY-MM-DD

### Síntoma
<qué se observa>

### Causa
<por qué ocurre>

### Solución aplicada
<comandos y pasos concretos>

### Lección
<qué hacer para no repetirlo>
```
