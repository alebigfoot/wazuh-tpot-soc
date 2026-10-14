# Wazuh + TPOT SOC Lab

![Fase 1](https://img.shields.io/badge/Fase%201-Completada-brightgreen)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14.8-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20LTS-orange)
![Licencia](https://img.shields.io/badge/Licencia-MIT-lightgrey)
![Estado](https://img.shields.io/badge/Estado-Activo-success)

Laboratorio SOC personal para practicar operativa Blue Team: despliegue de un
SIEM (Wazuh) en local y un honeypot multi-servicio (TPOT) en una VPS pública,
conectados por túnel Tailscale. Los ataques reales contra el honeypot se
detectan, enriquecen y visualizan en tiempo real.

> **Estado:** Fase 1 completada — Wazuh todo-en-uno desplegado y operativo.

## Fases del proyecto

| Fase | Descripción | Estado |
|---|---|---|
| **1. Wazuh base** | SIEM desplegado en local + agente validado | ✅ Completada |
| **2. Honeypot** | T-Pot en VPS pública + túnel Tailscale | 🚧 En progreso |
| **3. Detección** | Reglas custom + mapeo MITRE ATT&CK | ⏳ Pendiente |
| **4. Visualización** | Dashboards + Active Response | ⏳ Pendiente |

---

## 1. Problema

Los perfiles junior en ciberseguridad suelen tener dificultades para demostrar
experiencia práctica real. Los cursos y certificaciones no siempre evidencian
capacidad operativa: montar, monitorizar y analizar eventos en un SIEM real.

Este proyecto documenta la construcción de un SOC funcional end-to-end con
evidencia reproducible: instalación, configuración, reglas de detección,
dashboards y análisis de ataques reales capturados por un honeypot expuesto
en Internet.

---

## 2. Objetivo

**Qué hace este proyecto:**

- Despliega Wazuh todo-en-uno (Manager + Indexer + Dashboard) sobre Ubuntu 22.04 LTS.
- Expone un honeypot TPOT en una VPS pública para recibir ataques reales de Internet.
- Conecta ambos entornos mediante túnel Tailscale, sin exponer el SIEM.
- Aplica reglas de detección mapeadas a MITRE ATT&CK.
- Visualiza la actividad maliciosa en dashboards específicos.

**Qué NO hace:**

- No es un SOC de producción.
- No sustituye a un SIEM empresarial.
- No pretende detectar amenazas avanzadas (APTs).

---

## 3. Arquitectura

### Estado actual (Fase 1)

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

### Estado objetivo (Fase final)

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  VPS pública             │         │  Ubuntu 22.04 (local)    │
│                          │         │                          │
│  ┌────────────────────┐  │         │  ┌────────────────────┐  │
│  │  TPOT              │  │   TS    │  │  Wazuh Manager     │  │
│  │  - Cowrie          │◄─┼─────────┼─►│  Wazuh Indexer     │  │
│  │  - Dionaea         │  │         │  │  Wazuh Dashboard   │  │
│  │  - Suricata        │  │         │  │  + Agente Wazuh    │  │
│  └────────────────────┘  │         │  └────────────────────┘  │
│  10.10.0.2 (Tailscale)   │         │  10.10.0.1 (Tailscale)   │
└──────────────────────────┘         └──────────────────────────┘
         ▲
         │  Ataques reales de Internet
         │  (bots, escáneres, atacantes)
```

---

## 4. Instalación

Documentación detallada paso a paso en
[`docs/01-installation.md`](docs/01-installation.md).

**Resumen rápido:**

```bash
# 1. Ajuste del kernel (crítico para Wazuh Indexer)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Descarga del instalador
cd ~
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
chmod +x wazuh-install.sh

# 3. Ajuste de config.yml (sustituir placeholders)
sed -i 's/<indexer-node-ip>/127.0.0.1/g' config.yml
sed -i 's/<wazuh-manager-ip>/127.0.0.1/g' config.yml
sed -i 's/<dashboard-node-ip>/127.0.0.1/g' config.yml

# 4. Instalación all-in-one
sudo bash wazuh-install.sh -a
soc@soc-VirtualBox:~/wazuh-tpot-soc$ echo "=== Git status ==="
git status --short

echo ""
echo "=== ¿Qué dice el README de docs? ==="
grep -A 8 "## 10. Documentación adicional" README.md

echo ""
echo "=== Fases del proyecto en README ==="
grep -A 8 "## Fases del proyecto" README.md
=== Git status ===
M  .gitignore
A  docs/06-vps-setup.md
A  docs/adr/0002-tailscale-sobre-wireguard.md

=== ¿Qué dice el README de docs? ===
## 10. Documentación adicional

- [Instalación detallada](docs/01-installation.md)
- [Arquitectura](docs/02-architecture.md)
- [Validación del agente](docs/03-agent-validation.md)
- [Incidentes documentados](docs/04-incidents.md)
- [Troubleshooting](docs/05-troubleshooting.md)
- [Decisiones de diseño (ADR)](docs/adr/)
---

=== Fases del proyecto en README ===
## Fases del proyecto

| Fase | Descripción | Estado |
|---|---|---|
| **1. Wazuh base** | SIEM desplegado en local + agente validado | ✅ Completada |
| **2. Honeypot** | TPOT en VPS pública + túnel Tailscale | 🚧 En progreso |
| **3. Detección** | Reglas custom + mapeo MITRE ATT&CK | ⏳ Pendiente |
| **4. Visualización** | Dashboards + Active Response | ⏳ Pendiente |

soc@soc-VirtualBox:~/wazuh-tpot-soc$ 
```

Duración estimada: 10-20 minutos.

---

## 5. Uso

Acceso al dashboard desde el navegador de la VM:

```
https://127.0.0.1
```

Credenciales generadas por el instalador y almacenadas en
`~/wazuh-install-files.tar`.

Verificación rápida del estado:

```bash- [Instalación de T-Pot](docs/07-tpot-installation.md)
# Servicios activos
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard

# Estado del cluster
curl -sk -u admin:TU_PASSWORD https://localhost:9200/_cluster/health?pretty
```

---

## 6. Capturas

![Dashboard overview](docs/diagrams/dashboard-overview.png)

*Panel principal del Wazuh Dashboard tras la instalación inicial, mostrando
métricas de las últimas 24 horas.*

---

## 7. Testing

Pendiente de implementar cuando se añadan las reglas de detección.

Los tests previstos validarán que las reglas personalizadas disparan con
eventos de ejemplo (logs sintéticos de Cowrie, Dionaea y Suricata).

---

## 8. Seguridad

### Gestión de secretos

Este repositorio **no contiene credenciales reales**. Patrón seguido:

- `.env.example` → plantilla pública con valores `CHANGE_ME`
- `.env` → fichero local con valores reales, ignorado por git

El `.gitignore` bloquea explícitamente:

- Ficheros `.env` y variantes
- Claves y certificados (`*.pem`, `*.key`, `*.crt`)
- Claves Tailscale (`privatekey`, `publickey`)
- Credenciales del instalador (`wazuh-passwords.txt`, `wazuh-install-files.tar`)

### Superficie de exposición

- El dashboard **no se expone directamente a Internet**.
- El acceso se realiza desde la red local o por túnel Tailscale.
- La VPS solo expone los puertos de los honeypots (deliberadamente vulnerable).

### Aviso legal

Este proyecto se usa exclusivamente contra infraestructura propia.
Nunca ataques sistemas de terceros sin autorización por escrito.

---

## 9. Roadmap

### Fase 1 — Wazuh base
- [x] Desplegar Wazuh todo-en-uno en Ubuntu 22.04
- [x] Verificar cluster `green` y acceso al dashboard
- [x] Conectar agente Wazuh local para validar pipeline

### Fase 2 — Honeypot en VPS
- [x] Contratar VPS (Contabo) y preparar el sistema
- [x] Configurar túnel Tailscale VPS ↔ manager local
- [x] Verificar conectividad y puertos Wazuh a través del túnel
- [x] Instalar T-Pot (perfil mini) en la VPS
- [x] Verificar arranque de los contenedores de honeypots
- [ ] Instalar agente Wazuh en la VPS
- [ ] Configurar `localfiles` para los logs de T-Pot
- [ ] Verificar llegada de eventos reales al dashboard

### Fase 3 — Detección
- [ ] Añadir reglas de detección para Cowrie
- [ ] Añadir reglas de detección para Dionaea
- [ ] Añadir reglas de detección para Suricata
- [ ] Documentar cada regla con mapeo MITRE ATT&CK
- [ ] Añadir tests de reglas con eventos de ejemplo

### Fase 4 — Visualización y respuesta
- [ ] Exportar dashboards personalizados como código (ndjson)
- [ ] Añadir Active Response para bloqueo de IPs
- [ ] Integrar enriquecimiento (VirusTotal, AbuseIPDB, OTX)

---

## 10. Documentación adicional

- [Instalación detallada](docs/01-installation.md)
- [Arquitectura](docs/02-architecture.md)
- [Validación del agente](docs/03-agent-validation.md)
- [Incidentes documentados](docs/04-incidents.md)
- [Troubleshooting](docs/05-troubleshooting.md)
- [Configuración de la VPS](docs/06-vps-setup.md)
- [Instalación de T-Pot](docs/07-tpot-installation.md)
- [Decisiones de diseño (ADR)](docs/adr/)
---

## 11. Incidencias documentadas

Durante la construcción del laboratorio han aparecido algunos problemas reales
documentados en [`docs/04-incidents.md`](docs/04-incidents.md):

### Fase 1 — Wazuh base

1. `wazuh-agent` destruye `wazuh-manager` en el mismo host
2. Dashboard roto tras reinstall del manager (403 + `version_conflict`)
3. Manager no arranca por timeout de systemd
4. Locks huérfanos en `/var/ossec/var/run/` tras timeout
5. Indexer no arranca por timeout de systemd (mismo patrón)

### Fase 2 — VPS + Tailscale

6. DNS roto tras cambiar adaptador de red en VirtualBox
7. Tailscale: autenticación por URL no sincroniza
8. Sesión de Tailscale caduca entre sesiones SSH

## Licencia

MIT — ver [LICENSE](LICENSE).
