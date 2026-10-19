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
| SO | Ubuntu 24.04.5 LTS |
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
┌─────────────────────────────────────────┐         ┌─────────────────────────────────────────┐
│  VPS Contabo                            │         │  Manager local                          │
│                                         │         │                                         │
│  IP pública: <VPS_IP>                   │         │  LAN: <LAN_IP>                          │
│  Tailscale:  <TAILSCALE_IP_VPS>         │◄────────┼─►Tailscale: <TAILSCALE_IP_MGR>          │
│                                         │  Direct │                                         │
│  Ubuntu 24.04 LTS                       │  P2P    │  Ubuntu 22.04 LTS                       │
│  4 vCPU · 8 GB RAM · 96 GB disco        │         │  8 vCPU · 8 GB RAM · 50 GB disco        │
│                                         │         │                                         │
│              TPOT                       │         │  Wazuh Manager + Indexer + Dashboard    │
│              Agente Wazuh               │         │                                         │
└─────────────────────────────────────────┘         └─────────────────────────────────────────┘
```

## Estado de la VPS

| Componente | Estado |
|---|---|
| SSH (puerto 22, root) | ✅ Funcional |
| Swap | ✅ 4 GB activo |
| Actualización | ✅ Al día |
| Tailscale | ✅ Autenticado y conectado |
| UFW | ❌ Pendiente |
| fail2ban | ⚠️ Instalado pero sin configurar |
| Docker | ❌ Pendiente |
| TPOT | ❌ Pendiente |
| Agente Wazuh | ❌ Pendiente |

## Próximos pasos

1. Endurecer SSH (usuario no-root, deshabilitar password auth)
2. Configurar UFW (permitir solo lo necesario)
3. Configurar fail2ban
4. Instalar Docker
5. Instalar TPOT
6. Instalar agente Wazuh
7. Verificar llegada de eventos al manager

## Referencias

- [Contabo Cloud VPS](https://contabo.com/en/vps/)
- [Tailscale](https://tailscale.com/)
- [TPOT](https://github.com/telekom-security/tpotce)
