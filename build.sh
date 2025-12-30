#!/bin/bash

# Color and formatting definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Enhanced logging functions with colors and formatting
function print_info() {
  echo -e "${BLUE}${BOLD}ℹ  $1${NC}"
}

function print_success() {
  echo -e "${GREEN}${BOLD}✓  $1${NC}"
}

function print_warning() {
  echo -e "${YELLOW}${BOLD}⚠  $1${NC}"
}

function print_error() {
  echo -e "${RED}${BOLD}✗  $1${NC}"
}

function print_action() {
  echo -e "${BOLD}▶  $1${NC}"
}

function print_preview() {
  echo -e "${YELLOW}${BOLD}👁  PREVIEW: $1${NC}"
}

function confirm_action() {
  local message="$1"
  echo -e "${BOLD}$message [y/N]:${NC} \c"
  read -r response
  case "$response" in
    [yY][eE][sS]|[yY]) 
      return 0
      ;;
    *)
      echo
      print_warning "Build cancelled by user"
      return 1
      ;;
  esac
}

function show_help() {
  echo -e "${BOLD}${BLUE}🐳 Nginx Docker Builder${NC}\n"
  
  echo -e "${BOLD}USAGE:${NC}"
  echo -e "  ${GREEN}$0${NC} ${YELLOW}<module>${NC} ${BLUE}[options]${NC}\n"
  
  echo -e "${BOLD}DESCRIPTION:${NC}"
  echo -e "  Build Docker images for Nginx modules with custom configurations.\n"
  
  echo -e "${BOLD}ARGUMENTS:${NC}"
  echo -e "  ${YELLOW}<module>${NC}              Module name (e.g., ${GREEN}logrotate${NC}, ${GREEN}logrotate-geoip${NC})\n"
  
  echo -e "${BOLD}OPTIONS:${NC}"
  echo -e "  ${BLUE}-nc${NC}, ${BLUE}--no-cache${NC}      Build without using Docker cache"
  echo -e "  ${BLUE}-h${NC}, ${BLUE}--help${NC}           Show this help message\n"
  
  echo -e "${BOLD}EXAMPLES:${NC}"
  echo -e "  ${GREEN}./$0${NC} ${YELLOW}logrotate${NC}"
  echo -e "  ${GREEN}./$0${NC} ${YELLOW}logrotate-geoip${NC} ${BLUE}--no-cache${NC}"
  echo -e "  ${GREEN}./$0${NC} ${YELLOW}logrotate${NC} ${BLUE}-nc${NC}\n"
  
  echo -e "${BOLD}AVAILABLE MODULES:${NC}"
  echo -e "  ${GREEN}▶${NC} logrotate"
  echo -e "  ${GREEN}▶${NC} logrotate-geoip\n"
}

# Function to parse command line arguments
function parse_arguments() {
  MODULE=""
  NO_CACHE_FLAG=""
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      -nc|--no-cache)
        NO_CACHE_FLAG="--no-cache"
        shift
        ;;
      -*)
        print_error "Unknown option $1"
        show_help
        exit 1
        ;;
      *)
        if [[ -z "$MODULE" ]]; then
          MODULE="$1"
        else
          print_error "Multiple modules specified"
          show_help
          exit 1
        fi
        shift
        ;;
    esac
  done
  
  if [[ -z "$MODULE" ]]; then
    show_help
    exit 0
  fi
}

# Function to validate module directory
function validate_module() {
  local module="$1"
  local dir="nginx-$module"
  
  if [[ ! -d "$dir" ]]; then
    print_error "The directory '$dir' does not exist."
    exit 1
  fi
  
  echo "$dir"
}

# Function to extract Nginx version from Dockerfile
function get_nginx_version() {
  local dockerfile="$1/Dockerfile"
  local nginx_version
  
  nginx_version=$(grep -oP '(?<=FROM nginx:)[^ ]+' "$dockerfile" | head -1)
  
  if [[ -z "$nginx_version" ]]; then
    print_error "No Nginx version found in file '$dockerfile'. Skipping..."
    exit 1
  fi
  
  echo "$nginx_version"
}

# Function to build Docker image
function build_image() {
  local image_name="$1"
  local image_tag="$2"
  local no_cache_flag="$3"
  
  # Show formatted preview
  echo
  echo -e "${YELLOW}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${YELLOW}${BOLD}              BUILD PREVIEW${NC}"
  echo -e "${YELLOW}${BOLD}════════════════════════════════════════${NC}"
  
  # Extract module name from image name and nginx version from tag
  local module_name=$(basename "$image_name" | sed 's/nginx-//')
  local nginx_version=$(echo "$image_tag" | sed 's/-beta$//')
  
  echo -e "${BOLD}Module:${NC} ${GREEN}$module_name${NC}"
  echo -e "${BOLD}Nginx Version:${NC} ${GREEN}$nginx_version${NC}"
  echo -e "${BOLD}Build Context:${NC} ${BLUE}$(pwd)${NC}"
  echo -e "${BOLD}Docker User:${NC} ${YELLOW}${DOCKER_USERNAME:-$USER}${NC}"
  
  if [[ -n "$no_cache_flag" ]]; then
    echo -e "${BOLD}Cache Mode:${NC} ${RED}${BOLD}Disabled${NC} ${RED}(--no-cache)${NC}"
  else
    echo -e "${BOLD}Cache Mode:${NC} ${GREEN}${BOLD}Enabled${NC}"
  fi
  
  echo
  echo -e "${BOLD}Image to create:${NC}"
  echo -e "  ${GREEN}▸${NC} ${BOLD}$image_name:$image_tag${NC}"
  echo -e "    ${BLUE}→${NC} Registry: ${GREEN}$image_name${NC}"
  echo -e "    ${BLUE}→${NC} Tag: ${GREEN}$image_tag${NC}"
  echo
  echo -e "${BOLD}Docker Command:${NC} ${BLUE}docker build $no_cache_flag -t $image_name:$image_tag .${NC}"
  echo
  if ! confirm_action "Continue with build?"; then
    exit 0
  fi
  echo
  
  print_action "Starting build for image: $image_name:$image_tag"
  
  if docker build $no_cache_flag -t "$image_name:$image_tag" .; then
    print_success "Build completed successfully."
  else
    print_error "Image build failed."
    exit 1
  fi
}

# Main function
function main() {
  parse_arguments "$@"
  
  local dir
  dir=$(validate_module "$MODULE")
  
  print_info "Starting process for module: $MODULE"
  
  # Change to the module directory
  cd "$dir" || { print_error "Could not change to directory '$dir'"; exit 1; }
  
  local nginx_version
  nginx_version=$(get_nginx_version ".")
  
  # Define the image name and tag
  local image_name="${DOCKER_USERNAME:-$USER}/$dir"
  local image_tag="$nginx_version-beta"
  
  # Build the Docker image
  build_image "$image_name" "$image_tag" "$NO_CACHE_FLAG"
  
  # Push is commented out - uncomment if needed
  # print_preview "About to push image '$image_name:$image_tag' to Docker Hub"
  # if confirm_action "Do you want to push the image to Docker Hub?"; then
  #   print_action "Pushing image '$image_name:$image_tag' to Docker Hub..."
  #   if docker push "$image_name:$image_tag"; then
  #     print_success "Image pushed successfully."
  #   else
  #     print_error "Could not push the image to Docker Hub."
  #     exit 1
  #   fi
  # fi
  
  print_success "Process completed for module: $MODULE"
}

# Run main function with all arguments
main "$@"
