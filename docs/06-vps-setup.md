# Configuración inicial de la VPS (Contabo)

Documentación del aprovisionamiento y preparación de la VPS pública donde
se desplegará TPOT (honeypot) en la Fase 2.

> **Nota sobre privacidad:** las IPs, hostnames y datos identificativos reales
> están sustituidos por placeholders (`<VPS_IP>`, `<TAILSCALE_IP_VPS>`, etc.)
> para poder publicar este documento en un repositorio público.

## Proveedor

**Contabo** — Cloud VPS contratado específicamente para este laboratorio.

### Especificaciones

| Recurso | Valor |
|---|---|
| Hostname | `<VPS_HOSTNAME>` |
| SO | Ubuntu 26.04 LTS (tras upgrade desde 24.04 por requisito de T-Pot) |
| Kernel | 6.8.0-147-generic |
| CPU | 4 vCPU |
| RAM | 7.8 GB |
| Swap | 4 GB (creado manualmente) |
| Disco | 96 GB (90 GB libres) |
| IPv4 pública | `<VPS_IP>` |
| IPv6 pública | `<VPS_IPV6>` |
| Tailscale IP | `<TAILSCALE_IP_VPS>` |

### Motivos para elegir Contabo

- **Tráfico ilimitado** → clave para un honeypot expuesto a Internet
- Precio competitivo (~€5-7/mes según plan)
- Permite honeypots siempre que no se abuse
- 4 ubicaciones en Europa (Alemania, UK, US…)
- Buena relación precio/recursos

## Preparación inicial

### 1. Conexión por SSH

Contabo entrega las credenciales iniciales por email:

```bash
ssh root@<VPS_IP>
```

En el primer login, fuerza el cambio de contraseña de root.

### 2. Creación de swap

La VPS viene sin swap por defecto. Con 8 GB de RAM puede ser insuficiente
para TPOT durante las fases de arranque de todos los contenedores.

```bash
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Ajustar swappiness
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Verificación:

```bash
free -h
# Swap: 4,0Gi
```

### 3. Actualización del sistema

```bash
apt update && apt upgrade -y
```

Se aplicó un kernel nuevo y se requirió reinicio.

### 4. Instalación de herramientas base

```bash
apt install -y curl wget vim htop net-tools ncdu git ufw fail2ban jq \
  ca-certificates gnupg lsb-release netcat-openbsd
```

### 5. Instalación de Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Autenticación **con auth key** (evita problemas con URLs caducables):

```bash
tailscale up --authkey=tskey-auth-XXX --accept-dns=false
```

El flag `--accept-dns=false` es **crítico**: evita que Tailscale sobrescriba
el DNS del sistema (problema experimentado en el manager local, ver
`04-incidents.md`).

## Verificación de conectividad

### Estado de Tailscale

```bash
tailscale status
```

Salida (ejemplo):

```
<TAILSCALE_IP_VPS>  <VPS_HOSTNAME>       user@  linux  -
<TAILSCALE_IP_MGR>  <MANAGER_HOSTNAME>   user@  linux  active; direct <PUBLIC_IP>:41641
```

**Nota importante:** la conexión es `direct` (P2P sin relay DERP), lo que
garantiza el mejor rendimiento y latencia.

### Ping desde VPS al manager

```bash
ping -c 3 <TAILSCALE_IP_MGR>
```

Resultado (ejemplo):

```
64 bytes from <TAILSCALE_IP_MGR>: icmp_seq=1 ttl=64 time=234 ms
64 bytes from <TAILSCALE_IP_MGR>: icmp_seq=2 ttl=64 time=48.1 ms
64 bytes from <TAILSCALE_IP_MGR>: icmp_seq=3 ttl=64 time=47.4 ms
0% packet loss
```

### Puertos de Wazuh accesibles desde la VPS

```bash
nc -zv <TAILSCALE_IP_MGR> 1514    # succeeded
nc -zv <TAILSCALE_IP_MGR> 1515    # succeeded
nc -zv <TAILSCALE_IP_MGR> 55000   # succeeded
```

Los tres puertos del manager responden correctamente a través del túnel
Tailscale.

## Arquitectura actual

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
```


La Fase 2 está completada. El pipeline funciona end-to-end:
`Internet → T-Pot → wazuh-agent → Tailscale → Wazuh Manager → Dashboard`
```

---

## Estado de la VPS

| Componente | Estado |
|---|---|
| SO | ✅ Ubuntu 26.04 LTS |
| SSH (puerto 64295, usuario tadmin) | ✅ Configurado por T-Pot |
| Swap | ✅ 4 GB activo |
| Tailscale | ✅ Autenticado y conectado |
| Docker | ✅ Instalado por T-Pot |
| **T-Pot 24.04.1** | ✅ **23 contenedores activos** |
| **Agente Wazuh (`vps-tpot`)** | ✅ **Active, enviando eventos** |
| UFW | ✅ Configurado por T-Pot |
| fail2ban | ✅ Activo contra honeypots |

## Próximos pasos

La VPS está completamente operativa. Las tareas restantes pertenecen a fases
posteriores:

- **Fase 3:** crear reglas de detección específicas para los ataques capturados
  por T-Pot (SSH, RDP, SIP, HTTP) y mapeo a MITRE ATT&CK.
- **Fase 4:** dashboards personalizados y Active Response.

## Documentación relacionada

- [Instalación de T-Pot](07-tpot-installation.md)
- [Agente Wazuh en la VPS](08-wazuh-agent-vps.md)
- [ADR 0002 — Tailscale](adr/0002-tailscale-sobre-wireguard.md)
- [Incidentes documentados](04-incidents.md)

## Referencias

- [Contabo Cloud VPS](https://contabo.com/en/vps/)
- [Tailscale](https://tailscale.com/)
- [T-Pot](https://github.com/telekom-security/tpotce)
- [Wazuh](https://wazuh.com/)
