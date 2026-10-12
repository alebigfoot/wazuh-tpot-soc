# Incidencias y resolución

Registro de problemas reales encontrados durante la construcción del laboratorio
y de cómo se resolvieron. Los errores documentados valen más que el camino
feliz: demuestran criterio técnico y capacidad de diagnóstico.

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
