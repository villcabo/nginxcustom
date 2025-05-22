#!/bin/bash

# Función para imprimir mensajes con formato
function log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Verificar si se proporcionó un argumento
if [[ -z "$1" ]]; then
  log "Error: Debes especificar un módulo como argumento."
  log "Uso: bash build.sh <modulo>"
  exit 1
fi

# Obtener el nombre del módulo y determinar el directorio correspondiente
MODULE=$1
DIR="nginx-$MODULE"

# Verificar si el directorio existe
if [[ ! -d "$DIR" ]]; then
  log "Error: El directorio '$DIR' no existe."
  exit 1
fi

log "Iniciando proceso para el módulo: $MODULE"
log "Directorio seleccionado: $DIR"

# Cambiar al directorio del módulo
cd "$DIR" || { log "Error: No se pudo cambiar al directorio '$DIR'"; exit 1; }

# Extraer la versión de Nginx del Dockerfile (compatible con formato nginx:<version>-alpine)
NGINX_VERSION=$(grep -oP '(?<=FROM nginx:)[^ ]+' "Dockerfile" | head -1)

if [[ -z "$NGINX_VERSION" ]]; then
  log "No se encontró una versión de Nginx en el archivo '$DIR/Dockerfile'. Saltando..."
  exit 1
fi

log "Versión de Nginx detectada: $NGINX_VERSION"

# Definir el nombre de la imagen y el tag
IMAGE_NAME="${DOCKER_USERNAME:-$USER}/$DIR"
IMAGE_TAG="$NGINX_VERSION-beta"

log "Nombre de la imagen: $IMAGE_NAME"
log "Tag de la imagen: $IMAGE_TAG"

# Construir la imagen de Docker
log "Iniciando construcción de la imagen: $IMAGE_NAME:$IMAGE_TAG"
if docker build -t "$IMAGE_NAME:$IMAGE_TAG" .; then
  log "Construcción completada exitosamente."
else
  log "Error: La construcción de la imagen falló."
  exit 1
fi

# Subir la imagen a Docker Hub
log "Subiendo la imagen '$IMAGE_NAME:$IMAGE_TAG' a Docker Hub..."
if docker push "$IMAGE_NAME:$IMAGE_TAG"; then
  log "La imagen se subió correctamente."
else
  log "Error: No se pudo subir la imagen a Docker Hub."
  exit 1
fi

log "Proceso completado para el módulo: $MODULE"
