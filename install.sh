#!/bin/bash
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
    
    echo ""
    log_info "Settings:"
    echo "   Address: ${SERVER_ADDRESS}"
    echo "   Protocol: ${PROTOCOL}"
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
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker installed."
}

install_docker_compose() {
    if command -v docker compose &> /dev/null; then
        log_success "Docker Compose is installed."
        return
    fi
    log_info "Installing Docker Compose..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
    log_success "Docker Compose installed."
}

generate_secrets() {
    log_info "Generating security keys..."
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
    REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
    log_success "Keys generated."
}

create_env_file() {
    log_info "Creating .env file..."
    cat > .env <<EOF
DOMAIN=${SERVER_ADDRESS}
SERVER_ADDRESS=${SERVER_ADDRESS}
PROTOCOL=${PROTOCOL}
IP_MODE=${IP_MODE}
REGISTRATION_SHARED_SECRET=${REGISTRATION_SECRET}
POSTGRES_USER=dendrite
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=dendrite
LETSENCRYPT_EMAIL=${ADMIN_EMAIL}
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
    
    # Replace domain placeholder
    sed -i "s|\${DOMAIN}|${SERVER_ADDRESS}|g" config/element-config.json
    
    # Always use https (self-signed for IP, Let's Encrypt for domain)
    sed -i "s|http://${SERVER_ADDRESS}|https://${SERVER_ADDRESS}|g" config/element-config.json
    
    log_success "Element configured."
}

update_dendrite_config() {
    log_info "Configuring Dendrite..."
    
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
        log_info "Pulling Dendrite image (this may take a while)..."
        docker pull matrixdotorg/dendrite-monolith:latest
        
        log_info "Running key generation..."
        docker run --rm \
            --entrypoint /usr/bin/generate-keys \
            -v "$(pwd)/dendrite:/etc/dendrite" \
            matrixdotorg/dendrite-monolith:latest \
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
    log_info "Pulling Docker images (this may take a while)..."
    docker compose pull
    
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
get_user_input
install_docker
install_docker_compose
generate_secrets
create_env_file
setup_caddyfile
update_element_config
update_dendrite_config
generate_matrix_key
start_services
check_services
print_success
