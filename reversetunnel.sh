#!/bin/bash

BACKHAUL_BIN="/usr/local/bin/backhaul"
BACKHAUL_ARCHIVE="/tmp/backhaul_linux_amd64.tar.gz"
BACKHAUL_URL="https://github.com/musix/backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
SNIFFER_LOG="/root/backhaul.json"
TUNNEL_DB="/root/.reversetunnel_db.json"

declare -A COLORS=(
    [RESET]='\033[0m'
    [RED]='\033[38;5;196m'
    [GREEN]='\033[38;5;46m'
    [PINK]='\033[38;5;213m'
    [CYAN]='\033[38;5;51m'
    [YELLOW]='\033[38;5;226m'
    [ORANGE]='\033[38;5;208m'
    [BLUE]='\033[38;5;33m'
    [OLIVE]='\033[38;5;142m'
    [PURPLE]='\033[38;5;93m'
)

print_color() {
    local color="$1"
    local text="$2"
    echo -e "${COLORS[$color]}${text}${COLORS[RESET]}"
}

clear_screen() {
    printf "\033c"
}

print_logo() {
    echo ""
    echo -e "${COLORS[CYAN]}  ██████╗ ███████╗${COLORS[PINK]}██╗   ██╗${COLORS[YELLOW]}███████╗${COLORS[ORANGE]}██████╗ ███████╗${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}  ██╔══██╗██╔════╝${COLORS[PINK]}██║   ██║${COLORS[YELLOW]}██╔════╝${COLORS[ORANGE]}██╔══██╗██╔════╝${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}  ██████╔╝█████╗  ${COLORS[PINK]}██║   ██║${COLORS[YELLOW]}█████╗  ${COLORS[ORANGE]}██████╔╝███████╗${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}  ██╔══██╗██╔══╝  ${COLORS[PINK]}╚██╗ ██╔╝${COLORS[YELLOW]}██╔══╝  ${COLORS[ORANGE]}██╔══██╗╚════██║${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}  ██║  ██║███████╗${COLORS[PINK]} ╚████╔╝ ${COLORS[YELLOW]}███████╗${COLORS[ORANGE]}██║  ██║███████║${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}  ╚═╝  ╚═╝╚══════╝${COLORS[PINK]}  ╚═══╝  ${COLORS[YELLOW]}╚══════╝${COLORS[ORANGE]}╚═╝  ╚═╝╚══════╝${COLORS[RESET]}"
    echo ""
    print_color "PURPLE" "  ⚡ R E V E R S E   T U N N E L   M A N A G E R ⚡"
    print_color "ORANGE" "  ═════════════════════════════════════════════════════"
    echo ""
    
    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_color "GREEN" "  ✓ Backhaul Installed"
    else
        print_color "RED" "  ✗ Backhaul Not Installed"
    fi
    echo ""
}

print_header() {
    clear_screen
    print_logo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "RED" "✗ This script must be run as root"
        exit 1
    fi
}

press_enter() {
    echo ""
    print_color "ORANGE" "Press Enter to continue..."
    read -r
}

init_tunnel_db() {
    if [[ ! -f "$TUNNEL_DB" ]]; then
        echo "{}" > "$TUNNEL_DB"
    fi
}

save_tunnel_info() {
    local name="$1"
    local service_name="$2"
    local port="$3"
    local dest_ip="$4"
    local protocol="$5"
    local tunnel_type="$6"
    
    init_tunnel_db
    
    local temp_file=$(mktemp)
    jq --arg name "$name" \
       --arg service "$service_name" \
       --arg port "$port" \
       --arg dest "$dest_ip" \
       --arg proto "$protocol" \
       --arg ttype "$tunnel_type" \
       '.[$service] = {name: $name, port: $port, destination: $dest, protocol: $proto, type: $ttype}' \
       "$TUNNEL_DB" > "$temp_file" 2>/dev/null || echo "{\"$service_name\": {\"name\": \"$name\", \"port\": \"$port\", \"destination\": \"$dest_ip\", \"protocol\": \"$protocol\", \"type\": \"$tunnel_type\"}}" > "$temp_file"
    
    mv "$temp_file" "$TUNNEL_DB"
}

get_tunnel_info() {
    local service_name="$1"
    init_tunnel_db
    jq -r --arg service "$service_name" '.[$service] // empty' "$TUNNEL_DB" 2>/dev/null
}

delete_tunnel_info() {
    local service_name="$1"
    init_tunnel_db
    
    local temp_file=$(mktemp)
    jq --arg service "$service_name" 'del(.[$service])' "$TUNNEL_DB" > "$temp_file" 2>/dev/null
    mv "$temp_file" "$TUNNEL_DB"
}

check_port_in_use() {
    local port="$1"
    if ss -tuln | grep -q ":${port} "; then
        return 0
    else
        return 1
    fi
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

generate_token() {
    openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p
}

get_next_web_port() {
    local start_port=2060
    local used_ports=$(grep -h "web_port" /root/*.toml 2>/dev/null | awk '{print $3}' | sort -n | uniq)
    
    while true; do
        if ! echo "$used_ports" | grep -qx "$start_port"; then
            echo "$start_port"
            return
        fi
        ((start_port++))
    done
}

list_tunnels() {
    local tunnels=()
    for service in /etc/systemd/system/reverse-*.service; do
        if [[ -f "$service" ]]; then
            local name=$(basename "$service" .service)
            tunnels+=("$name")
        fi
    done
    echo "${tunnels[@]}"
}

install_backhaul() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  Installing Backhaul v0.6.5"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_color "YELLOW" "⚠ Backhaul is already installed"
        print_color "BLUE" "Do you want to reinstall? (yes/no)"
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            return
        fi
    fi
    
    clear_screen
    print_logo
    print_color "PINK" "→ Downloading Backhaul..."
    if ! wget -q --show-progress "$BACKHAUL_URL" -O "$BACKHAUL_ARCHIVE"; then
        clear_screen
        print_logo
        print_color "RED" "✗ Download failed"
        press_enter
        return
    fi
    
    clear_screen
    print_logo
    print_color "CYAN" "→ Extracting archive..."
    rm -f "$BACKHAUL_BIN"
    if ! tar -xzf "$BACKHAUL_ARCHIVE" -C /tmp/; then
        print_color "RED" "✗ Extraction failed"
        rm -f "$BACKHAUL_ARCHIVE"
        press_enter
        return
    fi
    
    mv /tmp/backhaul "$BACKHAUL_BIN" 2>/dev/null
    rm -f "$BACKHAUL_ARCHIVE"
    chmod +x "$BACKHAUL_BIN"
    
    clear_screen
    print_logo
    print_color "GREEN" "✓ Backhaul installed successfully"
    press_enter
}

setup_reverse_tunnel() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "PURPLE" "  ⚡ Setup Reverse Tunnel (Automated)"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    print_color "CYAN" "This will setup a complete reverse tunnel system:"
    print_color "YELLOW" "• Main Tunnel: Kharej (Client) → Iran (Server)"
    print_color "YELLOW" "• Bridge Tunnel: Iran → Kharej (through main tunnel)"
    echo ""
    
    print_color "PINK" "Select Server Location:"
    echo ""
    print_color "CYAN" "[1] Iran Server (Setup main tunnel + bridge)"
    print_color "YELLOW" "[2] Kharej Server (Setup client tunnel)"
    print_color "OLIVE" "[0] Back"
    echo ""
    print_color "ORANGE" "Select option:"
    read -r location
    
    case $location in
        1) setup_iran_reverse ;;
        2) setup_kharej_reverse ;;
        0) return ;;
        *) 
            print_color "RED" "✗ Invalid option"
            sleep 1
            ;;
    esac
}

setup_iran_reverse() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  Iran Server - Reverse Tunnel Setup"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    # Get tunnel name
    print_color "PINK" "Tunnel name:"
    read -r tunnel_name
    
    if [[ -z "$tunnel_name" ]]; then
        print_color "RED" "✗ Tunnel name is required"
        sleep 2
        return
    fi
    
    # Protocol selection
    echo ""
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP (Recommended)"
    print_color "CYAN" "[2] UDP"
    echo ""
    print_color "PINK" "Select protocol (1-2):"
    read -r proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        *)
            print_color "RED" "✗ Invalid protocol selection"
            sleep 2
            return
            ;;
    esac
    
    # Main tunnel port
    while true; do
        echo ""
        print_color "YELLOW" "Main Tunnel Port (for Kharej to connect):"
        read -r main_port
        
        if ! validate_port "$main_port"; then
            print_color "RED" "✗ Invalid port"
            sleep 1
            continue
        fi
        
        if check_port_in_use "$main_port"; then
            print_color "RED" "✗ Port $main_port is already in use"
            sleep 1
            continue
        fi
        break
    done
    
    # Bridge port
    while true; do
        echo ""
        print_color "BLUE" "Bridge Port (internal communication, e.g., 8080):"
        read -r bridge_port
        
        if ! validate_port "$bridge_port"; then
            print_color "RED" "✗ Invalid port"
            sleep 1
            continue
        fi
        
        if check_port_in_use "$bridge_port"; then
            print_color "RED" "✗ Port $bridge_port is already in use"
            sleep 1
            continue
        fi
        break
    done
    
    # Token generation
    echo ""
    print_color "ORANGE" "Token (leave empty for auto-generate):"
    read -r token
    
    if [[ -z "$token" ]]; then
        token=$(generate_token)
        echo ""
        print_color "GREEN" "✓ Generated token: $token"
        sleep 2
    fi
    
    # Get Kharej IP (optional, for display)
    echo ""
    print_color "PURPLE" "Kharej Server IP (for reference):"
    read -r kharej_ip
    
    local web_port_main=$(get_next_web_port)
    local web_port_bridge=$((web_port_main + 1))
    
    # Create MAIN tunnel config (Server - receives connection from Kharej)
    local main_config_name="reverse-${tunnel_name}-main-${protocol}"
    local main_config_file="/root/${main_config_name}.toml"
    
    cat > "$main_config_file" << EOF
[server]
bind_addr = "0.0.0.0:$main_port"
transport = "$protocol"
token = "$token"
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $web_port_main
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
ports = ["$bridge_port"]
EOF
    
    chmod 755 "$main_config_file"
    
    # Create MAIN tunnel service
    cat > "/etc/systemd/system/${main_config_name}.service" << EOF
[Unit]
Description=ReverseTunnel Main Server - ${tunnel_name}
After=network.target

[Service]
Type=simple
ExecStart=$BACKHAUL_BIN -c $main_config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # Create BRIDGE tunnel config (Client - connects through localhost to Kharej)
    local bridge_config_name="reverse-${tunnel_name}-bridge-${protocol}"
    local bridge_config_file="/root/${bridge_config_name}.toml"
    
    cat > "$bridge_config_file" << EOF
[client]
remote_addr = "127.0.0.1:$bridge_port"
transport = "$protocol"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port_bridge
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
EOF
    
    chmod 755 "$bridge_config_file"
    
    # Create BRIDGE tunnel service
    cat > "/etc/systemd/system/${bridge_config_name}.service" << EOF
[Unit]
Description=ReverseTunnel Bridge Client - ${tunnel_name}
After=network.target ${main_config_name}.service
Requires=${main_config_name}.service

[Service]
Type=simple
ExecStart=$BACKHAUL_BIN -c $bridge_config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # Start services
    systemctl daemon-reload
    systemctl enable "${main_config_name}.service" >/dev/null 2>&1
    systemctl enable "${bridge_config_name}.service" >/dev/null 2>&1
    systemctl start "${main_config_name}.service"
    sleep 2
    systemctl start "${bridge_config_name}.service"
    
    # Save tunnel info
    save_tunnel_info "$tunnel_name" "$main_config_name" "$main_port" "0.0.0.0" "$protocol" "main-server"
    save_tunnel_info "$tunnel_name" "$bridge_config_name" "$bridge_port" "127.0.0.1" "$protocol" "bridge-client"
    
    # Display results
    clear_screen
    print_logo
    
    if systemctl is-active --quiet "${main_config_name}.service" && systemctl is-active --quiet "${bridge_config_name}.service"; then
        print_color "GREEN" "✓ Reverse Tunnel created successfully!"
        echo ""
        print_color "CYAN" "════════════════════════════════════════════"
        print_color "YELLOW" "  Configuration Summary (Iran Server)"
        print_color "CYAN" "════════════════════════════════════════════"
        echo ""
        print_color "PINK" "Tunnel Name: ${tunnel_name}"
        print_color "BLUE" "Protocol: ${protocol}"
        print_color "YELLOW" "Main Port: ${main_port}"
        print_color "ORANGE" "Bridge Port: ${bridge_port}"
        print_color "PURPLE" "Token: ${token}"
        print_color "OLIVE" "Web Ports: ${web_port_main}, ${web_port_bridge}"
        echo ""
        print_color "CYAN" "════════════════════════════════════════════"
        print_color "GREEN" "  Share with Kharej Server:"
        print_color "CYAN" "════════════════════════════════════════════"
        echo ""
        print_color "YELLOW" "Iran IP: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
        print_color "YELLOW" "Tunnel Port: ${main_port}"
        print_color "YELLOW" "Protocol: ${protocol}"
        print_color "YELLOW" "Token: ${token}"
        echo ""
        print_color "PURPLE" "⚡ Now you can use 127.0.0.1:${bridge_port} for your services!"
        print_color "PURPLE" "   (This port connects to Kharej server through reverse tunnel)"
    else
        print_color "RED" "✗ Failed to start reverse tunnel"
    fi
    
    press_enter
}

setup_kharej_reverse() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  Kharej Server - Reverse Tunnel Setup"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    # Get tunnel name
    print_color "PINK" "Tunnel name:"
    read -r tunnel_name
    
    if [[ -z "$tunnel_name" ]]; then
        print_color "RED" "✗ Tunnel name is required"
        sleep 2
        return
    fi
    
    # Protocol selection
    echo ""
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP (Must match Iran server)"
    print_color "CYAN" "[2] UDP"
    echo ""
    print_color "PINK" "Select protocol (1-2):"
    read -r proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        *)
            print_color "RED" "✗ Invalid protocol selection"
            sleep 2
            return
            ;;
    esac
    
    # Iran IP
    echo ""
    print_color "YELLOW" "Iran Server IP:"
    read -r iran_ip
    
    if ! validate_ip "$iran_ip"; then
        print_color "RED" "✗ Invalid IP address"
        sleep 2
        return
    fi
    
    # Iran port
    echo ""
    print_color "ORANGE" "Iran Tunnel Port:"
    read -r iran_port
    
    if ! validate_port "$iran_port"; then
        print_color "RED" "✗ Invalid port"
        sleep 2
        return
    fi
    
    # Token
    echo ""
    print_color "BLUE" "Token (from Iran server):"
    read -r token
    
    if [[ -z "$token" ]]; then
        print_color "RED" "✗ Token is required"
        sleep 2
        return
    fi
    
    local remote_addr="${iran_ip}:${iran_port}"
    local web_port=$(get_next_web_port)
    local config_name="reverse-${tunnel_name}-kharej-${protocol}"
    local config_file="/root/${config_name}.toml"
    
    # Create config
    cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "$protocol"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
EOF
    
    chmod 755 "$config_file"
    
    # Create service
    cat > "/etc/systemd/system/${config_name}.service" << EOF
[Unit]
Description=ReverseTunnel Kharej Client - ${tunnel_name}
After=network.target

[Service]
Type=simple
ExecStart=$BACKHAUL_BIN -c $config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "${config_name}.service" >/dev/null 2>&1
    systemctl start "${config_name}.service"
    
    save_tunnel_info "$tunnel_name" "$config_name" "$iran_port" "$iran_ip" "$protocol" "kharej-client"
    
    # Display results
    clear_screen
    print_logo
    
    sleep 3
    
    if systemctl is-active --quiet "${config_name}.service"; then
        # Check logs for connection
        local logs=$(journalctl -u "${config_name}.service" -n 20 --no-pager 2>/dev/null)
        
        if echo "$logs" | grep -q "control channel established"; then
            print_color "GREEN" "✓ Reverse Tunnel connected successfully!"
            echo ""
            print_color "CYAN" "════════════════════════════════════════════"
            print_color "YELLOW" "  Kharej Server Configuration"
            print_color "CYAN" "════════════════════════════════════════════"
            echo ""
            print_color "PINK" "Tunnel Name: ${tunnel_name}"
            print_color "BLUE" "Protocol: ${protocol}"
            print_color "YELLOW" "Connected to: ${iran_ip}:${iran_port}"
            print_color "OLIVE" "Web Port: ${web_port}"
            echo ""
            print_color "GREEN" "✓ Connection Status: ESTABLISHED"
            print_color "PURPLE" "⚡ Your services can now receive traffic from Iran!"
        else
            print_color "YELLOW" "⚠ Tunnel started but waiting for connection..."
            echo ""
            print_color "CYAN" "Configuration:"
            print_color "PINK" "  Name: ${tunnel_name}"
            print_color "BLUE" "  Iran: ${iran_ip}:${iran_port}"
            print_color "YELLOW" "  Protocol: ${protocol}"
        fi
    else
        print_color "RED" "✗ Failed to start tunnel"
    fi
    
    press_enter
}

manage_tunnel_menu() {
    while true; do
        clear_screen
        print_logo
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        print_color "CYAN" "  Manage Reverse Tunnels"
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        echo ""
        
        local tunnels=($(list_tunnels))
        if [[ ${#tunnels[@]} -eq 0 ]]; then
            print_color "RED" "✗ No tunnels found"
            press_enter
            return
        fi
        
        local i=1
        for tunnel in "${tunnels[@]}"; do
            local info=$(get_tunnel_info "$tunnel")
            local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            local port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            local dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
            local ttype=$(echo "$info" | jq -r '.type // "N/A"' 2>/dev/null)
            
            if [[ -z "$name" || "$name" == "null" ]]; then
                name="Unknown"
            fi
            
            if systemctl is-active --quiet "$tunnel"; then
                print_color "GREEN" "[$i] $name | Type: $ttype | Port: $port | Dest: $dest (Active)"
            else
                print_color "RED" "[$i] $name | Type: $ttype | Port: $port | Dest: $dest (Inactive)"
            fi
            ((i++))
        done
        
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "YELLOW" "Select tunnel:"
        read -r choice
        
        if [[ "$choice" == "0" ]]; then
            return
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#tunnels[@]} ]]; then
            local selected_tunnel="${tunnels[$((choice-1))]}"
            manage_tunnel_actions "$selected_tunnel"
        else
            clear_screen
            print_logo
            print_color "RED" "✗ Invalid selection"
            sleep 1
        fi
    done
}

manage_tunnel_actions() {
    local tunnel="$1"
    
    while true; do
        clear_screen
        print_logo
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        print_color "CYAN" "  Manage: $tunnel"
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Start"
        print_color "CYAN" "[2] Stop"
        print_color "YELLOW" "[3] Restart"
        print_color "ORANGE" "[4] View Status"
        print_color "BLUE" "[5] Delete"
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "PINK" "Select action:"
        read -r action
        
        case $action in
            1)
                systemctl start "$tunnel"
                clear_screen
                print_logo
                if systemctl is-active --quiet "$tunnel"; then
                    print_color "GREEN" "✓ Tunnel started"
                else
                    print_color "RED" "✗ Failed to start"
                fi
                sleep 2
                ;;
            2)
                systemctl stop "$tunnel"
                clear_screen
                print_logo
                print_color "GREEN" "✓ Tunnel stopped"
                sleep 2
                ;;
            3)
                systemctl restart "$tunnel"
                clear_screen
                print_logo
                if systemctl is-active --quiet "$tunnel"; then
                    print_color "GREEN" "✓ Tunnel restarted"
                else
                    print_color "RED" "✗ Failed to restart"
                fi
                sleep 2
                ;;
            4)
                view_tunnel_status "$tunnel"
                ;;
            5)
                delete_tunnel "$tunnel"
                return
                ;;
            0)
                return
                ;;
            *)
                clear_screen
                print_logo
                print_color "RED" "✗ Invalid action"
                sleep 1
                ;;
        esac
    done
}

view_tunnel_status() {
    local tunnel="$1"
    
    clear_screen
    print_logo
    print_color "CYAN" "═══════════════════════════════════════════════════════"
    print_color "YELLOW" "  Status: $tunnel"
    print_color "CYAN" "═══════════════════════════════════════════════════════"
    echo ""
    
    local info=$(get_tunnel_info "$tunnel")
    local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
    local port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
    local dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
    local proto=$(echo "$info" | jq -r '.protocol // "N/A"' 2>/dev/null)
    local ttype=$(echo "$info" | jq -r '.type // "N/A"' 2>/dev/null)
    
    print_color "PINK" "Name: $name"
    print_color "CYAN" "Type: $ttype"
    print_color "YELLOW" "Protocol: $proto"
    print_color "ORANGE" "Port: $port"
    print_color "BLUE" "Destination: $dest"
    echo ""
    
    if systemctl is-active --quiet "$tunnel"; then
        print_color "GREEN" "Status: ACTIVE ✓"
        echo ""
        
        local logs=$(journalctl -u "$tunnel" -n 10 --no-pager 2>/dev/null | tail -5)
        if echo "$logs" | grep -q "control channel established"; then
            print_color "GREEN" "Connection: ESTABLISHED ✓"
        else
            print_color "YELLOW" "Connection: Connecting..."
        fi
    else
        print_color "RED" "Status: INACTIVE ✗"
    fi
    
    press_enter
}

delete_tunnel() {
    local tunnel="$1"
    
    clear_screen
    print_logo
    print_color "RED" "⚠ Are you sure you want to delete $tunnel? (yes/no)"
    read -r confirm
    
    if [[ "$confirm" == "yes" ]]; then
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
        delete_tunnel_info "$tunnel"
        systemctl daemon-reload
        
        clear_screen
        print_logo
        print_color "GREEN" "✓ Tunnel deleted successfully"
    else
        clear_screen
        print_logo
        print_color "YELLOW" "Deletion cancelled"
    fi
    
    press_enter
}

show_all_status() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  All Reverse Tunnels Status"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    local tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_color "RED" "✗ No tunnels found"
    else
        for tunnel in "${tunnels[@]}"; do
            local info=$(get_tunnel_info "$tunnel")
            local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            local port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            local dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
            local ttype=$(echo "$info" | jq -r '.type // "N/A"' 2>/dev/null)
            
            if [[ -z "$name" || "$name" == "null" ]]; then
                name="Unknown"
            fi
            
            if systemctl is-active --quiet "$tunnel"; then
                local logs=$(journalctl -u "$tunnel" -n 5 --no-pager 2>/dev/null)
                if echo "$logs" | grep -q "control channel established"; then
                    print_color "GREEN" "✓ $name ($ttype) | Port: $port | Dest: $dest | CONNECTED"
                else
                    print_color "YELLOW" "⚡ $name ($ttype) | Port: $port | Dest: $dest | CONNECTING"
                fi
            else
                print_color "RED" "✗ $name ($ttype) | Port: $port | Dest: $dest | STOPPED"
            fi
        done
    fi
    
    press_enter
}

show_logs() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  Tunnel Logs"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    local tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_color "RED" "✗ No tunnels found"
        press_enter
        return
    fi
    
    local i=1
    for tunnel in "${tunnels[@]}"; do
        local info=$(get_tunnel_info "$tunnel")
        local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
        
        if [[ -z "$name" || "$name" == "null" ]]; then
            name="Unknown"
        fi
        
        print_color "PINK" "[$i] $name ($tunnel)"
        ((i++))
    done
    
    print_color "OLIVE" "[0] Back"
    echo ""
    print_color "YELLOW" "Select tunnel:"
    read -r choice
    
    if [[ "$choice" == "0" ]]; then
        return
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#tunnels[@]} ]]; then
        local selected_tunnel="${tunnels[$((choice-1))]}"
        
        clear_screen
        print_color "CYAN" "═══════════════════════════════════════════════════════"
        print_color "YELLOW" "  Logs: $selected_tunnel (Last 50 lines)"
        print_color "CYAN" "═══════════════════════════════════════════════════════"
        echo ""
        
        local log_output=$(journalctl -u "$selected_tunnel" -n 50 --no-pager 2>/dev/null)
        if [[ -z "$log_output" ]]; then
            print_color "RED" "✗ No logs available"
        else
            echo "$log_output"
        fi
        
        press_enter
    else
        clear_screen
        print_logo
        print_color "RED" "✗ Invalid selection"
        sleep 1
    fi
}

uninstall_all() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "CYAN" "  Uninstall ReverseTunnel"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    print_color "RED" "⚠ This will remove all tunnels and Backhaul installation"
    print_color "YELLOW" "Are you sure? (yes/no)"
    read -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        clear_screen
        print_logo
        print_color "BLUE" "Uninstall cancelled"
        press_enter
        return
    fi
    
    clear_screen
    print_logo
    print_color "PINK" "→ Stopping and removing all tunnels..."
    sleep 1
    
    local tunnels=($(list_tunnels))
    for tunnel in "${tunnels[@]}"; do
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
    done
    
    clear_screen
    print_logo
    print_color "CYAN" "→ Removing Backhaul binary..."
    sleep 1
    
    rm -f "$BACKHAUL_BIN"
    rm -f /tmp/backhaul
    rm -f /root/backhaul
    
    clear_screen
    print_logo
    print_color "YELLOW" "→ Removing configuration files..."
    sleep 1
    
    rm -f "$SNIFFER_LOG"
    rm -f "$TUNNEL_DB"
    find /root -type f -name "reverse-*.toml" -exec rm -f {} \;
    
    clear_screen
    print_logo
    print_color "ORANGE" "→ Reloading systemd..."
    sleep 1
    
    systemctl daemon-reload
    
    clear_screen
    print_logo
    print_color "GREEN" "✓ ReverseTunnel uninstalled successfully"
    press_enter
}

show_guide() {
    clear_screen
    print_logo
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    print_color "PURPLE" "  ⚡ Reverse Tunnel Guide"
    print_color "ORANGE" "═══════════════════════════════════════════════════════"
    echo ""
    
    print_color "CYAN" "What is Reverse Tunnel?"
    echo ""
    print_color "YELLOW" "A reverse tunnel allows traffic to flow from Kharej → Iran"
    print_color "YELLOW" "instead of the usual Iran → Kharej direction."
    echo ""
    
    print_color "CYAN" "How it works:"
    echo ""
    print_color "PINK" "1. Iran Server runs TWO tunnels:"
    print_color "YELLOW" "   • Main Server: Receives connection from Kharej"
    print_color "YELLOW" "   • Bridge Client: Connects to Kharej through main tunnel"
    echo ""
    print_color "PINK" "2. Kharej Server runs ONE tunnel:"
    print_color "YELLOW" "   • Client: Connects to Iran's main server"
    echo ""
    print_color "PINK" "3. Result:"
    print_color "YELLOW" "   • Iran can access Kharej through 127.0.0.1:bridge_port"
    print_color "YELLOW" "   • Perfect for bypassing Iran's filtering"
    echo ""
    
    print_color "CYAN" "Setup Steps:"
    echo ""
    print_color "GREEN" "Step 1: On Iran Server"
    print_color "YELLOW" "   → Install Backhaul"
    print_color "YELLOW" "   → Choose 'Setup Reverse Tunnel' → 'Iran Server'"
    print_color "YELLOW" "   → Note down: IP, Port, Token"
    echo ""
    print_color "GREEN" "Step 2: On Kharej Server"
    print_color "YELLOW" "   → Install Backhaul"
    print_color "YELLOW" "   → Choose 'Setup Reverse Tunnel' → 'Kharej Server'"
    print_color "YELLOW" "   → Enter Iran's IP, Port, Token"
    echo ""
    print_color "GREEN" "Step 3: Test"
    print_color "YELLOW" "   → On Iran: Your services can use 127.0.0.1:bridge_port"
    print_color "YELLOW" "   → This port connects to Kharej automatically!"
    echo ""
    
    print_color "CYAN" "Benefits:"
    echo ""
    print_color "GREEN" "✓ Bypasses Iran's outbound filtering"
    print_color "GREEN" "✓ More stable connection"
    print_color "GREEN" "✓ Better for censorship circumvention"
    print_color "GREEN" "✓ Works with any service (VPN, proxy, etc.)"
    
    press_enter
}

main_menu() {
    if ! command -v jq &> /dev/null; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y jq >/dev/null 2>&1
    fi
    
    init_tunnel_db
    
    while true; do
        clear_screen
        print_logo
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        print_color "CYAN" "  Main Menu"
        print_color "ORANGE" "═══════════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Install Backhaul"
        print_color "CYAN" "[2] Setup Reverse Tunnel (Auto)"
        print_color "YELLOW" "[3] Manage Tunnels"
        print_color "ORANGE" "[4] View All Status"
        print_color "BLUE" "[5] View Logs"
        print_color "PURPLE" "[6] Guide & Help"
        print_color "OLIVE" "[7] Uninstall All"
        print_color "RED" "[8] Exit"
        echo ""
        print_color "CYAN" "Select option:"
        read -r choice
        
        case $choice in
            1)
                install_backhaul
                ;;
            2)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    setup_reverse_tunnel
                fi
                ;;
            3)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    manage_tunnel_menu
                fi
                ;;
            4)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_all_status
                fi
                ;;
            5)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_logs
                fi
                ;;
            6)
                show_guide
                ;;
            7)
                uninstall_all
                ;;
            8)
                clear_screen
                print_color "PURPLE" "⚡ Thank you for using ReverseTunnel!"
                print_color "CYAN" "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                clear_screen
                print_logo
                print_color "RED" "✗ Invalid option"
                sleep 1
                ;;
        esac
    done
}

check_root
main_menu
