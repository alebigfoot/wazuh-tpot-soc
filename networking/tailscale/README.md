# Tailscale

Configuración del túnel Tailscale entre la VPS pública (Contabo) y el
manager Wazuh local.

## Motivo de elegir Tailscale en lugar de WireGuard directo

Ver el ADR completo en [`docs/adr/0002-tailscale-sobre-wireguard.md`](../../docs/adr/0002-tailscale-sobre-wireguard.md).

Resumen:

- **No hay acceso al router** para abrir el puerto UDP de WireGuard
- Tailscale funciona detrás de CGNAT sin configuración de red
- Basado en WireGuard (misma criptografía, mismo rendimiento)
- Gratis para uso personal (hasta 100 dispositivos)
- Conexión directa P2P cuando es posible (sin relay DERP)

## Configuración

En **ambos extremos** (VPS y manager):

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --accept-dns=false
```

El flag `--accept-dns=false` es **crítico** para no romper la resolución
DNS del sistema (ver Incidente 6 en `docs/04-incidents.md`).

### Recomendación: usar auth keys en lugar de URLs

Para servidores y automatización, generar una **auth key** desde el panel
de Tailscale (`https://login.tailscale.com/admin/settings/keys`) y usarla:

```bash
sudo tailscale up --authkey=tskey-auth-XXXX --accept-dns=false
```

Ventajas:

- No depende del navegador
- No caduca en 10 minutos como las URLs de autenticación
- Reproducible y automatizable
- Se puede revocar desde el panel cuando se quiera

## Comandos de verificación

```bash
# Ver dispositivos en el tailnet
tailscale status

# Ver IP Tailscale de la máquina actual
tailscale ip -4

# Ping a la otra máquina por la red Tailscale
tailscale ping <TAILSCALE_IP>

# Ver el estado del servicio
systemctl status tailscaled
```

## Puertos Wazuh accesibles desde la VPS

A través del túnel Tailscale, la VPS puede alcanzar los siguientes puertos
del manager Wazuh:

```bash
nc -zv <TAILSCALE_IP_MANAGER> 1514    # eventos de agentes (remoted)
nc -zv <TAILSCALE_IP_MANAGER> 1515    # registro de agentes (authd)
nc -zv <TAILSCALE_IP_MANAGER> 55000   # API REST
```

## Arquitectura

```
┌─────────────────────────────────┐         ┌─────────────────────────────────┐
│  VPS pública                    │         │  Manager local                  │
│                                 │         │                                 │
│  Tailscale IP: <IP_VPS>         │◄────────┼─►Tailscale IP: <IP_MANAGER>     │
│                                 │  P2P    │                                 │
│  TPOT + Agente Wazuh            │  cifrado│  Wazuh Manager + Indexer        │
└─────────────────────────────────┘         └─────────────────────────────────┘
```

## Direcciones IP (referencia)

| Máquina | Tailscale IP | Rol |
|---|---|---|
| Manager local | `<TAILSCALE_IP_MGR>` | Servidor Wazuh |
| VPS Contabo | `<TAILSCALE_IP_VPS>` | TPOT + agente Wazuh |

Los valores reales están documentados en `docs/06-vps-setup.local.md`
(fichero no versionado, bloqueado por `.gitignore`).

## Troubleshooting

Problemas comunes y sus soluciones:

- **DNS no resuelve** → `tailscale set --accept-dns=false` (ver Incidente 6)
- **Autenticación por URL no sincroniza** → usar auth key (ver Incidente 7)
- **"Logged out" tras reconectar** → `systemctl restart tailscaled` (ver Incidente 8)

Ver [`docs/04-incidents.md`](../../docs/04-incidents.md) y
[`docs/05-troubleshooting.md`](../../docs/05-troubleshooting.md) para
detalles completos.

## Referencias

- [Tailscale](https://tailscale.com/)
- [ADR 0002 — Tailscale sobre WireGuard](../../docs/adr/0002-tailscale-sobre-wireguard.md)
- [Tailscale KB](https://tailscale.com/kb/)
