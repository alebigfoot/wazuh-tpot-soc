# ADR 0002: Tailscale en lugar de WireGuard directo

## Estado

Aceptado

## Fecha

2026-10-14

## Contexto

Para conectar la VPS pública (donde correrá TPOT) con el manager Wazuh local
es necesario un túnel seguro. Las dos opciones consideradas fueron:

1. **WireGuard directo** — requiere abrir un puerto UDP en el router local
2. **Tailscale** — solución gestionada basada en WireGuard con NAT traversal

El laboratorio está detrás de una conexión doméstica con las siguientes
restricciones:

- **No hay acceso al panel del router** para abrir puertos
- Posible CGNAT en la conexión del ISP
- Se necesita una solución que funcione sin tocar la infraestructura de red

## Decisión

Usar **Tailscale** como capa de red entre la VPS y el manager local.

## Motivos

- **No requiere abrir puertos** en el router (NAT traversal automático)
- **Funciona detrás de CGNAT**
- **Basado en WireGuard** → misma criptografía, mismo rendimiento
- **Conexión directa (P2P)** cuando es posible, sin relay
- **Gestión centralizada** de dispositivos vía panel web
- **Gratis** para uso personal (hasta 100 dispositivos)
- **Instalación trivial** (un comando por máquina)
- **Cifrado punto a punto** verificado
- **Auth keys** permiten automatizar el registro de servidores

## Consecuencias

### Positivas

- Túnel funcional en menos de 5 minutos por máquina
- Cero configuración de red en el router
- IPs estables (`100.x.y.z`) accesibles desde cualquier ubicación
- Fácil de añadir más nodos en el futuro

### Negativas

- **Dependencia de un servicio externo** (Tailscale Inc.)
- La metadata de conexión pasa por los servidores de Tailscale (control plane)
- Si Tailscale cae, el túnel se pierde (aunque los datos van P2P cifrados)
- Requiere cuenta y autenticación por máquina

## Alternativas descartadas

### WireGuard directo

Descartado por **imposibilidad de abrir puertos en el router doméstico**.
Sin acceso al panel del router, no hay forma de redirigir el puerto UDP
que WireGuard necesita.

### VPN comercial (NordVPN Meshnet, etc.)

Descartado por menor control y mayor dependencia. Tailscale ofrece mejor
integración para uso técnico.

### ZeroTier

Alternativa viable pero con configuración más compleja y peor integración
con el ecosistema Linux moderno. Tailscale es más directo.

### Exponer el manager a Internet

**Completamente descartado.** Abrir el puerto 1514 a Internet expone el
manager Wazuh a intentos de registro no autorizados. Riesgo de seguridad
inaceptable.

## Notas

Si en el futuro se obtiene acceso al router o una IP pública dedicada, se
puede migrar a WireGuard directo sin cambiar la topología lógica: la IP del
túnel cambiaría de `100.x.y.z` a la nueva red, y solo habría que actualizar
las referencias en las configuraciones.

Comando de verificación del estado del túnel:

```bash
tailscale status
tailscale ping <TAILSCALE_IP_MGR>
