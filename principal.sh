#!/bin/bash

#===============================================================================
# SISTEMA DE RESPALDO AUTOMÁTICO CON AUTENTICACIÓN Y NOTIFICACIONES
# Proyecto Final - Programación en Administración de Redes
# Autor: Alexis
# Fecha: 19 de junio de 2025
#===============================================================================

# Configuración global
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/backup-system"
LOG_DIR="/var/log/backup-system"
TEMP_DIR="/tmp/backup-system"
USB_MOUNT_BASE="/media"

# Archivos de configuración
SERVER_CONFIG="$CONFIG_DIR/server.conf"
SYSADMIN_KEYS="$CONFIG_DIR/authorized_keys"
SERVER_HASH="$CONFIG_DIR/server_hash"
TELEGRAM_CONFIG="$CONFIG_DIR/telegram.conf"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#===============================================================================
# FUNCIONES DE UTILIDAD
#===============================================================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/backup.log"
}

error_exit() {
    log_message "ERROR" "$1"
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

success_message() {
    log_message "INFO" "$1"
    echo -e "${GREEN}✓ $1${NC}"
}

warning_message() {
    log_message "WARNING" "$1"
    echo -e "${YELLOW}⚠ $1${NC}"
}

info_message() {
    log_message "INFO" "$1"
    echo -e "${BLUE}ℹ $1${NC}"
}

#===============================================================================
# FUNCIONES DE CONFIGURACIÓN
#===============================================================================

check_dependencies() {
    local deps=("openssl" "tar" "gzip" "curl" "udevadm" "mount" "umount")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error_exit "Dependencias faltantes: ${missing[*]}"
    fi
    
    success_message "Todas las dependencias están instaladas"
}

create_directories() {
    local dirs=("$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || error_exit "No se pudo crear el directorio $dir"
            info_message "Directorio creado: $dir"
        fi
    done
}

#===============================================================================
# FUNCIONES DE AUTENTICACIÓN
#===============================================================================

verify_digital_signature() {
    local usb_path="$1"
    local private_key="$usb_path/sysadmin_key.pem"
    local signature_file="$usb_path/signature.sig"
    local challenge_file="$TEMP_DIR/challenge.txt"
    
    # Verificar que existan los archivos necesarios
    if [ ! -f "$private_key" ]; then
        warning_message "No se encontró llave privada en la unidad USB"
        return 1
    fi
    
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        warning_message "No se encontró archivo de llaves autorizadas"
        return 1
    fi
    
    # Generar desafío
    local challenge=$(openssl rand -hex 32)
    echo "$challenge" > "$challenge_file"
    
    info_message "Generando desafío de autenticación..."
    
    # Firmar el desafío con la llave privada
    if ! openssl dgst -sha256 -sign "$private_key" -out "$signature_file" "$challenge_file"; then
        warning_message "Error al firmar el desafío"
        return 1
    fi
    
    # Extraer la llave pública correspondiente
    local public_key_file="$TEMP_DIR/temp_public.pem"
    if ! openssl rsa -in "$private_key" -pubout -out "$public_key_file" 2>/dev/null; then
        warning_message "Error al extraer llave pública"
        return 1
    fi
    
    # Verificar si la llave pública está autorizada
    local public_key_fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if ! grep -q "$public_key_fingerprint" "$SYSADMIN_KEYS"; then
        warning_message "Llave pública no autorizada"
        rm -f "$public_key_file" "$challenge_file" "$signature_file"
        return 1
    fi
    
    # Verificar la firma
    if openssl dgst -sha256 -verify "$public_key_file" -signature "$signature_file" "$challenge_file"; then
        success_message "Autenticación por firma digital exitosa"
        rm -f "$public_key_file" "$challenge_file" "$signature_file"
        return 0
    else
        warning_message "Fallo en la verificación de firma digital"
        rm -f "$public_key_file" "$challenge_file" "$signature_file"
        return 1
    fi
}

get_sysadmin_id() {
    local usb_path="$1"
    local sysadmin_id_file="$usb_path/sysadmin_id.txt"
    
    if [ -f "$sysadmin_id_file" ]; then
        cat "$sysadmin_id_file" | tr -d '\n\r'
    else
        echo "unknown"
    fi
}

#===============================================================================
# FUNCIONES DE TELEGRAM
#===============================================================================

load_telegram_config() {
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        warning_message "Archivo de configuración de Telegram no encontrado"
        return 1
    fi
    
    source "$TELEGRAM_CONFIG"
    
    if [ -z "$BOT_TOKEN" ]; then
        warning_message "Token del bot no configurado"
        return 1
    fi
    
    return 0
}

send_telegram_notification() {
    local sysadmin_id="$1"
    local message="$2"
    local request_password="$3"
    
    if ! load_telegram_config; then
        warning_message "No se pueden enviar notificaciones por Telegram"
        return 1
    fi
    
    # Obtener chat_id del sysadmin
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | cut -d':' -f2)
    
    if [ -z "$chat_id" ]; then
        warning_message "Chat ID no encontrado para sysadmin: $sysadmin_id"
        return 1
    fi
    
    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local keyboard=""
    
    if [ "$request_password" = "true" ]; then
        keyboard=', "reply_markup": {"force_reply": true, "input_field_placeholder": "Ingrese la contraseña del servidor"}'
    fi
    
    local payload="{\"chat_id\": \"$chat_id\", \"text\": \"$message\"$keyboard}"
    
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"ok":true'; then
        success_message "Notificación enviada a $sysadmin_id"
        return 0
    else
        warning_message "Error al enviar notificación: $response"
        return 1
    fi
}

wait_for_password() {
    local sysadmin_id="$1"
    local timeout=300 # 5 minutos
    local start_time=$(date +%s)
    
    if ! load_telegram_config; then
        return 1
    fi
    
    local chat_id=$(grep "^$sysadmin_id:" "$TELEGRAM_CONFIG" | cut -d':' -f2)
    local url="https://api.telegram.org/bot$BOT_TOKEN/getUpdates"
    local last_update_id=0
    
    info_message "Esperando contraseña del sysadmin $sysadmin_id..."
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        local response=$(curl -s "$url?offset=$((last_update_id + 1))")
        
        if echo "$response" | grep -q '"ok":true'; then
            local updates=$(echo "$response" | grep -o '"result":\[.*\]' | sed 's/"result":\[//' | sed 's/\]$//')
            
            if [ ! -z "$updates" ] && [ "$updates" != "null" ]; then
                while IFS= read -r update; do
                    if [ ! -z "$update" ]; then
                        local update_chat_id=$(echo "$update" | grep -o '"chat":{"id":[^,]*' | grep -o '[0-9-]*$')
                        local message_text=$(echo "$update" | grep -o '"text":"[^"]*"' | sed 's/"text":"//' | sed 's/"$//')
                        local update_id=$(echo "$update" | grep -o '"update_id":[0-9]*' | grep -o '[0-9]*$')
                        
                        if [ "$update_chat_id" = "$chat_id" ] && [ ! -z "$message_text" ]; then
                            echo "$message_text"
                            return 0
                        fi
                        
                        if [ ! -z "$update_id" ] && [ "$update_id" -gt "$last_update_id" ]; then
                            last_update_id=$update_id
                        fi
                    fi
                done <<< "$(echo "$updates" | sed 's/},{/\n/g')"
            fi
        fi
        
        sleep 2
    done
    
    warning_message "Timeout esperando contraseña"
    return 1
}

verify_server_password() {
    local provided_password="$1"
    
    if [ ! -f "$SERVER_HASH" ]; then
        error_exit "Archivo de hash del servidor no encontrado"
    fi
    
    local stored_hash=$(cat "$SERVER_HASH")
    local provided_hash=$(echo -n "$provided_password" | sha256sum | cut -d' ' -f1)
    
    if [ "$stored_hash" = "$provided_hash" ]; then
        success_message "Contraseña del servidor verificada"
        return 0
    else
        warning_message "Contraseña del servidor incorrecta"
        return 1
    fi
}

#===============================================================================
# FUNCIONES DE RESPALDO
#===============================================================================

read_backup_config() {
    local usb_path="$1"
    local config_file="$usb_path/backup_config.conf"
    
    if [ ! -f "$config_file" ]; then
        error_exit "Archivo de configuración de respaldo no encontrado en USB"
    fi
    
    source "$config_file"
    
    if [ -z "$BACKUP_DIRS" ]; then
        error_exit "No se especificaron directorios para respaldar"
    fi
    
    info_message "Configuración de respaldo cargada desde USB"
}

create_backup() {
    local backup_dirs="$1"
    local usb_path="$2"
    local server_password="$3"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    info_message "Iniciando proceso de respaldo..."
    
    for dir in $backup_dirs; do
        if [ ! -d "$dir" ]; then
            warning_message "Directorio no encontrado: $dir"
            continue
        fi
        
        local dir_name=$(basename "$dir")
        local backup_filename="${dir_name}_${timestamp}.tar.gz"
        local backup_path="$usb_path/$backup_filename"
        
        info_message "Respaldando directorio: $dir"
        
        # Crear respaldo comprimido y cifrado
        if tar -czf - -C "$(dirname "$dir")" "$(basename "$dir")" | \
           openssl enc -aes-256-cbc -salt -k "$server_password" -out "$backup_path"; then
            
            local size=$(du -h "$backup_path" | cut -f1)
            success_message "Respaldo completado: $backup_filename ($size)"
        else
            warning_message "Error al crear respaldo de: $dir"
        fi
    done
    
    success_message "Proceso de respaldo finalizado"
}

#===============================================================================
# FUNCIÓN PRINCIPAL DE RESPALDO
#===============================================================================

process_usb_backup() {
    local usb_device="$1"
    local usb_path=""
    
    info_message "Procesando dispositivo USB: $usb_device"
    
    # Encontrar punto de montaje
    for mount_point in "$USB_MOUNT_BASE"/*; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            local mounted_device=$(df "$mount_point" | tail -1 | awk '{print $1}')
            if [[ "$mounted_device" == *"$usb_device"* ]]; then
                usb_path="$mount_point"
                break
            fi
        fi
    done
    
    if [ -z "$usb_path" ]; then
        warning_message "No se pudo encontrar el punto de montaje para $usb_device"
        return 1
    fi
    
    info_message "USB montado en: $usb_path"
    
    # Verificar autenticación por firma digital
    if ! verify_digital_signature "$usb_path"; then
        warning_message "Fallo en autenticación por firma digital"
        return 1
    fi
    
    # Obtener ID del sysadmin
    local sysadmin_id=$(get_sysadmin_id "$usb_path")
    info_message "Sysadmin identificado: $sysadmin_id"
    
    # Enviar notificación de inicio y solicitar contraseña
    send_telegram_notification "$sysadmin_id" \
        "🔄 Iniciando proceso de respaldo en servidor $(hostname). Por favor, proporcione la contraseña del servidor." \
        "true"
    
    # Esperar contraseña del servidor
    local server_password=$(wait_for_password "$sysadmin_id")
    
    if [ -z "$server_password" ]; then
        send_telegram_notification "$sysadmin_id" \
            "❌ Respaldo cancelado: No se recibió la contraseña del servidor en el tiempo límite."
        return 1
    fi
    
    # Verificar contraseña del servidor
    if ! verify_server_password "$server_password"; then
        send_telegram_notification "$sysadmin_id" \
            "❌ Respaldo cancelado: Contraseña del servidor incorrecta."
        return 1
    fi
    
    # Leer configuración de respaldo
    read_backup_config "$usb_path"
    
    # Enviar notificación de inicio de respaldo
    send_telegram_notification "$sysadmin_id" \
        "✅ Autenticación exitosa. Iniciando respaldo de directorios: $BACKUP_DIRS"
    
    # Crear respaldos
    create_backup "$BACKUP_DIRS" "$usb_path" "$server_password"
    
    # Enviar notificación de finalización
    send_telegram_notification "$sysadmin_id" \
        "✅ Respaldo completado exitosamente en servidor $(hostname). Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    
    success_message "Proceso de respaldo completado para $sysadmin_id"
}

#===============================================================================
# MONITOR DE DISPOSITIVOS USB
#===============================================================================

monitor_usb() {
    info_message "Iniciando monitor de dispositivos USB..."
    
    udevadm monitor --kernel --subsystem-match=block | while read -r line; do
        if echo "$line" | grep -q "KERNEL\[.*\] add.*sd[a-z][0-9]"; then
            local device=$(echo "$line" | grep -o "sd[a-z][0-9]")
            info_message "Nuevo dispositivo USB detectado: $device"
            
            # Esperar un momento para que el dispositivo se monte
            sleep 3
            
            # Procesar el respaldo
            process_usb_backup "$device"
        fi
    done
}

#===============================================================================
# FUNCIONES DE INSTALACIÓN Y CONFIGURACIÓN
#===============================================================================

install_service() {
    local service_file="/etc/systemd/system/backup-system.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=Sistema de Respaldo Automático
After=multi-user.target

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/principal.sh --monitor
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable backup-system.service
    success_message "Servicio instalado y habilitado"
}

setup_initial_config() {
    info_message "Configurando sistema inicial..."
    
    create_directories
    
    # Crear archivo de configuración del servidor si no existe
    if [ ! -f "$SERVER_CONFIG" ]; then
        cat > "$SERVER_CONFIG" << EOF
# Configuración del servidor de respaldo
SERVER_NAME=$(hostname)
SERVER_ID=$(hostname | sha256sum | cut -d' ' -f1 | head -c 8)
BACKUP_MAX_SIZE=10G
LOG_RETENTION_DAYS=30
EOF
        info_message "Archivo de configuración del servidor creado"
    fi
    
    # Crear archivo de llaves autorizadas si no existe
    if [ ! -f "$SYSADMIN_KEYS" ]; then
        touch "$SYSADMIN_KEYS"
        chmod 600 "$SYSADMIN_KEYS"
        info_message "Archivo de llaves autorizadas creado"
    fi
    
    # Crear archivo de configuración de Telegram si no existe
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        cat > "$TELEGRAM_CONFIG" << EOF
# Configuración de Telegram
BOT_TOKEN=""
# Formato: sysadmin_id:chat_id
# admin1:123456789
# admin2:987654321
EOF
        chmod 600 "$TELEGRAM_CONFIG"
        info_message "Archivo de configuración de Telegram creado"
    fi
    
    success_message "Configuración inicial completada"
}

#===============================================================================
# FUNCIONES DE UTILIDADES ADMINISTRATIVAS
#===============================================================================

add_sysadmin_key() {
    local public_key_file="$1"
    
    if [ ! -f "$public_key_file" ]; then
        error_exit "Archivo de llave pública no encontrado: $public_key_file"
    fi
    
    local fingerprint=$(openssl rsa -pubin -in "$public_key_file" -outform DER | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if grep -q "$fingerprint" "$SYSADMIN_KEYS"; then
        warning_message "La llave ya está autorizada"
        return 1
    fi
    
    echo "$fingerprint" >> "$SYSADMIN_KEYS"
    success_message "Llave pública autorizada: $fingerprint"
}

set_server_password() {
    local password="$1"
    
    if [ -z "$password" ]; then
        error_exit "Debe proporcionar una contraseña"
    fi
    
    local hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)
    echo "$hash" > "$SERVER_HASH"
    chmod 600 "$SERVER_HASH"
    success_message "Contraseña del servidor establecida"
}

show_status() {
    echo -e "\n${BLUE}=== Estado del Sistema de Respaldo ===${NC}"
    echo -e "Servidor: $(hostname)"
    echo -e "Configuración: ${GREEN}$([ -f "$SERVER_CONFIG" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Llaves autorizadas: ${GREEN}$([ -f "$SYSADMIN_KEYS" ] && wc -l < "$SYSADMIN_KEYS" || echo "0")${NC}"
    echo -e "Contraseña configurada: ${GREEN}$([ -f "$SERVER_HASH" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Telegram configurado: ${GREEN}$([ -f "$TELEGRAM_CONFIG" ] && echo "✓" || echo "✗")${NC}"
    echo -e "Servicio activo: ${GREEN}$(systemctl is-active backup-system.service 2>/dev/null || echo "inactivo")${NC}"
    echo
}

show_help() {
    cat << EOF
Sistema de Respaldo Automático - Administración de Redes

Uso: $0 [OPCIÓN]

OPCIONES:
    --monitor              Iniciar monitor de dispositivos USB
    --process-usb <dev>    Procesar dispositivo USB específico
    --install              Instalar y configurar el servicio
    --setup                Configuración inicial del sistema
    --add-key <archivo>    Autorizar llave pública de sysadmin
    --set-password <pass>  Establecer contraseña del servidor
    --status               Mostrar estado del sistema
    --help                 Mostrar esta ayuda

EJEMPLOS:
    $0 --setup                          # Configuración inicial
    $0 --add-key /path/to/public.pem    # Autorizar sysadmin
    $0 --set-password "mi_password"     # Configurar contraseña
    $0 --install                        # Instalar servicio
    $0 --monitor                        # Iniciar monitor
    $0 --process-usb sdb1               # Procesar USB específico

ARCHIVOS DE CONFIGURACIÓN:
    $SERVER_CONFIG      # Configuración del servidor
    $SYSADMIN_KEYS      # Llaves públicas autorizadas
    $SERVER_HASH        # Hash de contraseña del servidor
    $TELEGRAM_CONFIG    # Configuración de Telegram

EOF
}

#===============================================================================
# FUNCIÓN PRINCIPAL
#===============================================================================

main() {
    # Verificar que se ejecute como root
    if [ "$EUID" -ne 0 ]; then
        error_exit "Este script debe ejecutarse como root"
    fi
    
    case "${1:-}" in
        --monitor)
            check_dependencies
            create_directories
            monitor_usb
            ;;
        --process-usb)
            if [ -z "$2" ]; then
                error_exit "Debe especificar el dispositivo USB"
            fi
            check_dependencies
            create_directories
            process_usb_direct "$2"
            ;;
        --install)
            check_dependencies
            setup_initial_config
            install_service
            ;;
        --setup)
            check_dependencies
            setup_initial_config
            ;;
        --add-key)
            if [ -z "$2" ]; then
                error_exit "Debe especificar el archivo de llave pública"
            fi
            add_sysadmin_key "$2"
            ;;
        --set-password)
            if [ -z "$2" ]; then
                error_exit "Debe especificar la contraseña"
            fi
            set_server_password "$2"
            ;;
        --status)
            show_status
            ;;
        --help|"")
            show_help
            ;;
        *)
            error_exit "Opción no válida: $1. Use --help para ver las opciones disponibles."
            ;;
    esac
}

# Ejecutar función principal con todos los argumentos
main "$@"

#===============================================================================
# FUNCIÓN MEJORADA DE PROCESAMIENTO USB
#===============================================================================

process_usb_direct() {
    local usb_device="$1"
    local lock_file="/tmp/backup-system/usb-processing.lock"
    
    # Verificar que se proporcione un dispositivo
    if [ -z "$usb_device" ]; then
        error_exit "Debe especificar el dispositivo USB"
    fi
    
    info_message "Procesamiento directo de USB: $usb_device"
    
    # Crear lock file para evitar procesos concurrentes
    if [ -f "$lock_file" ]; then
        warning_message "Ya hay un proceso de respaldo en curso"
        return 1
    fi
    
    echo "$$" > "$lock_file"
    
    # Asegurar limpieza del lock file al salir
    trap 'rm -f "$lock_file"' EXIT
    
    # Buscar punto de montaje
    local usb_path=""
    local attempts=0
    local max_attempts=15
    
    while [ $attempts -lt $max_attempts ]; do
        usb_path=$(mount | grep "/dev/$usb_device" | awk '{print $3}' | head -1)
        if [ ! -z "$usb_path" ]; then
            break
        fi
        sleep 2
        ((attempts++))
    done
    
    if [ -z "$usb_path" ]; then
        warning_message "No se pudo encontrar punto de montaje para $usb_device después de $max_attempts intentos"
        return 1
    fi
    
    info_message "USB montado en: $usb_path"
    
    # Verificar que sea una unidad de respaldo válida
    if [ ! -f "$usb_path/backup_config.conf" ]; then
        info_message "No es una unidad de respaldo válida (falta backup_config.conf)"
        return 0
    fi
    
    if [ ! -f "$usb_path/sysadmin_key.pem" ]; then
        info_message "No es una unidad de respaldo válida (falta sysadmin_key.pem)"
        return 0
    fi
    
    # Procesar el respaldo
    process_usb_backup "$usb_device"
    
    info_message "Procesamiento de USB completado"
}