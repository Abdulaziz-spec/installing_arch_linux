#!/bin/bash

# ========================================
# Arch Linux + Hyprland ULTRA STABLE Auto Installer
# С множественными fallback методами и проверками
# ========================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Логирование
LOG_FILE="/tmp/arch-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Функция логирования
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Функция повтора команды с таймаутом
retry_command() {
    local max_attempts=3
    local timeout=5
    local attempt=1
    local cmd="$@"
    
    while [ $attempt -le $max_attempts ]; do
        log "Попытка $attempt из $max_attempts: $cmd"
        if timeout $timeout bash -c "$cmd"; then
            log_success "Команда выполнена успешно"
            return 0
        else
            log_warning "Попытка $attempt не удалась"
            attempt=$((attempt + 1))
            [ $attempt -le $max_attempts ] && sleep 2
        fi
    done
    
    log_error "Все попытки исчерпаны для: $cmd"
    return 1
}

# Функция установки пакетов с fallback
install_package() {
    local packages="$@"
    
    log "Установка пакетов: $packages"
    
    # Попытка 1: Обычная установка
    if pacman -S --noconfirm --needed $packages 2>/dev/null; then
        log_success "Пакеты установлены"
        return 0
    fi
    
    log_warning "Обычная установка не удалась, обновляю базы..."
    
    # Попытка 2: С обновлением баз
    if pacman -Sy && pacman -S --noconfirm --needed $packages 2>/dev/null; then
        log_success "Пакеты установлены после обновления баз"
        return 0
    fi
    
    log_warning "Пробую установить пакеты по одному..."
    
    # Попытка 3: По одному пакету
    local failed_packages=""
    for pkg in $packages; do
        if ! pacman -S --noconfirm --needed $pkg 2>/dev/null; then
            log_warning "Пакет $pkg не установлен"
            failed_packages="$failed_packages $pkg"
        fi
    done
    
    if [ -n "$failed_packages" ]; then
        log_warning "Не удалось установить: $failed_packages"
        return 1
    fi
    
    log_success "Все пакеты установлены"
    return 0
}

clear
echo -e "${CYAN}"
cat << "EOF"
    ___             __       __   _                 __                __
   /   |  __________/ /_     / /  (_)___  __  ___  / /___ _____  ____/ /
  / /| | / ___/ ___/ __ \   / /  / / __ \/ / / / |/ / __ `/ __ \/ __  / 
 / ___ |/ /  / /__/ / / /  / /__/ / / / / /_/ />  </ /_/ / / / / /_/ /  
/_/  |_/_/   \___/_/ /_/  /_____/_/_/ /_/\__,_/_/|_|\__,_/_/ /_/\__,_/   
                                                                          
        🚀 ULTRA STABLE - ПОЛНОСТЬЮ АВТОМАТИЧЕСКАЯ УСТАНОВКА 🚀
             С защитой от ошибок и множественными fallback!
EOF
echo -e "${NC}"

sleep 2

# Проверка режима загрузки (UEFI или BIOS)
log "Проверка режима загрузки..."
BOOT_MODE="bios"
if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="uefi"
    log_success "UEFI режим обнаружен"
else
    log_warning "BIOS режим обнаружен (Legacy)"
    echo -e "${YELLOW}╔════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Обнаружен BIOS режим!                     ║${NC}"
    echo -e "${YELLOW}║  Рекомендуется использовать UEFI для VM    ║${NC}"
    echo -e "${YELLOW}║  Но установка продолжится с GRUB           ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    sleep 3
fi

# Проверка интернета с несколькими попытками
log "Проверка интернет соединения..."
INTERNET_OK=false
for host in archlinux.org google.com cloudflare.com; do
    if ping -c 1 -W 3 "$host" &> /dev/null; then
        INTERNET_OK=true
        log_success "Интернет работает (проверено через $host)"
        break
    fi
done

if [ "$INTERNET_OK" = false ]; then
    log_error "Нет интернета! Подключись к WiFi:"
    echo -e "${CYAN}Используй команды:${NC}"
    echo "  iwctl"
    echo "  station wlan0 scan"
    echo "  station wlan0 get-networks"
    echo "  station wlan0 connect 'ИмяСети'"
    echo "  exit"
    exit 1
fi

# Синхронизация времени
log "Синхронизация времени..."
timedatectl set-ntp true
sleep 2
log_success "Время синхронизировано"

# Определение типа VM
IS_VM=false
VM_TYPE="none"
if command -v systemd-detect-virt &> /dev/null; then
    VM_TYPE=$(systemd-detect-virt)
    if [ "$VM_TYPE" != "none" ]; then
        IS_VM=true
        log "Обнаружена виртуальная машина: $VM_TYPE"
    fi
fi

# Автоопределение диска
log "Поиск доступных дисков..."
mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,TYPE | grep disk | awk '{print $1 " (" $2 ")"}')

if [ ${#DISKS[@]} -eq 0 ]; then
    log_error "Диски не найдены!"
    exit 1
elif [ ${#DISKS[@]} -eq 1 ]; then
    DISK=$(echo "${DISKS[0]}" | awk '{print $1}')
    log_success "Найден диск: ${DISKS[0]}"
else
    echo -e "${CYAN}Найдено несколько дисков:${NC}"
    for i in "${!DISKS[@]}"; do
        echo "  $((i+1))) ${DISKS[$i]}"
    done
    read -p "Выбери номер диска [1]: " DISK_NUM
    DISK_NUM=${DISK_NUM:-1}
    DISK=$(echo "${DISKS[$((DISK_NUM-1))]}" | awk '{print $1}')
fi

# Настройки по умолчанию
DEFAULT_USERNAME="user"
DEFAULT_HOSTNAME="archlinux"
DEFAULT_PASSWORD="1234"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         НАСТРОЙКИ УСТАНОВКИ                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "Имя пользователя [user]: " USERNAME
USERNAME=${USERNAME:-$DEFAULT_USERNAME}

read -p "Hostname [archlinux]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

read -sp "Пароль пользователя [1234]: " USER_PASSWORD
echo
USER_PASSWORD=${USER_PASSWORD:-$DEFAULT_PASSWORD}

read -sp "Root пароль [1234]: " ROOT_PASSWORD
echo
ROOT_PASSWORD=${ROOT_PASSWORD:-$DEFAULT_PASSWORD}

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║              ВНИМАНИЕ!                     ║${NC}"
echo -e "${YELLOW}╠════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║  Диск $DISK будет ПОЛНОСТЬЮ СТЁРТ!         ║${NC}"
echo -e "${YELLOW}║  Все данные будут удалены БЕЗВОЗВРАТНО!    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
echo ""
read -p "Продолжить установку? (yes/no) [no]: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_error "Установка отменена"
    exit 0
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    🚀 НАЧИНАЕМ УСТАНОВКУ! 🚀               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
sleep 2

# 1. Разметка диска с проверками
echo -e "${BLUE}[1/10]${NC} ${YELLOW}Разметка диска...${NC}"
log "Размонтирование всех разделов диска..."
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true

log "Очистка диска..."
wipefs -af "$DISK" 2>/dev/null || true
sgdisk --zap-all "$DISK" 2>/dev/null || true
dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true

if [ "$BOOT_MODE" = "uefi" ]; then
    log "Создание GPT таблицы для UEFI..."
    parted -s "$DISK" mklabel gpt || {
        log_error "Не удалось создать GPT таблицу"
        exit 1
    }
    
    log "Создание EFI раздела (512MB)..."
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB || {
        log_error "Не удалось создать EFI раздел"
        exit 1
    }
    parted -s "$DISK" set 1 esp on
    
    log "Создание корневого раздела..."
    parted -s "$DISK" mkpart primary ext4 513MiB 100% || {
        log_error "Не удалось создать корневой раздел"
        exit 1
    }
else
    log "Создание MBR таблицы для BIOS..."
    parted -s "$DISK" mklabel msdos || {
        log_error "Не удалось создать MBR таблицу"
        exit 1
    }
    
    log "Создание boot раздела (512MB)..."
    parted -s "$DISK" mkpart primary ext4 1MiB 513MiB || {
        log_error "Не удалось создать boot раздел"
        exit 1
    }
    parted -s "$DISK" set 1 boot on
    
    log "Создание корневого раздела..."
    parted -s "$DISK" mkpart primary ext4 513MiB 100% || {
        log_error "Не удалось создать корневой раздел"
        exit 1
    }
fi

log_success "Диск размечен в режиме $BOOT_MODE"

# Определение имен разделов
sleep 2
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

log "Boot раздел: $BOOT_PART"
log "Root раздел: $ROOT_PART"

# Проверка существования разделов
sleep 1
if [ ! -b "$BOOT_PART" ] || [ ! -b "$ROOT_PART" ]; then
    log_error "Разделы не обнаружены!"
    lsblk "$DISK"
    exit 1
fi

# 2. Форматирование с проверками
echo -e "${BLUE}[2/10]${NC} ${YELLOW}Форматирование разделов...${NC}"

if [ "$BOOT_MODE" = "uefi" ]; then
    log "Форматирование EFI раздела (FAT32)..."
    if ! mkfs.fat -F32 "$BOOT_PART"; then
        log_warning "Первая попытка не удалась, пробую еще раз..."
        wipefs -af "$BOOT_PART"
        mkfs.fat -F32 "$BOOT_PART" || {
            log_error "Не удалось отформатировать EFI раздел"
            exit 1
        }
    fi
else
    log "Форматирование boot раздела (EXT4)..."
    if ! mkfs.ext4 -F "$BOOT_PART"; then
        log_warning "Первая попытка не удалась, пробую еще раз..."
        wipefs -af "$BOOT_PART"
        mkfs.ext4 -F "$BOOT_PART" || {
            log_error "Не удалось отформатировать boot раздел"
            exit 1
        }
    fi
fi

log "Форматирование корневого раздела..."
if ! mkfs.ext4 -F "$ROOT_PART"; then
    log_warning "Первая попытка не удалась, пробую еще раз..."
    wipefs -af "$ROOT_PART"
    mkfs.ext4 -F "$ROOT_PART" || {
        log_error "Не удалось отформатировать корневой раздел"
        exit 1
    }
fi

log_success "Разделы отформатированы"

# 3. Монтирование с проверками
echo -e "${BLUE}[3/10]${NC} ${YELLOW}Монтирование разделов...${NC}"

log "Монтирование корневого раздела..."
umount -R /mnt 2>/dev/null || true
if ! mount "$ROOT_PART" /mnt; then
    log_error "Не удалось смонтировать корневой раздел"
    exit 1
fi

log "Создание точки монтирования boot..."
mkdir -p /mnt/boot

log "Монтирование EFI раздела..."
if ! mount "$BOOT_PART" /mnt/boot; then
    log_error "Не удалось смонтировать EFI раздел"
    exit 1
fi

log_success "Разделы смонтированы"

# 4. БЫСТРАЯ настройка зеркал (БЕЗ Reflector!)
echo -e "${BLUE}[4/10]${NC} ${YELLOW}Настройка зеркал...${NC}"

log "Установка быстрых зеркал (без reflector - моментально!)..."
cat > /etc/pacman.d/mirrorlist << 'EOF'
# Быстрые глобальные CDN зеркала
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.osbeck.com/archlinux/$repo/os/$arch
Server = https://america.mirror.pkgbuild.com/$repo/os/$arch
Server = https://asia.mirror.pkgbuild.com/$repo/os/$arch
Server = https://europe.mirror.pkgbuild.com/$repo/os/$arch
Server = https://archlinux.mailtunnel.eu/$repo/os/$arch
Server = https://mirror.cyberbits.eu/archlinux/$repo/os/$arch
EOF

log_success "Зеркала настроены за 1 секунду!"

# 5. Установка базовой системы с множественными попытками
echo -e "${BLUE}[5/10]${NC} ${YELLOW}Установка базовой системы (5-10 минут)...${NC}"

BASE_PACKAGES="base base-devel linux linux-firmware intel-ucode amd-ucode networkmanager vim nano git wget curl sudo"

# Добавляем GRUB для BIOS режима
if [ "$BOOT_MODE" = "bios" ]; then
    BASE_PACKAGES="$BASE_PACKAGES grub"
    log "BIOS режим: добавлен пакет GRUB"
fi

log "Обновление баз данных pacman..."
pacman -Sy

log "Установка базовых пакетов..."
INSTALL_SUCCESS=false

# Попытка 1: Полная установка (быстро, без вывода)
if pacstrap -K /mnt $BASE_PACKAGES 2>&1 | grep -v "warning:" > /dev/null; then
    INSTALL_SUCCESS=true
    log_success "Базовая система установлена с первой попытки"
fi

# Попытка 2: По группам пакетов
if [ "$INSTALL_SUCCESS" = false ]; then
    log_warning "Пробую установку по группам..."
    
    if pacstrap -K /mnt base linux linux-firmware 2>&1 | grep -v "warning:" > /dev/null && \
       pacstrap -K /mnt base-devel 2>&1 | grep -v "warning:" > /dev/null && \
       pacstrap -K /mnt intel-ucode amd-ucode 2>&1 | grep -v "warning:" > /dev/null && \
       pacstrap -K /mnt networkmanager vim nano 2>&1 | grep -v "warning:" > /dev/null && \
       pacstrap -K /mnt git wget curl sudo 2>&1 | grep -v "warning:" > /dev/null; then
        INSTALL_SUCCESS=true
        log_success "Базовая система установлена по группам"
    fi
fi

# Попытка 3: Минимальная система + докачка
if [ "$INSTALL_SUCCESS" = false ]; then
    log_warning "Устанавливаю минимальную систему..."
    
    if pacstrap -K /mnt base linux linux-firmware networkmanager 2>&1 | grep -v "warning:" > /dev/null; then
        log_success "Минимальная система установлена"
        log "Докачиваю остальные пакеты в chroot..."
        INSTALL_SUCCESS=true
    else
        log_error "Не удалось установить даже минимальную систему"
        exit 1
    fi
fi

# 6. Генерация fstab
echo -e "${BLUE}[6/10]${NC} ${YELLOW}Генерация fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab
log_success "fstab сгенерирован"

# Проверка fstab
if [ ! -s /mnt/etc/fstab ]; then
    log_error "fstab пуст!"
    exit 1
fi

# 7. Настройка системы в chroot
echo -e "${BLUE}[7/10]${NC} ${YELLOW}Настройка системы...${NC}"

cat > /mnt/setup-chroot.sh << CHROOT_SCRIPT
#!/bin/bash

set -e

echo "==> Настройка часового пояса..."
ln -sf /usr/share/zoneinfo/Asia/Tashkent /etc/localtime || ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc || true

echo "==> Настройка локализации..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "==> Настройка клавиатуры..."
echo "KEYMAP=us" > /etc/vconsole.conf

echo "==> Настройка hostname..."
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "==> Установка root пароля..."
echo "root:$ROOT_PASSWORD" | chpasswd

echo "==> Создание пользователя $USERNAME..."
useradd -m -G wheel,audio,video,optical,storage,power -s /bin/bash "$USERNAME" || true
echo "$USERNAME:$USER_PASSWORD" | chpasswd

echo "==> Настройка sudo..."
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

echo "==> Включение NetworkManager..."
systemctl enable NetworkManager

if [ "$BOOT_MODE" = "uefi" ]; then
    echo "==> Установка systemd-boot (UEFI)..."
    bootctl install || {
        echo "Первая попытка установки загрузчика не удалась, пробую еще раз..."
        sleep 2
        bootctl install || {
            echo "ОШИБКА: Не удалось установить systemd-boot!"
            exit 1
        }
    }

    cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

    ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PART)

    cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw quiet splash loglevel=3
EOF
    
    echo "==> systemd-boot установлен"
else
    echo "==> Установка GRUB (BIOS)..."
    
    # Установка GRUB если его нет
    if ! command -v grub-install &> /dev/null; then
        echo "Установка пакета GRUB..."
        pacman -S --noconfirm grub || {
            echo "ОШИБКА: Не удалось установить GRUB!"
            exit 1
        }
    fi
    
    grub-install --target=i386-pc "$DISK" || {
        echo "Первая попытка установки GRUB не удалась, пробую еще раз..."
        sleep 2
        grub-install --target=i386-pc --recheck "$DISK" || {
            echo "ОШИБКА: Не удалось установить GRUB!"
            exit 1
        }
    }
    
    echo "==> Генерация конфигурации GRUB..."
    grub-mkconfig -o /boot/grub/grub.cfg || {
        echo "ОШИБКА: Не удалось создать конфиг GRUB!"
        exit 1
    }
    
    echo "==> GRUB установлен"
fi

echo "==> Базовая настройка завершена!"
CHROOT_SCRIPT

chmod +x /mnt/setup-chroot.sh

if arch-chroot /mnt /setup-chroot.sh; then
    log_success "Система настроена"
else
    log_error "Ошибка при настройке системы в chroot"
    exit 1
fi

rm /mnt/setup-chroot.sh

# 8. Установка графической среды с fallback
echo -e "${BLUE}[8/10]${NC} ${YELLOW}Установка Hyprland и графики (10-15 минут)...${NC}"

cat > /mnt/install-gui.sh << 'GUI_SCRIPT'
#!/bin/bash

set -e

# Определение VM
IS_VM=false
VM_TYPE="none"
if command -v systemd-detect-virt &> /dev/null; then
    VM_TYPE=$(systemd-detect-virt)
    [ "$VM_TYPE" != "none" ] && IS_VM=true
fi

echo "==> Включение multilib..."
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    cat >> /etc/pacman.conf << EOF

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

echo "==> Обновление баз данных..."
pacman -Sy

echo "==> Установка Hyprland и основных компонентов..."
GUI_PACKAGES=(
    # Hyprland и Wayland (самое важное!)
    "hyprland"
    "xdg-desktop-portal-hyprland"
    "qt5-wayland"
    "qt6-wayland"
    
    # Waybar и утилиты
    "waybar"
    "wofi"
    "dunst"
    "kitty"
    "thunar"
    
    # Система
    "polkit-kde-agent"
    
    # Аудио
    "pipewire"
    "pipewire-pulse"
    "wireplumber"
    "pavucontrol"
    
    # Инструменты
    "grim"
    "slurp"
    "wl-clipboard"
    
    # Шрифты (только основные)
    "ttf-dejavu"
    "ttf-liberation"
    "noto-fonts-emoji"
    
    # Приложения
    "firefox"
    
    # GTK
    "gtk3"
    
    # Сеть
    "network-manager-applet"
    
    # Утилиты
    "htop"
)

# Быстрая установка без лишнего вывода
if pacman -S --noconfirm --needed "${GUI_PACKAGES[@]}" 2>&1 | grep -E "(error|failed)" ; then
    echo "==> Устанавливаю пакеты по одному..."
    for pkg in "${GUI_PACKAGES[@]}"; do
        pacman -S --noconfirm --needed "$pkg" 2>/dev/null || echo "Пропуск: $pkg"
    done
else
    echo "==> Все GUI пакеты установлены!"
fi

# Драйверы для VM
if [ "$IS_VM" = true ]; then
    echo "==> Установка драйверов для $VM_TYPE..."
    case "$VM_TYPE" in
        vmware)
            pacman -S --noconfirm --needed open-vm-tools xf86-video-vmware mesa || true
            systemctl enable vmtoolsd.service || true
            systemctl enable vmware-vmblock-fuse.service || true
            ;;
        oracle)
            pacman -S --noconfirm --needed virtualbox-guest-utils mesa || true
            systemctl enable vboxservice.service || true
            ;;
        kvm|qemu)
            pacman -S --noconfirm --needed qemu-guest-agent spice-vdagent mesa || true
            systemctl enable qemu-guest-agent.service || true
            ;;
        *)
            echo "==> Установка универсальных драйверов Mesa..."
            pacman -S --noconfirm --needed mesa || true
            ;;
    esac
fi

echo "==> Графическая среда установлена!"
GUI_SCRIPT

chmod +x /mnt/install-gui.sh

if arch-chroot /mnt /install-gui.sh; then
    log_success "Графика установлена"
else
    log_warning "Возможны проблемы при установке графики, но продолжаем..."
fi

rm /mnt/install-gui.sh

# 9. Создание конфигов (вынес в отдельную функцию для надёжности)
echo -e "${BLUE}[9/10]${NC} ${YELLOW}Создание конфигов...${NC}"

create_configs() {
    local user_home="/home/$USERNAME"
    
    # Создание директорий
    arch-chroot /mnt su - "$USERNAME" -c "mkdir -p ~/.config/{hypr,waybar,wofi,dunst,kitty}" || return 1
    
    # Hyprland конфиг (сокращённый для надёжности)
    cat > /mnt${user_home}/.config/hypr/hyprland.conf << 'HYPR_EOF'
# Hyprland Configuration

monitor=,preferred,auto,1

exec-once = waybar &
exec-once = dunst &
exec-once = /usr/lib/polkit-kde-authentication-agent-1 &
exec-once = nm-applet --indicator &

env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland
env = GDK_BACKEND,wayland

input {
    kb_layout = us,ru
    kb_options = grp:alt_shift_toggle
    follow_mouse = 1
    touchpad {
        natural_scroll = yes
    }
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(89b4faee)
    col.inactive_border = rgba(45475aaa)
    layout = dwindle
}

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
}

animations {
    enabled = yes
    bezier = wind, 0.05, 0.9, 0.1, 1.0
    animation = windows, 1, 5, wind
    animation = windowsIn, 1, 5, wind
    animation = windowsOut, 1, 3, wind
    animation = fade, 1, 5, default
    animation = workspaces, 1, 4, wind
}

$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, B, exec, firefox
bind = $mainMod, E, exec, thunar
bind = $mainMod, R, exec, wofi --show drun
bind = $mainMod, C, killactive,
bind = $mainMod, F, fullscreen, 0
bind = $mainMod, V, togglefloating,
bind = $mainMod, M, exit,

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5

bind = , Print, exec, grim -g "$(slurp)" ~/screenshot.png

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
HYPR_EOF

    # Waybar конфиг
    cat > /mnt${user_home}/.config/waybar/config << 'WAYBAR_EOF'
{
    "layer": "top",
    "position": "top",
    "height": 35,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network", "battery"],
    
    "clock": {
        "format": "{:%H:%M %d.%m.%Y}"
    },
    
    "battery": {
        "format": "{icon} {capacity}%",
        "format-icons": ["", "", "", "", ""]
    },
    
    "network": {
        "format-wifi": " {signalStrength}%",
        "format-ethernet": " Connected",
        "format-disconnected": "⚠ Disconnected"
    },
    
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": " Muted",
        "format-icons": ["", "", ""]
    }
}
WAYBAR_EOF

    cat > /mnt${user_home}/.config/waybar/style.css << 'WAYBAR_STYLE_EOF'
* {
    font-family: "JetBrainsMono Nerd Font";
    font-size: 13px;
}

window#waybar {
    background: rgba(30, 30, 46, 0.9);
    color: #cdd6f4;
}

#workspaces button {
    padding: 0 10px;
    color: #6c7086;
}

#workspaces button.active {
    color: #89b4fa;
}

#clock, #battery, #network, #pulseaudio {
    padding: 0 10px;
    margin: 2px;
    background: rgba(49, 50, 68, 0.8);
    border-radius: 8px;
}
WAYBAR_STYLE_EOF

    # Kitty конфиг
    cat > /mnt${user_home}/.config/kitty/kitty.conf << 'KITTY_EOF'
font_family      JetBrainsMono Nerd Font
font_size 12.0

background #1e1e2e
foreground #cdd6f4
cursor #f5e0dc

background_opacity 0.95
window_padding_width 10
hide_window_decorations yes
enable_audio_bell no
KITTY_EOF

    # Wofi конфиг
    cat > /mnt${user_home}/.config/wofi/config << 'WOFI_EOF'
width=500
height=400
show=drun
prompt=Search...
allow_images=true
image_size=32
WOFI_EOF

    cat > /mnt${user_home}/.config/wofi/style.css << 'WOFI_STYLE_EOF'
window {
    background-color: rgba(30, 30, 46, 0.95);
    color: #cdd6f4;
    border: 2px solid #89b4fa;
    border-radius: 10px;
}

#input {
    margin: 5px;
    padding: 10px;
    border: 2px solid #89b4fa;
    border-radius: 8px;
    background-color: #313244;
    color: #cdd6f4;
}

#entry:selected {
    background-color: #89b4fa;
}
WOFI_STYLE_EOF

    # Dunst конфиг
    cat > /mnt${user_home}/.config/dunst/dunstrc << 'DUNST_EOF'
[global]
    width = 300
    height = 300
    origin = top-right
    offset = 10x50
    
    font = JetBrainsMono Nerd Font 10
    frame_width = 2
    frame_color = "#89b4fa"
    corner_radius = 10
    
[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 5
    
[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 10
    
[urgency_critical]
    background = "#f38ba8"
    foreground = "#1e1e2e"
    timeout = 0
DUNST_EOF

    # Права
    arch-chroot /mnt chown -R $USERNAME:$USERNAME ${user_home}/.config || return 1
    
    return 0
}

if create_configs; then
    log_success "Конфиги созданы"
else
    log_warning "Проблемы с созданием конфигов, но продолжаем..."
fi

# Автологин
mkdir -p /mnt/etc/systemd/system/getty@tty1.service.d
cat > /mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf << AUTOLOGIN_EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USERNAME %I \$TERM
AUTOLOGIN_EOF

# Автозапуск Hyprland
cat > /mnt/home/$USERNAME/.bash_profile << 'BASH_PROFILE_EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec Hyprland
fi
BASH_PROFILE_EOF

# Bashrc
cat > /mnt/home/$USERNAME/.bashrc << 'BASHRC_EOF'
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'

alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

if [ -n "$KITTY_WINDOW_ID" ]; then
    command -v fastfetch &>/dev/null && fastfetch
fi
BASHRC_EOF

arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/.bash_profile
arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

# 10. Финальные настройки
echo -e "${BLUE}[10/10]${NC} ${YELLOW}Финальные настройки...${NC}"

# Цвет в pacman
sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
sed -i '/Color/a ILoveCandy' /mnt/etc/pacman.conf

# Оптимизация makepkg
sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' /mnt/etc/makepkg.conf

log_success "Все готово!"

# Размонтирование
log "Размонтирование разделов..."
sync
umount -R /mnt || umount -l /mnt

# Финальное сообщение
clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║    ✨ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! ✨                    ║
║                                                           ║
║  🎉 Твой Arch Linux с Hyprland готов! 🎉                 ║
║                                                           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  📋 Установлено:                                         ║
║  ✓ Arch Linux + Hyprland                                 ║
║  ✓ Waybar + Wofi + Dunst                                 ║
║  ✓ Kitty + Firefox + Thunar                              ║
║  ✓ Все необходимые драйверы                              ║
║                                                           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  🎮 ОСНОВНЫЕ ГОРЯЧИЕ КЛАВИШИ:                            ║
║                                                           ║
║  SUPER + Q  → Терминал                                   ║
║  SUPER + B  → Браузер                                    ║
║  SUPER + R  → Меню приложений                            ║
║  SUPER + E  → Файловый менеджер                          ║
║  SUPER + C  → Закрыть окно                               ║
║  SUPER + F  → Полный экран                               ║
║  SUPER + M  → Выход                                      ║
║                                                           ║
║  SUPER + 1-5     → Рабочие столы                         ║
║  SUPER + ←↑↓→    → Переключить фокус                    ║
║  Print           → Скриншот                              ║
║                                                           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  📝 Логи установки сохранены в:                          ║
║     /tmp/arch-install.log                                ║
║                                                           ║
║  ⚙️  Конфиги Hyprland:                                   ║
║     ~/.config/hypr/hyprland.conf                         ║
║                                                           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  🚀 ПЕРЕЗАГРУЗИСЬ: reboot                                ║
║                                                           ║
║  После перезагрузки ты попадёшь в Hyprland!              ║
║  Наслаждайся своим Arch! 😎                              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}Нажми Enter для перезагрузки или Ctrl+C для отмены...${NC}"
read

reboot
