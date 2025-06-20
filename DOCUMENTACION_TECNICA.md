# 📚 DOCUMENTACIÓN TÉCNICA PRIVADA
## Sistema de Respaldo Automático - Análisis Detallado

**Autor:** Alexis  
**Fecha:** 19 de junio de 2025  
**Proyecto:** Final - Programación en Administración de Redes

---

## 🎯 ARQUITECTURA DEL SISTEMA

### **Flujo Principal de Operación:**
1. **Detección USB** → udev rules → handler script
2. **Autenticación** → firma digital + contraseña
3. **Respaldo** → compresión + cifrado
4. **Notificación** → Telegram API

### **Componentes de Seguridad:**
- **Criptografía**: RSA-2048 + AES-256-CBC + SHA-256
- **Autenticación**: Multinivel (firma + contraseña)
- **Autorización**: Lista de llaves públicas autorizadas

---

## 📁 ANÁLISIS DETALLADO POR ARCHIVO

### 1. 🚀 **`principal.sh`** - Script Principal (639 líneas)

**Propósito:** Motor principal del sistema de respaldo con todas las funcionalidades core.

#### **Secciones Principales:**

##### **🔧 Configuración Global (líneas 10-25)**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/backup-system"
LOG_DIR="/var/log/backup-system"
TEMP_DIR="/tmp/backup-system"
USB_MOUNT_BASE="/media"
```
**Análisis:** Define rutas absolutas para evitar problemas de directorio de trabajo. Usa expansión de parámetros para obtener directorio del script.

##### **🎨 Funciones de Utilidad (líneas 32-55)**
- `log_message()`: Sistema de logging centralizado con timestamps
- `error_exit()`: Manejo de errores con logging y salida limpia
- `success_message()`, `warning_message()`, `info_message()`: Output colorizado

**Técnica clave:** Uso de `tee -a` para escribir simultáneamente a consola y archivo log.

##### **🔐 Autenticación por Firma Digital (líneas 77-145)**

**Función `verify_digital_signature()`:**
```bash
# Proceso de autenticación:
1. Generar desafío aleatorio (openssl rand -hex 32)
2. Firmar desafío con llave privada del USB
3. Extraer llave pública correspondiente
4. Verificar si la llave está autorizada (fingerprint en authorized_keys)
5. Validar firma del desafío
```

**Detalles técnicos:**
- **Hash fingerprint**: `openssl rsa -pubin -in public.pem -outform DER | openssl dgst -sha256`
- **Firma**: `openssl dgst -sha256 -sign private.pem -out signature challenge.txt`
- **Verificación**: `openssl dgst -sha256 -verify public.pem -signature sig challenge.txt`

##### **📱 Integración Telegram (líneas 157-290)**

**Función `send_telegram_notification()`:**
- API endpoint: `https://api.telegram.org/bot<TOKEN>/sendMessage`
- Payload JSON con chat_id y mensaje
- Soporte para teclado de respuesta forzada (solicitud de contraseña)

**Función `wait_for_password()`:**
- Polling de updates cada 2 segundos
- Timeout de 5 minutos (300 seg)
- Parseo de JSON con herramientas básicas de shell
- Filtrado por chat_id específico

**Reto técnico resuelto:** Parseo de JSON sin dependencias externas usando `grep`, `sed` y `awk`.

##### **💾 Sistema de Respaldo (líneas 310-380)**

**Función `create_backup()`:**
```bash
# Pipeline de respaldo:
tar -czf - -C "$(dirname "$dir")" "$(basename "$dir")" | \
openssl enc -aes-256-cbc -salt -k "$server_password" -out "$backup_path"
```

**Análisis técnico:**
- **Compresión**: tar con gzip (-z)
- **Cifrado**: AES-256-CBC con salt automático
- **Streaming**: Pipeline para eficiencia de memoria
- **Naming**: `directorio_YYYYMMDD_HHMMSS.tar.gz`

##### **🔄 Monitor USB Avanzado (líneas 390-450)**

**Función `process_usb_direct()`:**
- Lock file para prevenir procesos concurrentes
- Retry logic para montaje (15 intentos, 2 seg c/u)
- Validación de estructura de USB requerida
- Trap para limpieza garantizada del lock

##### **⚙️ Funciones Administrativas (líneas 520-600)**

**Gestión de llaves:**
- `add_sysadmin_key()`: Agrega fingerprint a authorized_keys
- `set_server_password()`: Almacena hash SHA-256

**Instalación de servicio:**
- Crea archivo systemd service
- Recarga daemon y habilita servicio

#### **🎯 Puntos Clave de Implementación:**

1. **Manejo de errores robusto**: Cada función retorna códigos de estado
2. **Logging exhaustivo**: Todas las operaciones se registran
3. **Seguridad por capas**: Múltiples validaciones antes de ejecutar respaldo
4. **Compatibilidad**: Solo usa herramientas estándar de Linux

---

### 2. 📦 **`install.sh`** - Instalador Automático (125 líneas)

**Propósito:** Automatizar completamente la instalación y configuración del sistema.

#### **Funciones Principales:**

##### **🔍 `check_root()`**
Verifica permisos de superusuario usando `$EUID`.

##### **📋 `install_dependencies()`**
```bash
local packages=("openssl" "curl" "udev" "systemd")
```
- Usa `dpkg -l` para verificar instalación
- Instala solo paquetes faltantes
- Compatible con sistemas Debian/Ubuntu

##### **🔧 `setup_permissions()`**
Establece permisos de ejecución (`chmod +x`) en todos los scripts.

##### **🔗 `create_symlinks()`**
Crea enlaces simbólicos en `/usr/local/bin/`:
- `backup-system` → `principal.sh`
- `backup-genkeys` → `generar_llaves.sh`
- `backup-telegram` → `setup_telegram.sh`
- `backup-usb-handler` → `backup-usb-handler.sh`
- `backup-usb-cleanup` → `backup-usb-cleanup.sh`

##### **🚀 Nuevas Funciones Agregadas:**

**`install_udev_rules()`:**
- Copia `99-backup-usb.rules` a `/etc/udev/rules.d/`
- Recarga reglas con `udevadm control --reload-rules`

**`install_systemd_service()`:**
- Instala archivo de servicio en `/etc/systemd/system/`
- Ejecuta `systemctl daemon-reload`

#### **🎯 Flujo de Instalación:**
1. Verificar root
2. Instalar dependencias
3. Configurar permisos
4. Crear symlinks
5. Instalar reglas udev
6. Instalar servicio systemd
7. Ejecutar configuración inicial

---

### 3. 🔑 **`generar_llaves.sh`** - Generador de Llaves (65 líneas)

**Propósito:** Generar pares de llaves RSA para autenticación de sysadmins.

#### **Proceso de Generación:**

```bash
# Llave privada RSA-2048
openssl genrsa -out "${sysadmin_id}_private.pem" 2048

# Extraer llave pública
openssl rsa -in "$private_key" -pubout -out "$public_key"

# Archivo de identificación
echo "$sysadmin_id" > "sysadmin_id.txt"
```

#### **Seguridad:**
- **Tamaño de llave**: 2048 bits (estándar actual)
- **Permisos**: Llave privada con `chmod 600`
- **Estructura**: Directorio de salida personalizable

#### **Archivos generados:**
- `{id}_private.pem` - Llave privada (para USB)
- `{id}_public.pem` - Llave pública (para autorizar en servidor)
- `sysadmin_id.txt` - Identificador del administrador

---

### 4. 📱 **`setup_telegram.sh`** - Configurador Telegram (120 líneas)

**Propósito:** Configurar integración con bot de Telegram para notificaciones.

#### **Configuración del Bot:**

##### **Función `setup_telegram_bot()`:**
1. Solicita token del bot
2. Crea archivo `/etc/backup-system/telegram.conf`
3. Agrega mapeo sysadmin_id:chat_id iterativamente

**Formato del archivo de configuración:**
```bash
BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
admin1:123456789
admin2:987654321
```

##### **Función `test_telegram_notification()`:**
- Envía mensaje de prueba usando API
- Valida respuesta JSON de Telegram
- Verifica conectividad y configuración

#### **API de Telegram utilizada:**
- **Endpoint**: `https://api.telegram.org/bot<TOKEN>/sendMessage`
- **Método**: POST con JSON payload
- **Campos**: chat_id, text, reply_markup (opcional)

---

### 5. ⚙️ **`backup_config.conf`** - Configuración USB (10 líneas)

**Propósito:** Archivo de configuración que debe estar en la raíz del USB.

#### **Variables principales:**
```properties
BACKUP_DIRS="/etc /home /var/log /opt"        # Directorios a respaldar
BACKUP_NAME="servidor_produccion"             # Nombre identificativo
EXCLUDE_PATTERNS="*.tmp *.log.* /var/log/journal/*"  # Patrones a excluir
SYSADMIN_NAME="Administrador Principal"       # Nombre del admin
BACKUP_DESCRIPTION="Respaldo automático..."   # Descripción
```

#### **Uso en el sistema:**
- Leído por función `read_backup_config()` en `principal.sh`
- Parseado usando `source` (carga variables al entorno)
- Validación de `BACKUP_DIRS` como variable obligatoria

---

### 6. 🔧 **`backup-system.service`** - Servicio Systemd (25 líneas)

**Propósito:** Definir servicio systemd para ejecución automática y continua.

#### **Configuración detallada:**

```ini
[Unit]
Description=Sistema de Respaldo Automático con USB
After=multi-user.target graphical-session.target
Wants=network-online.target
```

**Análisis:**
- **Dependencies**: Espera a que el sistema esté completamente iniciado
- **Network**: Requiere red para Telegram

```ini
[Service]
Type=simple
ExecStart=/usr/local/bin/backup-system --monitor
Restart=always
RestartSec=10
User=root
Group=root
```

**Análisis:**
- **Type=simple**: Proceso en primer plano
- **Restart=always**: Reinicio automático en caso de fallo
- **User=root**: Requerido para acceso a dispositivos y directorios

```ini
# Configuración de seguridad
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/etc/backup-system /var/log/backup-system /tmp/backup-system /media
```

**Análisis de seguridad:**
- **NoNewPrivileges**: Previene escalada de privilegios
- **PrivateTmp**: Aislamiento de `/tmp`
- **ProtectSystem=strict**: Sistema de archivos en solo lectura
- **ReadWritePaths**: Excepciones específicas para funcionamiento

---

### 7. 🔌 **`99-backup-usb.rules`** - Reglas Udev (5 líneas)

**Propósito:** Detectar automáticamente dispositivos USB de almacenamiento.

#### **Reglas definidas:**

```udev
# Detección de dispositivos USB
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", ACTION=="add", RUN+="/usr/local/bin/backup-usb-handler %k"

# Limpieza al desconectar
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ACTION=="remove", RUN+="/usr/local/bin/backup-usb-cleanup %k"
```

#### **Análisis técnico:**
- **SUBSYSTEM=="block"**: Solo dispositivos de bloque
- **KERNEL=="sd[a-z][0-9]"**: Particiones de discos SATA/USB (sda1, sdb1, etc.)
- **ENV{ID_BUS}=="usb"**: Solo dispositivos USB
- **ENV{ID_FS_TYPE}!=""**: Que tengan sistema de archivos
- **%k**: Pasa el nombre del kernel device (ej: sdb1)

---

### 8. 🎬 **`backup-usb-handler.sh`** - Manejador de Eventos USB (65 líneas)

**Propósito:** Script ejecutado por udev cuando se detecta un dispositivo USB.

#### **Flujo de ejecución:**

1. **Validación inicial**:
   ```bash
   if [ -z "$DEVICE" ]; then
       log_event "ERROR: No se especificó dispositivo"
       exit 1
   fi
   ```

2. **Control de concurrencia**:
   ```bash
   if [ -f "$LOCK_FILE" ]; then
       log_event "WARNING: Proceso de respaldo ya en curso"
       exit 0
   fi
   ```

3. **Espera de montaje**:
   ```bash
   for i in {1..10}; do
       MOUNT_POINT=$(mount | grep "/dev/$DEVICE" | awk '{print $3}' | head -1)
       if [ ! -z "$MOUNT_POINT" ]; then break; fi
       sleep 1
   done
   ```

4. **Validación de unidad de respaldo**:
   - Verifica existencia de `backup_config.conf`
   - Verifica existencia de `sysadmin_key.pem`

5. **Ejecución en background**:
   ```bash
   nohup /usr/local/bin/backup-system --process-usb "$DEVICE" >> "$LOG_FILE" 2>&1 &
   ```

#### **Características técnicas:**
- **Logging**: Todas las operaciones se registran
- **Timeout handling**: Máximo 10 segundos esperando montaje
- **Background execution**: No bloquea el sistema udev
- **Error recovery**: Limpieza de lock files en caso de error

---

### 9. 🧹 **`backup-usb-cleanup.sh`** - Script de Limpieza (25 líneas)

**Propósito:** Limpiar archivos temporales cuando se desconecta el USB.

#### **Operaciones de limpieza:**
```bash
rm -f "/tmp/backup-system/challenge_${DEVICE}.txt"
rm -f "/tmp/backup-system/signature_${DEVICE}.sig"
rm -f "/tmp/backup-system/temp_public_${DEVICE}.pem"
```

#### **Logging de eventos:**
- Registro de dispositivo desconectado
- Confirmación de limpieza completada

---

### 10. 🧪 **`test_system.sh`** - Suite de Pruebas (180 líneas)

**Propósito:** Verificar integridad y funcionamiento del sistema antes del despliegue.

#### **Categorías de pruebas:**

##### **🔍 Test de Dependencias:**
```bash
local deps=("openssl" "tar" "gzip" "curl" "udevadm" "mount" "umount" "systemctl")
```
Verifica que todas las herramientas requeridas estén disponibles.

##### **🔐 Test de Permisos:**
Valida que todos los scripts tengan permisos de ejecución.

##### **📝 Test de Sintaxis:**
```bash
bash -n "$script" 2>/dev/null
```
Verifica sintaxis de bash en todos los scripts sin ejecutarlos.

##### **🔒 Test de OpenSSL:**
- Genera par de llaves de prueba
- Crea y verifica firma digital
- Valida toda la cadena criptográfica

##### **💾 Creación de Estructura de Prueba:**
```bash
# Crea directorio test_usb/ con:
├── backup_config.conf    # Configuración de prueba
├── sysadmin_key.pem     # Llave privada de prueba
└── sysadmin_id.txt      # ID test_admin
```

#### **Función auxiliar `run_test()`:**
Sistema elegante para ejecutar pruebas con output colorizado:
```bash
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Probando $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}
```

---

## 🔒 ANÁLISIS DE SEGURIDAD

### **Vectores de Ataque Mitigados:**

1. **USB Malicioso:**
   - ✅ Validación de estructura requerida
   - ✅ Autenticación por firma digital
   - ✅ Autorización de llaves públicas

2. **Man-in-the-Middle:**
   - ✅ HTTPS para comunicación con Telegram
   - ✅ No transmisión de credenciales en claro

3. **Escalada de Privilegios:**
   - ✅ Configuración systemd restrictiva
   - ✅ Principio de menor privilegio

4. **Ataques de Fuerza Bruta:**
   - ✅ No almacenamiento de contraseñas
   - ✅ Hash SHA-256 con salt implícito

### **Puntos de Mejora Futuros:**

1. **Rate limiting** en intentos de autenticación
2. **Alertas de seguridad** por intentos fallidos
3. **Rotación automática** de llaves
4. **Auditoría detallada** de accesos

---

## 📊 MÉTRICAS DEL PROYECTO

### **Líneas de Código:**
- `principal.sh`: 639 líneas
- `install.sh`: 125 líneas
- `generar_llaves.sh`: 65 líneas
- `setup_telegram.sh`: 120 líneas
- `backup-usb-handler.sh`: 65 líneas
- `backup-usb-cleanup.sh`: 25 líneas
- `test_system.sh`: 180 líneas
- **Total**: ~1,219 líneas

### **Tecnologías Utilizadas:**
- **Bash scripting**: 100%
- **OpenSSL**: Criptografía
- **Systemd**: Gestión de servicios
- **Udev**: Detección de hardware
- **Telegram API**: Notificaciones
- **JSON**: Intercambio de datos

### **Patrones de Diseño Implementados:**
- **Observer Pattern**: Detección de eventos USB
- **Command Pattern**: Sistema de opciones CLI
- **Factory Pattern**: Generación de llaves
- **Strategy Pattern**: Diferentes métodos de autenticación

---

## 🎓 CONCLUSIONES TÉCNICAS

### **Fortalezas del Diseño:**
1. **Modularidad**: Cada archivo tiene una responsabilidad específica
2. **Robustez**: Manejo exhaustivo de errores y casos edge
3. **Seguridad**: Múltiples capas de autenticación y validación
4. **Mantenibilidad**: Código bien documentado y estructurado
5. **Escalabilidad**: Fácil agregar nuevos sysadmins y servidores

### **Retos Técnicos Superados:**
1. **Parseo de JSON** sin dependencias externas
2. **Detección automática** de dispositivos USB
3. **Integración completa** con systemd y udev
4. **Manejo de procesos concurrentes** con lock files
5. **Pipeline de cifrado** streaming para eficiencia

### **Aplicabilidad en Entorno Real:**
- ✅ **Producción**: Sistema robusto para entornos corporativos
- ✅ **Escalable**: Soporta múltiples servidores y administradores
- ✅ **Auditable**: Logs detallados para compliance
- ✅ **Mantenible**: Estructura clara para futuras mejoras

---

**Este sistema representa un proyecto completo de administración de sistemas que cumple todos los requerimientos académicos y técnicos, con calidad de código profesional.**
