# Arquitectura

## Estado actual (Fase 1)

```
┌──────────────────────────────────────────────┐
│  Ubuntu 22.04 LTS (VirtualBox, NAT)          │
│  IP: 10.0.2.15                               │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │  Wazuh Manager      (1514, 1515, 55000)│  │
│  │  Wazuh Indexer      (9200, solo local) │  │
│  │  Wazuh Dashboard    (443)              │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  8 vCPU · 8 GB RAM · 50 GB disco             │
└──────────────────────────────────────────────┘
```

En esta fase el sistema es autónomo: Wazuh monitoriza el propio host y se
accede al dashboard únicamente desde la red local.

## Estado objetivo (Fase final)

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  VPS pública             │         │  Ubuntu 22.04 (local)    │
│                          │         │                          │
│  ┌────────────────────┐  │         │  ┌────────────────────┐  │
│  │  TPOT              │  │         │  │  Wazuh Manager     │  │
│  │  - Cowrie          │  │   WG    │  │  Wazuh Indexer     │  │
│  │  - Dionaea         │◄─┼─────────┼─►│  Wazuh Dashboard   │  │
│  │  - Suricata        │  │         │  │  + Agente Wazuh    │  │
│  │  - Honeytrap       │  │         │  └────────────────────┘  │
│  └────────────────────┘  │         │                          │
│  10.10.0.2 (WireGuard)   │         │  10.10.0.1 (WireGuard)   │
└──────────────────────────┘         └──────────────────────────┘
         ▲
         │  Ataques reales de Internet
         │  (bots, escáneres, atacantes)
```

## Componentes

### Wazuh (local)

| Componente | Puerto | Función |
|---|---|---|
| Wazuh Manager | 1514, 1515, 55000 | Recepción de eventos, aplicación de reglas, API |
| Wazuh Indexer | 9200 (solo localhost) | Almacenamiento y búsqueda |
| Wazuh Dashboard | 443 | Interfaz web de análisis |

### TPOT (VPS)

| Honeypot | Servicio simulado | Puerto típico |
|---|---|---|
| Cowrie | SSH, Telnet | 22, 23 |
| Dionaea | SMB, FTP, MSSQL | 445, 21, 1433 |
| Suricata | IDS/IPS (no honeypot) | — |
| Honeytrap | Genérico | varios |

### Túnel WireGuard

| Extremo | IP túnel | Rol |
|---|---|---|
| Ubuntu local | 10.10.0.1 | Servidor WG |
| VPS | 10.10.0.2 | Cliente WG |

El túnel permite que el agente Wazuh de la VPS envíe eventos al manager
local sin exponer los puertos `1514`, `1515` ni `55000` a Internet.

## Flujo de datos

1. Un atacante contacta con un servicio del honeypot en la VPS.
2. TPOT captura la interacción y genera un log JSON.
3. El agente Wazuh de la VPS lee ese log y lo envía al manager por el túnel WG.
4. El manager aplica decoders y reglas.
5. Los eventos se indexan en Wazuh Indexer.
6. El dashboard los muestra con dashboards específicos de TPOT.

## Decisiones de diseño

- **Instalación todo-en-uno:** para un lab personal con recursos limitados,
  un solo nodo simplifica la operación y es suficiente. Ver ADR 0001.
- **TPOT en VPS pública:** el honeypot necesita exponerse a Internet para
  recibir tráfico real; hacerlo en la red doméstica sería inseguro.
- **WireGuard en lugar de abrir puertos:** mantiene el manager inaccesible
  desde Internet y reduce la superficie de ataque.

## Referencias

- [Documentación Wazuh](https://documentation.wazuh.com/)
- [TPOT en GitHub](https://github.com/telekom-security/tpotce)
- [WireGuard](https://www.wireguard.com/)
