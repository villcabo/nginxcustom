#!/bin/bash

# Function to print formatted messages
function log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if an argument was provided
if [[ -z "$1" ]]; then
  log "Error: You must specify a module as an argument."
  log "Usage: bash build.sh <module> [-nc|--no-cache]"
  exit 1
fi

# Get the module name and determine the corresponding directory
MODULE=$1
DIR="nginx-$MODULE"

# Parse optional flags
NO_CACHE_FLAG=""
if [[ "$2" == "-nc" || "$2" == "--no-cache" ]]; then
  NO_CACHE_FLAG="--no-cache"
fi

# Check if the directory exists
if [[ ! -d "$DIR" ]]; then
  log "Error: The directory '$DIR' does not exist."
  exit 1
fi

log "Starting process for module: $MODULE"
log "Selected directory: $DIR"

# Change to the module directory
cd "$DIR" || { log "Error: Could not change to directory '$DIR'"; exit 1; }

# Extract the Nginx version from the Dockerfile (compatible with format nginx:<version>-alpine)
NGINX_VERSION=$(grep -oP '(?<=FROM nginx:)[^ ]+' "Dockerfile" | head -1)

if [[ -z "$NGINX_VERSION" ]]; then
  log "No Nginx version found in file '$DIR/Dockerfile'. Skipping..."
  exit 1
fi

log "Detected Nginx version: $NGINX_VERSION"

# Define the image name and tag
IMAGE_NAME="${DOCKER_USERNAME:-$USER}/$DIR"
IMAGE_TAG="$NGINX_VERSION-beta"

log "Image name: $IMAGE_NAME"
log "Image tag: $IMAGE_TAG"

# Build the Docker image
log "Starting build for image: $IMAGE_NAME:$IMAGE_TAG"
if docker build $NO_CACHE_FLAG -t "$IMAGE_NAME:$IMAGE_TAG" .; then
  log "Build completed successfully."
else
  log "Error: Image build failed."
  exit 1
fi

# Push the image to Docker Hub
log "Pushing image '$IMAGE_NAME:$IMAGE_TAG' to Docker Hub..."
if docker push "$IMAGE_NAME:$IMAGE_TAG"; then
  log "Image pushed successfully."
else
  log "Error: Could not push the image to Docker Hub."
  exit 1
fi

log "Process completed for module: $MODULE"
