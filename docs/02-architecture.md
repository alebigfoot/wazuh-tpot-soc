
# Arquitectura

## Estado actual (Fase 2 completada)

```
┌────────────────────────────────────────────┐         ┌────────────────────────────────────────────┐
│  VPS Contabo                               │         │  Manager local (VirtualBox)                │
│                                            │         │                                            │
│  IP pública: <VPS_IP>                      │         │  LAN: <LAN_IP>                             │
│  Tailscale:  <TAILSCALE_IP_VPS>            │◄────────┼─►Tailscale: <TAILSCALE_IP_MGR>             │
│                                            │  Direct │                                            │
│  Ubuntu 26.04 LTS                          │  P2P    │  Ubuntu 22.04 LTS                          │
│  4 vCPU · 8 GB RAM · 96 GB disco           │ cifrado │  8 vCPU · 8 GB RAM · 50 GB disco           │
│                                            │         │                                            │
│  ┌──────────────────────────────────────┐  │         │  ┌──────────────────────────────────────┐  │
│  │  T-Pot 24.04.1 (23 contenedores)     │  │         │  │  Wazuh Manager + Indexer             │  │
│  │  - Honeypots (SSH/HTTP/RDP/SIP)      │  │         │  │  Wazuh Dashboard                     │  │
│  │  - Dionaea (SMB/FTP/MSSQL)           │  │         │  │  Agente de prueba (agent-test)       │  │
│  │  - Suricata (IDS)                    │  │         │  └──────────────────────────────────────┘  │
│  │  - Conpot (SCADA/ICS)                │  │         │                                            │
│  │  - Dicompot, Medpot, otros...        │  │         │                                            │
│  └──────────────────────────────────────┘  │         │                                            │
│                                            │         │                                            │
│  ┌──────────────────────────────────────┐  │         │                                            │
│  │  Wazuh Agent (vps-tpot)              │  │         │                                            │
│  │  Estado: Active                      │  │         │                                            │
│  │  localfiles: logs de T-Pot           │  │         │                                            │
│  └──────────────────────────────────────┘  │         │                                            │
└────────────────────────────────────────────┘         └────────────────────────────────────────────┘
                     ▲
                     │  Ataques reales de Internet
                     │  (bots, escáneres, atacantes)
```

El pipeline está completamente operativo:

```
Internet → T-Pot → wazuh-agent → Tailscale → Wazuh Manager → Indexer → Dashboard
```

## Estado objetivo (Fases 3 y 4)

- **Fase 3 — Detección:** reglas custom para los ataques capturados por T-Pot
  (SSH, RDP, SIP, HTTP, SMB) con mapeo justificado a MITRE ATT&CK.
- **Fase 4 — Visualización y respuesta:** dashboards personalizados, Active
  Response y enriquecimiento de indicadores (VirusTotal, AbuseIPDB, OTX).

## Componentes

### Wazuh (manager local)

| Componente | Puerto | Función |
|---|---|---|
| Wazuh Manager | 1514, 1515, 55000 | Recepción de eventos, aplicación de reglas, API |
| Wazuh Indexer | 9200 (solo localhost) | Almacenamiento y búsqueda |
| Wazuh Dashboard | 443 | Interfaz web de análisis |
| Agente de prueba (`agent-test`) | — | Validación del pipeline (Fase 1) |

### T-Pot (VPS pública)

| Contenedor / Servicio | Función | Puertos típicos |
|---|---|---|
| `honeypots` (multi) | SSH, Telnet, HTTP, HTTPS, FTP, RDP, SIP, SMTP, POP3, IMAP, MySQL, MSSQL, PostgreSQL, Redis, VNC, Memcached, LDAP, y más | 21-23, 25, 53, 80, 110, 143, 443, 445, 1433, 1521, 3306, 3389, 5060, 5432, 5900, 6379, 11211 |
| `dionaea` | SMB, FTP, MSSQL | 445, 21, 1433 |
| `suricata` | IDS / análisis de tráfico | — |
| `conpot_*` | Honeypots industriales (SCADA/ICS) | 161, 623, 1025, 2404, 50100, 10001 |
| `dicompot` | DICOM (médico) | 104, 11112 |
| `medpot` | HL7 (médico) | 2575 |
| `ciscoasa` | Cisco ASA (VPN) | 5000, 8443 |
| `adbhoney` | Android Debug Bridge | 5555 |
| `spiderfoot` | OSINT / threat intelligence | — |
| `honeytrap` | Honeypot genérico | varios |
| `p0f`, `fatt` | Passive fingerprinting | — |
| `elasticsearch`, `logstash`, `kibana` | Stack ELK para análisis | 64296 (Kibana interno), 64298 (ES interno) |
| `nginx` | Reverse proxy del panel | 64294, 64297 |
| `map_*`, `ewsposter` | Mapa de atacantes y envío a EWS | — |

### Wazuh Agent (VPS)

| Componente | Función |
|---|---|
| `wazuh-agent` (`vps-tpot`) | Envía los logs de T-Pot al manager vía Tailscale (puerto 1514) |

## Flujo de datos

1. Un atacante contacta con un servicio del honeypot en la VPS.
2. T-Pot captura la interacción y genera logs en
   `/home/tadmin/tpotce/data/<honeypot>/log/*.json` o `.log`.
3. El agente Wazuh de la VPS (`vps-tpot`) lee esos ficheros mediante `localfiles`:
   - `dionaea.json` (Dionaea)
   - `eve.json` (Suricata)
   - `honeypots/log/ssh.log`, `http.log`, `rdp.log`, `sip.log` (multi-honeypot)
4. El agente envía los eventos al manager por el túnel Tailscale (puerto 1514).
5. El manager aplica decoders y reglas.
6. Los eventos se indexan en Wazuh Indexer.
7. El dashboard los muestra en **Threat Hunting**, **Security Events** y
   **MITRE ATT&CK**.

## Decisiones de diseño

- **Instalación Wazuh todo-en-uno:** para un lab personal con recursos
  limitados, un solo nodo simplifica la operación. Ver
  [ADR 0001](adr/0001-instalacion-todo-en-uno.md).
- **T-Pot en VPS pública:** el honeypot necesita exponerse a Internet para
  recibir tráfico real; hacerlo en la red doméstica sería inseguro.
- **Tailscale en lugar de WireGuard directo:** no hay acceso al panel del
  router para abrir puertos UDP, y Tailscale funciona detrás de CGNAT.
  Ver [ADR 0002](adr/0002-tailscale-sobre-wireguard.md).
- **Agente Wazuh separado del manager:** nunca en el mismo host (ver
  [Incidente 1](04-incidents.md#incidente-1-wazuh-agent-destruye-wazuh-manager-al-instalarse-en-el-mismo-host)).

## Documentación relacionada

- [Instalación de Wazuh](01-installation.md)
- [Configuración de la VPS](06-vps-setup.md)
- [Instalación de T-Pot](07-tpot-installation.md)
- [Agente Wazuh en la VPS](08-wazuh-agent-vps.md)
- [Incidentes documentados](04-incidents.md)
- [Troubleshooting](05-troubleshooting.md)

## Referencias

- [Documentación Wazuh](https://documentation.wazuh.com/)
- [T-Pot en GitHub](https://github.com/telekom-security/tpotce)
- [Tailscale](https://tailscale.com/)

