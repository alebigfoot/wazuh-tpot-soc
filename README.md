# Wazuh + T-Pot SOC Lab

![Fase 1](https://img.shields.io/badge/Fase%201-Completada-brightgreen)
![Fase 2](https://img.shields.io/badge/Fase%202-En%20progreso-yellow)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14.8-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2026.04-orange)
![Licencia](https://img.shields.io/badge/Licencia-MIT-lightgrey)
![Estado](https://img.shields.io/badge/Estado-Activo-success)

Laboratorio personal de **Blue Team** orientado a practicar la monitorización de eventos, el análisis de actividad sospechosa y el desarrollo de capacidades de detección.

El proyecto combina **Wazuh SIEM/XDR**, desplegado en una máquina virtual local, con **T-Pot**, un honeypot multiservicio alojado en una VPS pública. Ambos entornos cuentan con conectividad mediante una red privada Tailscale. El laboratorio se desarrolla por fases: despliegue de infraestructura, integración de telemetría, creación de reglas de detección, mapeo a **MITRE ATT&CK** y visualización de resultados.

> **Estado actual:** Wazuh está desplegado y validado en local; T-Pot está instalado en la VPS y la conectividad mediante Tailscale está configurada. La integración de los logs de T-Pot con Wazuh y la validación de eventos reales en el dashboard siguen pendientes.

## Fases del proyecto

| Fase | Descripción | Estado |
|---|---|---|
| **1. Wazuh base** | SIEM desplegado en local y agente de prueba validado | ✅ Completada |
| **2. Honeypot** | T-Pot en VPS pública y conectividad mediante Tailscale | 🚧 En progreso |
| **3. Detección** | Reglas personalizadas y mapeo MITRE ATT&CK | ⏳ Pendiente |
| **4. Visualización y respuesta** | Dashboards, enriquecimiento y Active Response | ⏳ Pendiente |

---

## 1. Objetivo y alcance

### Objetivos

- Desplegar Wazuh todo-en-uno (Manager, Indexer y Dashboard) en Ubuntu 22.04 LTS.
- Ejecutar T-Pot en una VPS pública para observar actividad dirigida a servicios señuelo.
- Mantener la comunicación entre los entornos mediante Tailscale, evitando exponer directamente el dashboard a Internet.
- Integrar los logs relevantes de T-Pot en Wazuh.
- Crear reglas de detección, documentar su relación con MITRE ATT&CK y desarrollar dashboards para analizar los eventos.

### Alcance y limitaciones

- Es un laboratorio personal, no un SOC de producción.
- No sustituye a un SIEM empresarial ni pretende detectar por sí solo todas las amenazas avanzadas.
- Las capacidades se incorporan y validan progresivamente. Las fases pendientes no deben interpretarse como funcionalidades ya operativas.

---

## 2. Arquitectura

### Estado actual

```text
        Internet
   (bots y escáneres)
            |
            v
+-----------------------------------+
| VPS pública                       |
| Ubuntu 26.04 LTS                  |
|                                   |
| T-Pot (perfil mini)               |
| - Cowrie                          |
| - Dionaea                         |
| - Suricata                        |
| - Otros honeypots                 |
+-----------------------------------+
            |
            | Red privada Tailscale
            | Conectividad configurada
            |
            v
+-----------------------------------+
| Laboratorio local (VirtualBox)    |
| Ubuntu 22.04 LTS                  |
|                                   |
| Wazuh Manager                     |
| Wazuh Indexer                     |
| Wazuh Dashboard                   |
|                                   |
| Agente local de prueba validado   |
+-----------------------------------+

Integración de los logs de T-Pot con Wazuh:
pendiente de completar y validar.
```

La conectividad Tailscale entre la VPS y el laboratorio está configurada. La instalación del agente Wazuh en la VPS, la configuración de la recogida de logs de T-Pot y la comprobación de su llegada al dashboard forman parte del trabajo pendiente de la fase 2.

> **Nota de seguridad:** las direcciones IP privadas de Tailscale, los puertos administrativos y otros detalles específicos de la infraestructura se omiten del diagrama público. La configuración real de red y firewall debe consultarse en la documentación operativa privada o en los archivos de configuración correspondientes.

### Arquitectura objetivo

- **Fase 3:** reglas de detección específicas para la telemetría recogida y mapeo justificado a MITRE ATT&CK.
- **Fase 4:** dashboards personalizados, enriquecimiento de indicadores y pruebas controladas de Active Response.

---

## 3. Instalación

Los procedimientos completos se documentan por separado:

- [Instalación de Wazuh](docs/01-installation.md)
- [Arquitectura del laboratorio](docs/02-architecture.md)
- [Configuración de la VPS](docs/06-vps-setup.md)
- [Instalación de T-Pot](docs/07-tpot-installation.md)

La instalación y los comandos deben corresponder a las versiones realmente utilizadas en cada equipo. Consulta la documentación de instalación para los requisitos previos, la configuración y los pasos de validación.

Para Wazuh Indexer, comprueba que el parámetro de kernel `vm.max_map_count` cumple el requisito de la versión instalada antes de iniciar el despliegue.

---

## 4. Uso y validación

### Acceso al dashboard

Desde el navegador de la máquina virtual, si el servicio está escuchando en la interfaz local:

```text
https://127.0.0.1
```

Las credenciales iniciales se generan durante la instalación. Guarda el archivo de credenciales de forma segura y **no lo subas al repositorio**.

### Comprobar el estado de los servicios

```bash
sudo systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard
```

### Comprobar la salud del clúster

Sustituye `TU_PASSWORD` por la contraseña correspondiente. Evita guardar contraseñas reales en el historial de shell o en archivos versionados.

```bash
curl -sk -u "admin:TU_PASSWORD" \
  "https://localhost:9200/_cluster/health?pretty"
```

La salida de estos comandos debe interpretarse junto con los logs de los servicios. Un comando correcto por sí solo no demuestra que la telemetría de T-Pot esté integrada.

---

## 5. Evidencias

### Wazuh Dashboard — Overview con agente activo

![Dashboard overview](docs/diagrams/dashboard-overview.png)

*Panel principal de Wazuh con un agente activo.*

### Agents — Agente conectado

![Agents active](docs/diagrams/agents-active.png)

El agente `agent-test` aparece en estado `Active` en la vista de agentes.

### Security Events — Eventos del agente

![Security events](docs/diagrams/security-events.png)

*Vista de Discover filtrada por `agent.name: agent-test`, con 216 eventos en la consulta documentada. Estos eventos corresponden al agente de prueba y no deben interpretarse como 216 ataques reales procedentes de T-Pot.*

### Eventos de T-Pot en Wazuh — Ataques reales

![T-Pot events](docs/diagrams/tpot-events.png)

*Vista de Threat Hunting filtrada por `agent.name: vps-tpot`. Muestra 516 eventos reales capturados por T-Pot (Suricata, Dionaea, honeypots SSH/HTTP/RDP/SIP) en las últimas 24 horas.*

### MITRE ATT&CK — Técnicas detectadas en T-Pot

![T-Pot MITRE](docs/diagrams/tpot-mitre.png)

*Técnicas MITRE ATT&CK mapeadas por las reglas de Wazuh aplicadas a los eventos reales de T-Pot: T1110 (Brute Force), T1046 (Network Service Scanning) y T1078 (Valid Accounts), entre otras.*

### Agente `vps-tpot` conectado

![T-Pot agent active](docs/diagrams/tpot-agent-active.png)

*El agente `vps-tpot` (IP Tailscale `<IP_TAILSCALE>`) en estado Active en la vista de agentes del manager.*

---

## 6. Testing

Las pruebas automatizadas de las reglas personalizadas están pendientes de implementar.

Está previsto validar las reglas con eventos de ejemplo asociados a Cowrie, Dionaea y Suricata. Cada prueba deberá documentar:

- El evento de entrada y su origen.
- La regla que se espera que se active.
- El resultado observado.
- El nivel de alerta y los campos relevantes.
- El mapeo a MITRE ATT&CK, cuando corresponda.

---

## 7. Seguridad

### Gestión de secretos

El repositorio no debe contener credenciales reales. El patrón previsto es:

- `.env.example`: plantilla pública con valores de ejemplo.
- `.env`: configuración local con valores reales, excluida del control de versiones.

El `.gitignore` contempla la exclusión de:

- Archivos `.env` y variantes.
- Claves y certificados (`*.pem`, `*.key`, `*.crt`).
- Archivos de claves de Tailscale.
- Archivos de credenciales generados por el instalador de Wazuh.

Estas exclusiones reducen el riesgo de publicar secretos, pero no sustituyen la revisión de los cambios antes de cada `commit`.

### Superficie de exposición

- El dashboard de Wazuh no debe exponerse directamente a Internet.
- El acceso de administración debe limitarse a interfaces y redes de confianza.
- La VPS pública aloja los servicios señuelo de T-Pot, cuya exposición es intencionada.
- Los puertos de administración y de comunicación de Wazuh deben restringirse mediante firewall a los orígenes necesarios.
- Antes de publicar capturas o documentación, revisa que no incluyan direcciones, tokens, contraseñas, claves ni otros datos operativos que no quieras divulgar.

### Aviso legal

Este laboratorio se utiliza para aprendizaje y observación de actividad dirigida a infraestructura propia. No realices pruebas contra sistemas de terceros sin autorización expresa.

---

## 8. Roadmap

### Fase 1 — Wazuh base

- [x] Desplegar Wazuh todo-en-uno en Ubuntu 22.04.
- [x] Verificar el estado del clúster y el acceso al dashboard.
- [x] Conectar un agente local para validar el pipeline básico.

### Fase 2 — Honeypot en VPS

- [x] Contratar la VPS y preparar el sistema.
- [x] Configurar Tailscale entre la VPS y el laboratorio.
- [x] Verificar la conectividad y los puertos necesarios a través del túnel.
- [x] Instalar T-Pot (perfil mini) en la VPS.
- [x] Verificar el arranque de los contenedores de honeypots.
- [x] Instalar el agente Wazuh en la VPS.
- [x] Configurar la recogida de logs de T-Pot mediante `localfile` u otro mecanismo compatible con la fuente de logs.
- [x] Validar la llegada de eventos de T-Pot al dashboard de Wazuh.

### Fase 3 — Detección

- [ ] Crear reglas de detección para Cowrie.
- [ ] Crear reglas de detección para Dionaea.
- [ ] Crear reglas de detección para Suricata.
- [ ] Documentar las reglas y su mapeo a MITRE ATT&CK.
- [ ] Añadir pruebas con eventos de ejemplo.

### Fase 4 — Visualización y respuesta

- [ ] Exportar dashboards personalizados y versionarlos cuando sea viable.
- [ ] Evaluar y probar Active Response en condiciones controladas.
- [ ] Integrar enriquecimiento con fuentes como VirusTotal, AbuseIPDB u OTX, respetando sus límites y condiciones de uso.

---

## 9. Documentación adicional

- [Instalación detallada](docs/01-installation.md)
- [Arquitectura](docs/02-architecture.md)
- [Validación del agente](docs/03-agent-validation.md)
- [Incidentes documentados](docs/04-incidents.md)
- [Troubleshooting](docs/05-troubleshooting.md)
- [Configuración de la VPS](docs/06-vps-setup.md)
- [Instalación de T-Pot](docs/07-tpot-installation.md)
- [Agente Wazuh en la VPS](docs/08-wazuh-agent-vps.md)
- [Decisiones de diseño (ADR)](docs/adr/)
- [Decisiones de diseño (ADR)](docs/adr/)

---

## 10. Incidencias documentadas

Durante el desarrollo del laboratorio se han registrado incidencias y tareas de troubleshooting en [`docs/04-incidents.md`](docs/04-incidents.md).

### Fase 1 — Wazuh base

1. Conflicto al instalar `wazuh-agent` y `wazuh-manager` en el mismo host.
2. Dashboard afectado tras reinstalar el manager (`403` y `version_conflict`).
3. Manager que no arranca por timeout de systemd.
4. Locks huérfanos en `/var/ossec/var/run/` después de un timeout.
5. Indexer que no arranca por timeout de systemd.

### Fase 2 — VPS y Tailscale

6. Problema de DNS tras cambiar el adaptador de red de VirtualBox.
7. Autenticación de Tailscale mediante URL que no se sincroniza como se esperaba.
8. Sesión de Tailscale que caduca entre sesiones SSH.
9. Problemas de compatibilidad de T-Pot con la versión de Ubuntu probada; consultar el informe de incidencia para conocer el entorno y el error exactos.
10. Instalación de T-Pot rechazada al ejecutarse como `root`.
11. Problemas de autenticación SSH por ausencia de una clave configurada en el manager.
12. Agente en bucle `Never connected` por auto-enrollment
13. Error de `cowrie.json` — T-Pot no usa Cowrie en esta versión
14. Mismatch de versión agente (4.14.9) vs manager (4.14.8)

Consulta el registro de incidencias para conocer el contexto, el diagnóstico y la resolución aplicada en cada caso.

---

## Licencia

MIT — consulta el archivo [LICENSE](LICENSE).
