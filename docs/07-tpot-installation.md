# Instalación de T-Pot en la VPS

Documentación del despliegue de **T-Pot** (plataforma multi-honeypot de
Deutsche Telekom) en la VPS pública de Contabo, como parte de la Fase 2
del laboratorio.

## Contexto

### ¿Qué es T-Pot?

T-Pot es una plataforma que agrupa **más de 20 honeypots especializados**
bajo un mismo sistema, con:

- Almacenamiento centralizado (Elasticsearch + Logstash)
- Dashboards Kibana predefinidos
- Attack Map en tiempo real
- Filtros y análisis de ataques

Es uno de los frameworks de honeypots más completos del mercado y se usa
ampliamente para investigación de amenazas y entrenamiento en ciberseguridad.

### ¿Por qué T-Pot en este laboratorio?

El objetivo de la Fase 2 es capturar **tráfico real de Internet** para
alimentar el SIEM (Wazuh) con eventos auténticos:

- Fuerza bruta SSH contra Cowrie
- Escaneos de servicios y explotación contra Dionaea
- Tráfico malicioso detectado por Suricata
- Toda la telemetría que solo se genera cuando estás expuesto a Internet

T-Pot acelera el despliegue porque incluye los honeypots configurados,
los logs centralizados y un panel web listo para usar.

## Requisitos

Según la versión 24.04.1 de T-Pot:

| Recurso | Mínimo | Recomendado |
|---|---|---|
| SO | Ubuntu 26.04 LTS | Ubuntu 26.04 LTS |
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disco | 40 GB | 100 GB+ |
| Red | IP pública | IP pública |

Nuestra VPS de Contabo (4 vCPU, 8 GB RAM, 96 GB disco) cumple con margen.

> **Nota:** versiones anteriores de T-Pot soportaban Ubuntu 22.04 y 24.04.
> La versión actual exige **Ubuntu 26.04**. Ver Incidente 9 en
> [`04-incidents.md`](04-incidents.md).

## Proceso de instalación

### 1. Verificar la versión del SO

```bash
lsb_release -rs
```

Debe devolver **`26.04`**. Si devuelve `24.04` o inferior, hay que
actualizar primero:

```bash
sudo do-release-upgrade
```

### 2. Preparar el sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ca-certificates gnupg jq
```

### 3. Crear un usuario no-root

T-Pot **no se puede instalar desde root**. Hay que crear un usuario
normal con permisos sudo:

```bash
sudo adduser tadmin
sudo usermod -aG sudo tadmin
```

> **Nota:** la instalación posterior de T-Pot usará este usuario tanto para
> el sistema como para el panel web.

### 4. Configurar la clave SSH pública

Antes de la instalación, hay que asegurar que el usuario `tadmin` (y root)
tienen la clave pública SSH del manager para poder reconectar tras el
cambio de puerto que hace T-Pot.

**Desde el manager:**

```bash
# Ver la clave pública
cat ~/.ssh/id_ed25519.pub
```

Si no existe, generarla primero:

```bash
ssh-keygen -t ed25519 -C "soc-manager"
cat ~/.ssh/id_ed25519.pub
```

**Añadir la clave al usuario `tadmin`:**

```bash
cat ~/.ssh/id_ed25519.pub | ssh tadmin@<VPS_IP> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Verificar que funciona sin contraseña:

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP> "hostname"
```

### 5. Clonar T-Pot

Como `tadmin` (no como root):

```bash
ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP>
git clone https://github.com/telekom-security/tpotce.git
cd tpotce
ls -la install.sh
```

### 6. Elegir el tipo de instalación

El instalador soporta varios tipos:

| Tipo | Descripción | RAM recomendada |
|---|---|---|
| `h` (hive) | Completo, todos los honeypots | 16 GB |
| `s` (sensor) | Subconjunto ligero | 8 GB |
| `l` (llm) | Enfocado a LLM/prompts | — |
| **`i` (mini)** | **Subconjunto adaptado a recursos limitados** | **4-6 GB** |
| `m` (mobile) | Ligero, para ARM | — |
| `t` (tarpit) | Tarpit + honeypots básicos | — |

**Recomendación para VPS de 8 GB:** `mini` (i).

### 7. Lanzar el instalador

**Sin `sudo`** — el script no acepta ejecutarse como root:

```bash
cd ~/tpotce
./install.sh -t i -u tadmin -p '<PASSWORD>'
```

**Flags:**

- `-t i` → tipo mini
- `-u tadmin` → usuario del web UI
- `-p '<PASSWORD>'` → contraseña del web UI

> **Nota:** la contraseña debe ir entre **comillas simples** si contiene
> caracteres especiales. Evitar incluir `'` dentro.

### 8. Durante la instalación

El instalador tarda **20-40 minutos** y realiza estas fases:

1. Verificación de prerequisitos (versión de SO, recursos)
2. Instalación de Docker y docker-compose
3. Descarga de imágenes Docker (~3-4 GB)
4. Configuración de UFW (abre puertos de honeypots)
5. **Cambio de puerto SSH** (de 22 a 64295)
6. **Deshabilitación de root por SSH**
7. Creación del usuario y configuración de la clave SSH
8. Arranque de todos los contenedores
9. Publicación del panel web en el puerto 64297

> **⚠️ Importante:** en algún punto de la instalación, **la sesión SSH se
> cerrará**. Es normal: T-Pot está cambiando el puerto SSH.
>
> La reconexión posterior se hace así:
>
> ```bash
> ssh -i ~/.ssh/id_ed25519 tadmin@<VPS_IP> -p 64295
> ```

## Estado tras la instalación

### Contenedores corriendo

Después de la instalación, `sudo docker ps` muestra **23 contenedores
activos**:

| Contenedor | Función |
|---|---|
| `honeypots` | Multi-honeypot (SSH, FTP, HTTP, MySQL, RDP, VNC, Redis…) |
| `conpot_*` | Honeypots industriales (SCADA/ICS) |
| `dicompot` | Honeypot DICOM (médico) |
| `medpot` | Honeypot HL7 (médico) |
| `ciscoasa` | Honeypot Cisco ASA (VPN) |
| `adbhoney` | Honeypot Android Debug Bridge |
| `suricata` | IDS / análisis de tráfico |
| `p0f`, `fatt` | Passive fingerprinting de atacantes |
| `honeytrap` | Honeypot genérico |
| `spiderfoot` | OSINT / threat intelligence |
| `elasticsearch` | Almacenamiento de logs |
| `logstash` | Procesamiento de logs |
| `kibana` | Dashboard web |
| `nginx` | Reverse proxy del panel |
| `map_*` | Mapa de atacantes |
| `ewsposter` | Envío a Early Warning System |
| `tpotinit` | Inicializador de T-Pot |

### Puertos abiertos a Internet

T-Pot abre puertos específicos para cada honeypot:

| Puerto | Servicio |
|---|---|
| 22, 2222 | SSH (honeypots) |
| 23 | Telnet |
| 25 | SMTP |
| 80, 443, 8080 | HTTP/HTTPS |
| 445 | SMB (Dionaea) |
| 1433 | MSSQL |
| 3306 | MySQL |
| 3389 | RDP |
| 5432 | PostgreSQL |
| 5900 | VNC |
| 6379 | Redis |
| 11211 | Memcached |

Los puertos internos de administración (`9200` Elasticsearch, `5601` Kibana)
solo escuchan en `127.0.0.1`.

### Puertos de administración

| Puerto | Servicio |
|---|---|
| **64295** | SSH (nuevo puerto tras instalación) |
| **64297** | Panel web de T-Pot (HTTPS) |
| 64294 | Landing page |
| 64298 | Elasticsearch (interno) |
| 64299 | Map data (interno) |

## Acceso al panel web

Desde el manager o cualquier equipo con acceso a la VPS:

```
https://<VPS_IP>:64297
```

- **Usuario:** el configurado en la instalación (`tadmin`)
- **Contraseña:** la configurada en la instalación

El panel incluye:

- **Attack Map** en tiempo real (mapa mundial)
- **Kibana** con dashboards predefinidos:
  - Ataques por servicio
  - Credenciales más probadas
  - Comandos ejecutados
  - Geolocalización de atacantes
  - Timeline de eventos
- **Cockpit** para administración del sistema
- **Cyberchef** para análisis de datos

## Seguridad tras la instalación

T-Pot endurece el SSH automáticamente:

| Aspecto | Antes | Después |
|---|---|---|
| Puerto SSH | 22 | **64295** |
| Login root | Permitido | **Deshabilitado** |
| Password auth | Permitido | Deshabilitado (solo clave) |
| UFW | Inactivo | Activo con reglas específicas |
| Fail2ban | Instalado, no config | Activo contra honeypots |

## Verificación

Comandos útiles para verificar el estado:

```bash
# Ver contenedores
sudo docker ps

# Contar contenedores activos
sudo docker ps -q | wc -l

# Ver estado del servicio T-Pot
sudo systemctl status tpot

# Ver puertos abiertos
sudo ss -tlnp | grep LISTEN

# Ver reglas de firewall
sudo ufw status verbose

# Ver logs de un honeypot específico
sudo docker logs honeypots --tail 30
sudo docker logs suricata --tail 30
sudo docker logs conpot_ipmi --tail 30
```

## Próximos pasos

1. Instalar agente Wazuh en la VPS
2. Configurar `localfiles` para los logs de T-Pot
3. Verificar que los eventos llegan al manager Wazuh
4. Crear reglas de detección específicas para T-Pot
5. Documentar la fase de integración completa

## Referencias

- [T-Pot en GitHub](https://github.com/telekom-security/tpotce)
- [Documentación oficial de T-Pot](https://github.com/telekom-security/tpotce/blob/master/README.md)
- [Incidentes relacionados](04-incidents.md)
