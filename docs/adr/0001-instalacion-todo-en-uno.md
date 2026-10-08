# ADR 0001: Instalación todo-en-uno de Wazuh

## Estado

Aceptado

## Fecha

2026-10-07

## Contexto

Wazuh puede desplegarse en modo distribuido (varios nodos de Indexer, varios
Managers) o en modo todo-en-uno (un solo nodo con todos los componentes). Para
un laboratorio personal con recursos limitados hay que elegir uno antes de
empezar.

El laboratorio dispone de:

- 8 vCPU
- 8 GB RAM
- 50 GB disco
- Ubuntu 22.04 LTS sobre VirtualBox

## Decisión

Instalación todo-en-uno con el script oficial `wazuh-install.sh -a`.

## Motivos

- Los recursos disponibles (8 vCPU / 8 GB RAM) son suficientes para un nodo
  único pero no para un clúster de varios nodos.
- Simplifica la operación: un solo sistema que actualizar, monitorizar y
  respaldar.
- Suficiente para procesar el volumen de eventos de un honeypot personal.
- Reduce el tiempo de montaje de horas a minutos.
- Fácil de destruir y recrear si algo se rompe durante el aprendizaje.

## Consecuencias

### Positivas

- Instalación y mantenimiento simples.
- Menor consumo de recursos.
- Curva de aprendizaje centrada en el uso, no en la administración del clúster.

### Negativas

- Sin alta disponibilidad: si el nodo cae, el SOC cae.
- Escalado vertical limitado por los recursos de la VM.
- No apto para producción.

## Alternativas descartadas

### Modo distribuido

Sobredimensionado para el objetivo del laboratorio. Requeriría al menos 3
nodos (1 Indexer, 1 Manager, 1 Dashboard) o más si se quiere alta
disponibilidad real.

### Wazuh Cloud

No permite control total ni práctica de instalación. El objetivo del
laboratorio es precisamente aprender a desplegar y operar la plataforma.

## Notas

Si en el futuro el laboratorio crece (más agentes, retención más larga, etc.),
se puede migrar a un despliegue distribuido sin pérdida de datos exportando
los índices y reconfigurando los agentes.
