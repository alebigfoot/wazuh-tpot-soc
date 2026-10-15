# Instalación de Wazuh todo-en-uno

Documentación del proceso de despliegue de Wazuh (Manager + Indexer + Dashboard)
sobre Ubuntu 22.04 LTS en una máquina virtual.

## Requisitos del sistema

| Recurso | Mínimo | Usado en este lab |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 8 GB |
| Disco | 50 GB | 50 GB |
| SO | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

## Pasos

### 1. Actualización del sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg apt-transport-https lsb-release \
  software-properties-common net-tools vim htop ufw git
```

### 2. Ajuste del kernel

Wazuh Indexer usa OpenSearch, que requiere un valor mínimo de `vm.max_map_count`.
Sin este ajuste, el Indexer no arranca.

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Verificación:

```bash
sysctl vm.max_map_count
# Debe devolver: vm.max_map_count = 262144
```

### 3. Firewall

UFW está habilitado, con política predeterminada de denegación de conexiones entrantes y permiso para conexiones salientes.

Reglas entrantes configuradas y verificadas:

| Puerto | Servicio | Regla actual |
|---|---|---|
| 22/TCP | SSH | Permitido desde cualquier origen |
| 443/TCP | Wazuh Dashboard | Permitido desde cualquier origen |
| 1514/TCP | Comunicación con agentes | Permitido desde cualquier origen |
| 1515/TCP | Registro de agentes | Permitido desde cualquier origen |
| 55000/TCP | API de Wazuh | Permitido desde cualquier origen |

Los puertos 9200/TCP y 9300/TCP del Wazuh Indexer no tienen reglas de entrada específicas en UFW y, según la comprobación realizada con `ss`, escuchan únicamente en la interfaz de loopback.

Aunque UFW está activo, las reglas actuales permiten conexiones entrantes a los puertos indicados desde cualquier origen. Se debe restringir el acceso a los servicios de administración y limitar las conexiones de agentes a las redes autorizadas.

La máquina dispone de una interfaz de red local y otra de Tailscale. La política definitiva de acceso debe tener en cuenta ambas interfaces y la conectividad con la VPS que aloja T-Pot.

### 4. Descarga del instalador

Se descarga el asistente de instalación de la rama 4.14 de Wazuh. La versión instalada y verificada en este laboratorio es la 4.14.8.

```bash
cd ~
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
chmod +x wazuh-install.sh
```

### 5. Instalación all-in-one

```bash
sudo bash wazuh-install.sh -a
```

Duración estimada: 10-20 minutos.

Al finalizar, el instalador muestra las credenciales y las guarda en
`~/wazuh-install-files.tar`. Es importante conservarlas.

### 6. Verificación

```bash

# Servicios centrales
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard

# Puertos en escucha
sudo ss -lntp | grep -E ':(443|1514|1515|55000|9200|9300)\b'

# Parámetro del kernel
sysctl vm.max_map_count

# Respuesta del dashboard
curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://127.0.0.1/
```

## Resultado obtenido

Resultados observados durante la verificación del laboratorio:

- Versión de Wazuh: `4.14.8` en Manager, Indexer y Dashboard.
- Estado del clúster: `green`.
- Nodos: 1 nodo total y 1 nodo de datos.
- Shards primarios activos: 28.
- Shards activos: 28.
- Shards sin asignar: 0.
- Dashboard accesible y operativo; responde con HTTP `302` al acceder a la raíz.
- Alertas iniciales observadas: 144 Medium y 89 Low, generadas por la monitorización interna del Manager, sin agentes conectados en ese momento.

Estos valores corresponden a las comprobaciones realizadas en este laboratorio y pueden variar con la configuración y la actividad del entorno.

### 7. Acceso al dashboard

Desde el navegador de la VM:

```
https://127.0.0.1
```

Aceptar el certificado autofirmado y usar las credenciales del usuario `admin`.

## Resultado obtenido

- Cluster: `green`
- Shards activos: 11
- Alertas iniciales: 144 Medium + 89 Low (monitorización interna del propio
  manager, sin agentes conectados aún)
- Dashboard accesible y operativo

## Incidencias encontradas

Durante la instalación aparecieron varios problemas, todos documentados
con detalle en [`04-incidents.md`](04-incidents.md):

| Problema | Referencia |
|---|---|
| `vm.max_map_count` por defecto demasiado bajo | — |
| Placeholders sin sustituir en `config.yml` | — |
| Manager no arranca por timeout de systemd | [Incidente 3](04-incidents.md#incidente-3-manager-no-arranca-por-timeout-de-systemd) |
| Locks huérfanos tras timeout | [Incidente 4](04-incidents.md#incidente-4-locks-huérfanos-tras-timeout) |
| Indexer no arranca por timeout de systemd | [Incidente 5](04-incidents.md#incidente-5-indexer-no-arranca-por-timeout-de-systemd) |

## Relación con otras fases

- **Fase 2 — Honeypot en VPS:** el manager Wazuh recibe eventos de un
  honeypot T-Pot desplegado en una VPS pública.
  - [Configuración de la VPS](06-vps-setup.md)
  - [Instalación de T-Pot](07-tpot-installation.md)
  - [ADR 0002 — Tailscale](adr/0002-tailscale-sobre-wireguard.md)

## Referencias

- [Documentación oficial Wazuh](https://documentation.wazuh.com/)
- [Guía de instalación all-in-one](https://documentation.wazuh.com/current/installation-guide/index.html)
