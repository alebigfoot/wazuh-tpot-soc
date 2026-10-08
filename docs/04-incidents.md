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
