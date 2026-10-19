# Validación del pipeline con agente en VM separada

## Contexto

Tras el Incidente 1 (`wazuh-agent` sobrescribe `wazuh-manager` en el mismo
host), se monta el agente en una **máquina virtual separada** siguiendo la
arquitectura correcta.

## Arquitectura de la prueba

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│  VM 1: manager              │         │  VM 2: agente               │
│  192.168.56.103             │◄────────│  192.168.56.104             │
│                             │  :1514  │                             │
│  Wazuh Manager              │  :1515  │  Wazuh Agent (v4.14.8)      │
│  Wazuh Indexer              │         │                             │
│  Wazuh Dashboard            │         │  Ubuntu 22.04 minimal       │
│                             │         │  2 GB RAM / 20 GB disco     │
└─────────────────────────────┘         └─────────────────────────────┘
```

Ambas VMs comparten un adaptador Host-Only (`192.168.56.0/24`) para
comunicarse internamente.

## Pasos ejecutados

### 1. Verificar conectividad

```bash
# Desde el agente
ping -c 3 192.168.56.103
```

### 2. Registrar el agente en el manager

En el manager:

```bash
sudo /var/ossec/bin/manage_agents
# A → Add agent
#   Name: agent-test
#   IP: 192.168.56.104
# E → Extract key for agent 001
# Q → Quit
```

### 3. Instalar el agente en la segunda VM

En el agente:

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  gpg --dearmor | sudo tee /usr/share/keyrings/wazuh.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | \
  sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt update

sudo WAZUH_MANAGER='192.168.56.103' \
     WAZUH_AGENT_NAME='agent-test' \
     apt install -y wazuh-agent
```

### 4. Importar la clave

```bash
sudo /var/ossec/bin/manage_agents -i <CLAVE>
```

### 5. Arrancar el servicio

```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

### 6. Verificar

En el manager:

```bash
sudo /var/ossec/bin/agent_control -l
```

Salida:

```
Wazuh agent_control. List of available agents:
   ID: 000, Name: soc-VirtualBox (server), IP: 127.0.0.1, Active/Local
   ID: 001, Name: agent-test, IP: 192.168.56.104, Active
```

## Evidencia

### Agente activo en el dashboard

![Agents active](diagrams/agents-active.png)

*El agente `agent-test` aparece como Active en la vista de Agents.*

### Eventos recibidos por el manager

![Security events](diagrams/security-events.png)

*216 eventos del agente `agent-test` (SCA, FIM, syslog) en Discover,
filtrados por `agent.name: "agent-test"`.*

### Overview con el agente conectado

![Dashboard overview](diagrams/dashboard-overview.png)

*El panel principal muestra "Active (1)" en Agents Summary.*

## Eventos generados para prueba

| Tipo | Origen | Módulo |
|---|---|---|
| Modificación de fichero | `/etc/test-*.txt` | FIM |
| Cambio de permisos | `/etc/test-*.txt` | FIM |
| Login fallido | usuario_falso | Syslog |
| Auditoría de configuración | automático | SCA |

## Resultado

El pipeline funciona correctamente:

- El agente se registra y aparece como **Active** en el manager.
- Los eventos llegan al manager a través del puerto 1514.
- El dashboard muestra los eventos en tiempo real.
- Se han capturado **216 eventos** generados por el agente.

**Fase 1 completada.** La Fase 2 (T-Pot en VPS) está documentada en
[`07-tpot-installation.md`](07-tpot-installation.md) y
[`08-wazuh-agent-vps.md`](08-wazuh-agent-vps.md).

## Lección aprendida

Aplicando la lección del Incidente 1, el agente se ha desplegado en una
VM separada del manager. Esto:

- Evita el conflicto de binarios.
- Refleja la arquitectura real de producción.
- Prepara el despliegue del agente en la VPS de la Fase 2.
