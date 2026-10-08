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

```bash
sudo ufw allow 22/tcp        # SSH
sudo ufw allow 443/tcp       # Dashboard
sudo ufw allow 1514/tcp      # Agentes (eventos)
sudo ufw allow 1515/tcp      # Registro de agentes
sudo ufw allow 55000/tcp     # API
sudo ufw enable
```

Los puertos `9200` y `9300` del Indexer **no se exponen**. Solo escuchan en
`127.0.0.1`.

### 4. Descarga del instalador

```bash
cd ~
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
chmod +x wazuh-install.sh
```

### 5. Configuración del `config.yml`

El fichero descargado contiene placeholders que hay que sustituir. Para una
instalación en un solo nodo, se reemplazan por `127.0.0.1`:

```bash
sed -i 's/<indexer-node-ip>/127.0.0.1/g' config.yml
sed -i 's/<wazuh-manager-ip>/127.0.0.1/g' config.yml
sed -i 's/<dashboard-node-ip>/127.0.0.1/g' config.yml
```

Verificación (no debe quedar ningún `<...>`):

```bash
cat config.yml | grep -E "ip:"
```

### 6. Instalación all-in-one

```bash
sudo bash wazuh-install.sh -a
```

Duración estimada: 10-20 minutos.

Al finalizar, el instalador muestra las credenciales y las guarda en
`~/wazuh-install-files.tar`. Es importante conservarlas.

### 7. Verificación

```bash
# Servicios activos
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard

# Puertos escuchando
sudo ss -tlnp | grep -E '443|1514|1515|55000|9200'

# Estado del cluster
curl -sk -u admin:TU_PASSWORD https://localhost:9200/_cluster/health?pretty
```

Resultado esperado:

- Los 3 servicios `active`
- Puertos 443, 1514, 1515, 55000, 9200 escuchando
- Cluster en estado `green` o `yellow`
- 11 shards activos

### 8. Acceso al dashboard

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

| Problema | Causa | Solución aplicada |
|---|---|---|
| El instalador falla al arrancar el Indexer | `vm.max_map_count` por defecto (65530) | Aplicar `sysctl -w vm.max_map_count=262144` |
| `config.yml` contiene placeholders sin sustituir | Descarga por defecto sin editar | Reemplazarlos por `127.0.0.1` con `sed` |

## Referencias

- [Documentación oficial Wazuh](https://documentation.wazuh.com/)
- [Guía de instalación all-in-one](https://documentation.wazuh.com/current/installation-guide/index.html)
