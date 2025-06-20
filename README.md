# Sistema de Respaldo Automático con Autenticación
## Proyecto Final - Programación en Administración de Redes

### 📋 Descripción
Sistema completo de respaldo automático para servidores mediante dispositivos USB, con autenticación mediante firmas digitales, notificaciones vía Telegram y cifrado de archivos de respaldo.

### 🚀 Características
- ✅ **Respaldo automático** al conectar dispositivo USB
- ✅ **Autenticación con firmas digitales** RSA-2048
- ✅ **Notificaciones en tiempo real** vía Telegram
- ✅ **Cifrado de respaldos** con AES-256-CBC
- ✅ **Compresión automática** con gzip
- ✅ **Detección automática** con reglas udev
- ✅ **Servicio systemd** para ejecución continua
- ✅ **Logs detallados** de auditoría

### 📁 Estructura del Proyecto
```
Proyecto_Admon_Servicios/
├── principal.sh              # Script principal del sistema
├── install.sh                # Instalador automático
├── generar_llaves.sh         # Generador de llaves RSA
├── setup_telegram.sh         # Configurador de Telegram
├── backup_config.conf        # Configuración para USB
├── backup-system.service     # Servicio systemd
├── 99-backup-usb.rules      # Reglas udev para USB
├── backup-usb-handler.sh    # Manejador de eventos USB
├── backup-usb-cleanup.sh    # Script de limpieza
├── test_system.sh           # Script de pruebas
└── README.md                # Documentación
```

### 🔧 Instalación

#### 1. Clonar o descargar el proyecto
```bash
git clone <repositorio>
cd Proyecto_Admon_Servicios
```

#### 2. Ejecutar instalación automática
```bash
sudo ./install.sh --install
```

#### 3. Configurar Telegram
```bash
sudo backup-telegram --setup
```

#### 4. Generar llaves para sysadmins
```bash
sudo backup-genkeys admin1 ./keys/
```

#### 5. Establecer contraseña del servidor
```bash
sudo backup-system --set-password "mi_password_segura"
```

#### 6. Habilitar y iniciar servicio
```bash
sudo systemctl enable backup-system.service
sudo systemctl start backup-system.service
```

### 📱 Configuración de Telegram

#### Crear Bot
1. Contactar a @BotFather en Telegram
2. Usar comando `/newbot`
3. Seguir instrucciones y obtener token

#### Obtener Chat ID
1. Enviar mensaje al bot
2. Visitar: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Buscar `"chat":{"id":XXXXXXXXX}`

### 🔐 Preparación de USB

#### Estructura requerida en USB:
```
USB/
├── backup_config.conf    # Configuración de respaldo
├── sysadmin_key.pem     # Llave privada del sysadmin
└── sysadmin_id.txt      # ID del sysadmin
```

#### Ejemplo de backup_config.conf:
```properties
BACKUP_DIRS="/etc /home /var/log"
BACKUP_NAME="servidor_produccion"
EXCLUDE_PATTERNS="*.tmp *.log.*"
SYSADMIN_NAME="Admin Principal"
BACKUP_DESCRIPTION="Respaldo de directorios críticos"
```

### 🎮 Uso del Sistema

#### Comandos principales:
```bash
# Ver estado del sistema
sudo backup-system --status

# Procesar USB manualmente
sudo backup-system --process-usb sdb1

# Agregar llave pública autorizada
sudo backup-system --add-key /path/to/public.pem

# Ver logs
tail -f /var/log/backup-system/backup.log
```

#### Proceso automático:
1. Conectar USB con archivos requeridos
2. Sistema detecta automáticamente el dispositivo
3. Verifica autenticación por firma digital
4. Solicita contraseña vía Telegram
5. Valida contraseña del servidor
6. Crea respaldos cifrados y comprimidos
7. Notifica finalización vía Telegram

### 🔍 Pruebas

#### Ejecutar suite de pruebas:
```bash
chmod +x test_system.sh
./test_system.sh
```

#### Verificar instalación:
```bash
sudo backup-system --status
systemctl status backup-system.service
```

### 📂 Ubicación de Archivos

#### Configuración:
- `/etc/backup-system/server.conf` - Configuración del servidor
- `/etc/backup-system/authorized_keys` - Llaves públicas autorizadas
- `/etc/backup-system/server_hash` - Hash de contraseña del servidor
- `/etc/backup-system/telegram.conf` - Configuración de Telegram

#### Logs:
- `/var/log/backup-system/backup.log` - Log principal
- `/var/log/backup-system/usb-events.log` - Eventos USB

#### Temporales:
- `/tmp/backup-system/` - Archivos temporales

### 🛡️ Seguridad

#### Autenticación multinivel:
1. **Firma digital**: Verificación con llaves RSA-2048
2. **Contraseña del servidor**: Hash SHA-256 almacenado
3. **Autorización de llaves**: Lista de llaves públicas autorizadas

#### Cifrado:
- **Respaldos**: AES-256-CBC con contraseña del servidor
- **Comunicación**: HTTPS para API de Telegram

### 🔧 Solución de Problemas

#### Ver logs detallados:
```bash
journalctl -u backup-system.service -f
tail -f /var/log/backup-system/backup.log
```

#### Verificar detección USB:
```bash
udevadm monitor --kernel --subsystem-match=block
```

#### Probar notificaciones Telegram:
```bash
sudo backup-telegram --test
```

### 📋 Requisitos del Sistema
- **OS**: Debian/Ubuntu Linux
- **Privilegios**: root
- **Dependencias**: openssl, curl, tar, gzip, udev, systemd
- **Red**: Acceso a internet para Telegram

### 👥 Autor
**Alexis** - Proyecto Final Programación en Administración de Redes

### 📄 Licencia
Proyecto académico - Universidad

---
*Fecha: 19 de junio de 2025*
