#!/usr/bin/env bash
# Zanjir - Matrix Server Auto-Installer
# Optimized for Iranian VPS
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}       Zanjir - Matrix Server Installer          ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
}

log_info() { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

normalize_line_endings() {
    if ! command -v sed &> /dev/null; then
        return 0
    fi

    local files=(
        "scripts/generate-keys.sh"
        "docker-compose.yml"
        "Caddyfile"
        "Caddyfile.ip-mode"
        "dendrite/dendrite.yaml"
        "config/element-config.json"
    )

    local f
    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            sed -i 's/\r$//' "$f" 2>/dev/null || true
        fi
    done
}

load_env_if_exists() {
    if [ -f ".env" ]; then
        set -a
        . ./.env
        set +a
    fi
}

is_dockerhub_restriction_error() {
    local text=$1
    echo "$text" | grep -Eqi '403 Forbidden|export control regulations|Since Docker is a US company'
}

json_array_from_csv() {
    local csv=$1
    python3 - "$csv" <<'PY'
import json, sys
csv = sys.argv[1]
parts = [p.strip() for p in csv.replace(";", ",").split(",")]
parts = [p for p in parts if p]
print(json.dumps(parts))
PY
}

configure_docker_registry_mirrors() {
    local mirrors_csv=$1
    if [ -z "$mirrors_csv" ]; then
        return 1
    fi

    local mirrors_json
    if command -v python3 &> /dev/null; then
        mirrors_json=$(json_array_from_csv "$mirrors_csv")
    else
        local cleaned
        cleaned=$(echo "$mirrors_csv" | tr ';' ',' | tr -s ' ')
        local IFS=,
        read -ra _parts <<< "$cleaned"
        local json="["
        local first=1
        for p in "${_parts[@]}"; do
            p=$(echo "$p" | xargs)
            [ -z "$p" ] && continue
            if [ "$first" -eq 0 ]; then
                json+=","
            fi
            first=0
            json+="\"$p\""
        done
        json+="]"
        mirrors_json="$json"
    fi

    log_info "Configuring Docker registry mirrors..."
    mkdir -p /etc/docker

    local daemon_file="/etc/docker/daemon.json"
    if [ -f "$daemon_file" ]; then
        cp -a "$daemon_file" "${daemon_file}.bak.$(date +%s)" 2>/dev/null || true
    fi

    if command -v python3 &> /dev/null; then
        python3 - "$daemon_file" "$mirrors_json" <<'PY'
import json, sys, pathlib, re

daemon_file = pathlib.Path(sys.argv[1])
mirrors = json.loads(sys.argv[2])

data = {}
if daemon_file.exists():
    try:
        raw = daemon_file.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        data = {}

def insecure_from_url(url: str) -> str:
    url = re.sub(r"^https?://", "", url)
    url = url.split("/", 1)[0]
    return url

data["registry-mirrors"] = mirrors
data["insecure-registries"] = sorted({insecure_from_url(u) for u in mirrors})

daemon_file.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    else
        cat > "$daemon_file" <<EOF
{
  "registry-mirrors": $mirrors_json,
  "insecure-registries": $(echo "$mirrors_json" | sed -E 's#https?://##g;s#/[^"]*##g')
}
EOF
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart docker
    log_success "Docker mirrors configured."
}

ensure_docker_registry_access() {
    local mirrors_csv="${DOCKER_REGISTRY_MIRRORS:-${DOCKER_REGISTRY_MIRROR:-}}"
    if [ -n "$mirrors_csv" ]; then
        configure_docker_registry_mirrors "$mirrors_csv" || true
        return 0
    fi

    load_env_if_exists
    local probe_image="${DOCKER_PROBE_IMAGE:-hello-world:latest}"

    set +e
    local pull_output
    pull_output=$(docker pull "$probe_image" 2>&1)
    local pull_exit=$?
    set -e

    if [ "$pull_exit" -eq 0 ]; then
        return 0
    fi

    if ! is_dockerhub_restriction_error "$pull_output"; then
        log_warning "Docker pull failed (not a sanctions-style 403). Continuing..."
        return 0
    fi

    log_warning "Docker Hub appears restricted from this server IP. Applying Iran-friendly mirrors..."

    local default_mirrors="https://docker.arvancloud.ir,https://registry.docker.ir,https://docker.iranserver.com,https://mirror-docker.runflare.com"
    configure_docker_registry_mirrors "$default_mirrors"
}

docker_pull_with_mirror_fallback() {
    local image=$1

    set +e
    local out
    out=$(docker pull "$image" 2>&1)
    local code=$?
    set -e

    if [ "$code" -eq 0 ]; then
        return 0
    fi

    if is_dockerhub_restriction_error "$out"; then
        ensure_docker_registry_access
        docker pull "$image"
        return $?
    fi

    echo "$out" >&2
    return "$code"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run with sudo"
        exit 1
    fi
}

is_ip_address() {
    local ip=$1
    [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

get_user_input() {
    echo ""
    log_info "Configuration questions..."
    echo ""
    
    # Get server address
    while true; do
        read -p "Server address (domain or IP): " SERVER_ADDRESS
        if [ -n "$SERVER_ADDRESS" ]; then
            break
        fi
        log_error "Address cannot be empty!"
    done
    
    # Detect IP mode
    if is_ip_address "$SERVER_ADDRESS"; then
        IP_MODE=true
        PROTOCOL="https"
        log_warning "IP mode detected. Self-signed SSL will be used."
        log_warning "Browser will show security warning - click Advanced > Proceed."
    else
        IP_MODE=false
        PROTOCOL="https"
        log_success "Domain mode. SSL will be obtained from Let's Encrypt."
    fi
    
    # Get admin email (only for domain mode)
    if [ "$IP_MODE" = false ]; then
        read -p "Admin email (for SSL): " ADMIN_EMAIL
        if [ -z "$ADMIN_EMAIL" ]; then
            ADMIN_EMAIL="admin@${SERVER_ADDRESS}"
        fi
    else
        ADMIN_EMAIL=""
    fi
    
    # Get custom port (optional)
    while true; do
        read -p "HTTPS port (default: 443): " HTTPS_PORT
        if [ -z "$HTTPS_PORT" ]; then
            HTTPS_PORT=443
            break
        elif [[ "$HTTPS_PORT" =~ ^[0-9]+$ ]] && [ "$HTTPS_PORT" -ge 1 ] && [ "$HTTPS_PORT" -le 65535 ]; then
            break
        else
            log_error "Invalid port! Must be between 1-65535"
        fi
    done
    
    # Calculate HTTP port (HTTPS_PORT - 363, but ensure it's valid)
    HTTP_PORT=$((HTTPS_PORT - 363))
    if [ "$HTTP_PORT" -lt 1 ]; then
        HTTP_PORT=80
    fi
    
    echo ""
    log_info "Settings:"
    echo "   Address: ${SERVER_ADDRESS}"
    echo "   Protocol: ${PROTOCOL}"
    echo "   HTTPS Port: ${HTTPS_PORT}"
    echo "   HTTP Port: ${HTTP_PORT}"
    if [ "$IP_MODE" = false ]; then
        echo "   Email: ${ADMIN_EMAIL}"
    fi
    echo ""
    
    read -p "Is this correct? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_error "Cancelled."
        exit 1
    fi
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker is installed."
        return
    fi
    log_info "Installing Docker..."
    
    # Try official script first, fallback to apt
    if curl -fsSL https://get.docker.com | sh 2>/dev/null; then
        log_success "Docker installed from official script."
    else
        log_warning "Official Docker install failed, trying apt..."
        apt-get update -qq
        apt-get install -y -qq docker.io
    fi
    
    systemctl enable docker
    systemctl start docker
    log_success "Docker installed."
}

install_docker_compose() {
    # Check if docker compose works
    if docker compose version &> /dev/null; then
        log_success "Docker Compose is installed."
        return
    fi
    
    log_info "Installing Docker Compose..."
    
    # Try apt plugin first
    if apt-get update -qq && apt-get install -y -qq docker-compose-plugin 2>/dev/null; then
        log_success "Docker Compose plugin installed."
        return
    fi
    
    # Fallback: download binary directly
    log_warning "Plugin not available, downloading binary..."
    COMPOSE_VERSION="v2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create plugin symlink
    mkdir -p /usr/lib/docker/cli-plugins/
    ln -sf /usr/local/bin/docker-compose /usr/lib/docker/cli-plugins/docker-compose
    
    if docker compose version &> /dev/null; then
        log_success "Docker Compose installed."
    else
        log_error "Docker Compose installation failed!"
        exit 1
    fi
}

generate_secrets() {
    log_info "Generating security keys..."
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
    REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
    TURN_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
    log_success "Keys generated."
}

create_env_file() {
    log_info "Creating .env file..."
    cat > .env <<EOF
DOMAIN=${SERVER_ADDRESS}
SERVER_ADDRESS=${SERVER_ADDRESS}
PROTOCOL=${PROTOCOL}
IP_MODE=${IP_MODE}
HTTPS_PORT=${HTTPS_PORT}
HTTP_PORT=${HTTP_PORT}
REGISTRATION_SHARED_SECRET=${REGISTRATION_SECRET}
TURN_SECRET=${TURN_SECRET}
POSTGRES_USER=dendrite
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=dendrite
LETSENCRYPT_EMAIL=${ADMIN_EMAIL}
POSTGRES_IMAGE=postgres:15-alpine
DENDRITE_IMAGE=matrixdotorg/dendrite-monolith:latest
ELEMENT_IMAGE=vectorim/element-web:v1.11.50
ELEMENT_COPY_IMAGE=vectorim/element-web:v1.11.50
CADDY_IMAGE=caddy:2-alpine
EOF
    chmod 600 .env
    log_success ".env file created."
}

setup_caddyfile() {
    log_info "Setting up Caddy..."
    if [ "$IP_MODE" = true ]; then
        cp Caddyfile.ip-mode Caddyfile.active
    else
        cp Caddyfile Caddyfile.active
    fi
    log_success "Caddy configured."
}

update_element_config() {
    log_info "Configuring Element..."
    
    # Reset config from git to ensure placeholders exist
    git checkout -- config/element-config.json 2>/dev/null || true
    
    # Replace domain placeholder
    sed -i "s|\${DOMAIN}|${SERVER_ADDRESS}|g" config/element-config.json
    
    # Always use https (self-signed for IP, Let's Encrypt for domain)
    sed -i "s|http://${SERVER_ADDRESS}|https://${SERVER_ADDRESS}|g" config/element-config.json
    
    log_success "Element configured."
}

update_dendrite_config() {
    log_info "Configuring Dendrite..."
    
    # Reset config from git to ensure placeholders exist
    git checkout -- dendrite/dendrite.yaml 2>/dev/null || true
    
    # Now replace placeholders
    sed -i "s/\${DOMAIN}/${SERVER_ADDRESS}/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_USER}/dendrite/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_PASSWORD}/${POSTGRES_PASSWORD}/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_DB}/dendrite/g" dendrite/dendrite.yaml
    sed -i "s/\${REGISTRATION_SHARED_SECRET}/${REGISTRATION_SECRET}/g" dendrite/dendrite.yaml
    
    # IP mode uses port 443 with self-signed SSL
    if [ "$IP_MODE" = true ]; then
        sed -i "s|:443|:443|g" dendrite/dendrite.yaml
    fi
    log_success "Dendrite configured."
}

generate_matrix_key() {
    log_info "Generating Matrix signing key..."
    if [ ! -f "dendrite/matrix_key.pem" ]; then
        load_env_if_exists
        ensure_docker_registry_access
        local dendrite_image="${DENDRITE_IMAGE:-matrixdotorg/dendrite-monolith:latest}"

        log_info "Pulling Dendrite image (this may take a while)..."
        docker_pull_with_mirror_fallback "$dendrite_image"
        
        log_info "Running key generation..."
        docker run --rm \
            --entrypoint /usr/bin/generate-keys \
            -v "$(pwd)/dendrite:/etc/dendrite" \
            "$dendrite_image" \
            --private-key /etc/dendrite/matrix_key.pem
        
        if [ -f "dendrite/matrix_key.pem" ]; then
            chmod 600 dendrite/matrix_key.pem
            log_success "Matrix key generated."
        else
            log_error "Failed to generate Matrix key!"
            exit 1
        fi
    else
        log_warning "Matrix key already exists."
    fi
}

start_services() {
    ensure_docker_registry_access
    log_info "Pulling Docker images (this may take a while)..."
    set +e
    local pull_out
    pull_out=$(docker compose pull 2>&1)
    local pull_code=$?
    set -e

    if [ "$pull_code" -ne 0 ]; then
        if is_dockerhub_restriction_error "$pull_out"; then
            ensure_docker_registry_access
            docker compose pull
        else
            echo "$pull_out" >&2
            exit "$pull_code"
        fi
    fi
    
    log_info "Copying Element files..."
    docker compose run --rm element-copy
    
    log_info "Starting services..."
    docker compose up -d postgres
    
    log_info "Waiting for PostgreSQL to be ready..."
    sleep 10
    
    docker compose up -d dendrite element caddy
    
    log_info "Waiting for services to start..."
    sleep 5
    
    log_success "Services started!"
}

check_services() {
    log_info "Checking service status..."
    docker compose ps
}

print_success() {
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}          Installation Complete!                 ${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo "URL: ${PROTOCOL}://${SERVER_ADDRESS}"
    
    if [ "$IP_MODE" = true ]; then
        echo ""
        echo -e "${YELLOW}Warning: Using self-signed SSL certificate.${NC}"
        echo -e "${YELLOW}Browser will show security warning - click Advanced > Proceed.${NC}"
    fi
    
    echo ""
    echo "To create an admin user:"
    echo ""
    echo "docker exec -it zanjir-dendrite /usr/bin/create-account \\"
    echo "    --config /etc/dendrite/dendrite.yaml \\"
    echo "    --username YOUR_USERNAME \\"
    echo "    --admin"
    echo ""
    echo "Registration secret (for API): ${REGISTRATION_SECRET}"
    echo ""
    echo "All settings saved in .env file."
    echo ""
}

# Main
print_banner
check_root
normalize_line_endings
get_user_input
install_docker
install_docker_compose
ensure_docker_registry_access
generate_secrets
create_env_file
setup_caddyfile
update_element_config
update_dendrite_config
generate_matrix_key
start_services
check_services
print_success
