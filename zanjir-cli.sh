#!/usr/bin/env bash
# Zanjir - Management CLI Tool
# Beautiful command-line interface for managing your Zanjir Matrix server

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Project directory
PROJECT_DIR="${PROJECT_DIR:-/root/zanjir}"

# Check if running as root for certain operations
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This operation requires root privileges. Please run with sudo.${NC}"
        exit 1
    fi
}

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    if command -v figlet &> /dev/null; then
        figlet -f standard "Zanjir" 2>/dev/null || echo "╔═══════════════════════════╗
║                           ║
║      Z A N J I R ⛓️       ║
║                           ║
╚═══════════════════════════╝"
    else
        echo "╔═══════════════════════════╗
║                           ║
║      Z A N J I R ⛓️       ║
║                           ║
╚═══════════════════════════╝"
    fi
    echo -e "${NC}"
    echo -e "${BOLD}${WHITE}Matrix Server Management Tool${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Show status
show_status() {
    echo -e "${BOLD}${CYAN}📊 Service Status${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        return 1
    fi
    
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed (directory not found: $PROJECT_DIR)${NC}"
        return 1
    }
    
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || {
        echo -e "${YELLOW}⚠️  No services running${NC}"
        return 1
    }
    
    echo ""
    echo -e "${GREEN}✓ Zanjir is running${NC}"
    
    # Show URL if .env exists
    if [ -f .env ]; then
        source .env
        echo -e "${BOLD}URL:${NC} ${CYAN}${PROTOCOL}://${DOMAIN}${NC}"
    fi
}

# Show logs
show_logs() {
    local service=$1
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    echo -e "${BOLD}${CYAN}📝 Logs for ${service:-all services}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -z "$service" ]; then
        docker compose logs --tail=50 -f
    else
        docker compose logs "$service" --tail=50 -f
    fi
}

# Restart services
restart_services() {
    check_root
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    echo -e "${YELLOW}🔄 Restarting services...${NC}"
    docker compose restart
    echo -e "${GREEN}✓ Services restarted successfully${NC}"
}

# Stop services
stop_services() {
    check_root
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    echo -e "${YELLOW}⏸️  Stopping services...${NC}"
    docker compose stop
    echo -e "${GREEN}✓ Services stopped${NC}"
}

# Start services
start_services() {
    check_root
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    echo -e "${YELLOW}▶️  Starting services...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Services started${NC}"
}

# Update Zanjir
update_zanjir() {
    check_root
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    echo -e "${CYAN}🔄 Updating Zanjir...${NC}"
    echo ""
    
    # Pull latest code
    echo -e "${BLUE}[1/4]${NC} Pulling latest code from GitHub..."
    git pull || {
        echo -e "${RED}❌ Failed to pull updates${NC}"
        return 1
    }
    
    # Pull latest Docker images
    echo -e "${BLUE}[2/4]${NC} Pulling latest Docker images..."
    docker compose pull
    
    # Restart services
    echo -e "${BLUE}[3/4]${NC} Restarting services..."
    docker compose up -d
    
    # Show status
    echo -e "${BLUE}[4/4]${NC} Checking status..."
    sleep 3
    docker compose ps
    
    echo ""
    echo -e "${GREEN}✓ Zanjir updated successfully!${NC}"
}

# Uninstall Zanjir
uninstall_zanjir() {
    check_root
    
    echo -e "${RED}${BOLD}⚠️  WARNING: This will permanently delete all data!${NC}"
    echo -e "${YELLOW}This includes:${NC}"
    echo "  • All user accounts"
    echo "  • All rooms and messages"
    echo "  • All uploaded files"
    echo "  • All configuration"
    echo ""
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}Cancelled.${NC}"
        return 0
    fi
    
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${YELLOW}Directory not found, skipping Docker cleanup${NC}"
    }
    
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${YELLOW}🗑️  Stopping and removing containers...${NC}"
        docker compose down 2>/dev/null || true
        
        echo -e "${YELLOW}🗑️  Removing Docker volumes...${NC}"
        docker volume ls | grep zanjir | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
        
        echo -e "${YELLOW}🗑️  Removing project directory...${NC}"
        cd /
        rm -rf "$PROJECT_DIR"
    fi
    
    echo -e "${YELLOW}🗑️  Removing CLI tool...${NC}"
    rm -f /usr/local/bin/zanjir
    
    echo ""
    echo -e "${GREEN}✓ Zanjir has been completely uninstalled${NC}"
    echo -e "${CYAN}Thank you for using Zanjir!${NC}"
}

# Backup data
backup_data() {
    check_root
    cd "$PROJECT_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Zanjir is not installed${NC}"
        return 1
    }
    
    local backup_file="zanjir-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "${CYAN}💾 Creating backup...${NC}"
    
    # Create backup directory
    mkdir -p ~/zanjir-backups
    
    # Backup volumes
    echo -e "${BLUE}Backing up Docker volumes...${NC}"
    docker run --rm \
        -v zanjir-conduit-data:/data/conduit \
        -v zanjir-caddy-data:/data/caddy \
        -v zanjir-admin-data:/data/admin \
        -v ~/zanjir-backups:/backup \
        ubuntu tar czf "/backup/$backup_file" /data
    
    # Backup .env
    cp .env ~/zanjir-backups/.env-backup-$(date +%Y%m%d-%H%M%S)
    
    echo ""
    echo -e "${GREEN}✓ Backup created: ~/zanjir-backups/$backup_file${NC}"
}

# Show interactive menu
show_menu() {
    print_banner
    
    echo -e "${BOLD}${WHITE}Main Menu:${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} Show Status"
    echo -e "  ${GREEN}2.${NC} View Logs"
    echo -e "  ${GREEN}3.${NC} Restart Services"
    echo -e "  ${GREEN}4.${NC} Start Services"
    echo -e "  ${GREEN}5.${NC} Stop Services"
    echo -e "  ${CYAN}6.${NC} Update Zanjir"
    echo -e "  ${MAGENTA}7.${NC} Backup Data"
    echo -e "  ${RED}8.${NC} Uninstall"
    echo -e "  ${YELLOW}9.${NC} Exit"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -n -e "${BOLD}Select an option [1-9]: ${NC}"
}

# Main menu loop
interactive_mode() {
    while true; do
        show_menu
        read -r choice
        echo ""
        
        case $choice in
            1)
                show_status
                ;;
            2)
                echo -e "${YELLOW}Which service? (conduit/caddy/admin/coturn or press Enter for all):${NC} "
                read -r service
                show_logs "$service"
                ;;
            3)
                restart_services
                ;;
            4)
                start_services
                ;;
            5)
                stop_services
                ;;
            6)
                update_zanjir
                ;;
            7)
                backup_data
                ;;
            8)
                uninstall_zanjir
                exit 0
                ;;
            9)
                echo -e "${CYAN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
    done
}

# Parse command line arguments
case "${1:-}" in
    status)
        print_banner
        show_status
        ;;
    logs)
        print_banner
        show_logs "${2:-}"
        ;;
    restart)
        print_banner
        restart_services
        ;;
    start)
        print_banner
        start_services
        ;;
    stop)
        print_banner
        stop_services
        ;;
    update)
        print_banner
        update_zanjir
        ;;
    backup)
        print_banner
        backup_data
        ;;
    uninstall)
        print_banner
        uninstall_zanjir
        ;;
    --help|-h|help)
        print_banner
        echo -e "${BOLD}Usage:${NC}"
        echo "  zanjir              Interactive menu"
        echo "  zanjir status       Show service status"
        echo "  zanjir logs [svc]   View logs (optionally for specific service)"
        echo "  zanjir restart      Restart all services"
        echo "  zanjir start        Start all services"
        echo "  zanjir stop         Stop all services"
        echo "  zanjir update       Update to latest version"
        echo "  zanjir backup       Backup all data"
        echo "  zanjir uninstall    Completely remove Zanjir"
        echo ""
        ;;
    *)
        interactive_mode
        ;;
esac
