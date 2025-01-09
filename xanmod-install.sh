!/bin/bash

# 定义全局变量
install_headers=0
cpu_version="v3"
SCRIPT_VERSION="2.0"
LOG_FILE="/var/log/xanmod_install.log"

# 定义颜色输出函数
purple() { echo -e "\033[35;1m${*}\033[0m"; }
tyblue() { echo -e "\033[36;1m${*}\033[0m"; }
green() { echo -e "\033[32;1m${*}\033[0m"; }
yellow() { echo -e "\033[33;1m${*}\033[0m"; }
red() { echo -e "\033[31;1m${*}\033[0m"; }
blue() { echo -e "\033[34;1m${*}\033[0m"; }

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_and_show() {
    log "$1"
    echo "$1"
}

# 检查基本命令
check_base_command() {
    local temp_command_list=('bash' 'true' 'false' 'exit' 'echo' 'test' 'sort' 'sed' 'awk' 'grep' 'cut' 'cd' 'rm' 'cp' 'mv' 'head' 'tail' 'uname' 'tr' 'md5sum' 'cat' 'find' 'type' 'command' 'wc' 'ls' 'mktemp' 'swapon' 'swapoff' 'mkswap' 'chmod' 'chown' 'export')

    for cmd in "${temp_command_list[@]}"; do
        if ! command -V "$cmd" > /dev/null; then
            log_and_show "命令\"$cmd\"未找到，不是标准的Linux系统"
            exit 1
        fi
    done
}

# 安装依赖
test_important_dependence_installed() {
    local pkg="$1"
    local temp_exit_code=1

    if LANG="en_US.UTF-8" LANGUAGE="en_US:en" dpkg -s "$pkg" 2>/dev/null | grep -qi 'status[ '$'\t]*:[ '$'\t]*install[ '$'\t]*ok[ '$'\t]*installed[ '$'\t]*$'; then
        if LANG="en_US.UTF-8" LANGUAGE="en_US:en" apt-mark manual "$pkg" | grep -qi 'set[ '$'\t]*to[ '$'\t]*manually[ '$'\t]*installed'; then
            temp_exit_code=0
        else
            log_and_show "安装依赖 \"$pkg\" 出错！"
        fi
    elif apt -y --no-install-recommends install "$pkg"; then
        temp_exit_code=0
    else
        apt update
        apt -y -f install
        apt -y --no-install-recommends install "$pkg" && temp_exit_code=0
    fi
    return $temp_exit_code
}

check_important_dependence_installed() {
    if ! test_important_dependence_installed "$1"; then
        log_and_show "重要组件\"$1\"安装失败！"
        yellow "按回车键继续或者Ctrl+c退出"
        read -s
    fi
}

# 清理旧的源配置
cleanup_old_sources() {
    if [[ -f '/etc/apt/sources.list.d/xanmod-kernel.list' ]]; then
        log "清理旧的源文件"
        sudo rm /etc/apt/sources.list.d/xanmod-kernel.list
        sudo rm /etc/apt/trusted.gpg.d/xanmod-kernel.gpg 2>/dev/null
    fi
}

# 询问函数
ask_if() {
    local choice=""
    while [ "$choice" != "y" ] && [ "$choice" != "n" ]; do
        tyblue "$1"
        read -r choice
    done
    [ "$choice" == "y" ] && return 0
    return 1
}


# 检查系统环境
check_system() {
    log "开始检查系统环境"

    if [[ -d "/proc/vz" ]]; then
        log_and_show "Error: Your VPS is based on OpenVZ, which is not supported."
        exit 1
    fi

    if [[ ! "$(type -P apt)" ]]; then
        log_and_show "xanmod内核仅支持Debian系的系统"
        exit 1
    fi

    if [[ "$(type -P apt)" ]] && [[ "$(type -P dnf)" || "$(type -P yum)" ]]; then
        log_and_show "同时存在apt和yum/dnf，不支持的系统！"
        exit 1
    fi

    if [ "$EUID" != "0" ]; then
        log_and_show "请用root用户运行此脚本！"
        exit 1
    fi
}

# 检查CPU
check_cpu() {
    log "开始检查CPU版本"
    tyblue "===============检查CPU版本==============="

    rm -f check_x86-64_psabi.sh
    if ! wget -q https://dl.xanmod.org/check_x86-64_psabi.sh; then
        log_and_show "下载CPU检查脚本失败"
        exit 1
    fi

    chmod +x check_x86-64_psabi.sh
    output=$(./check_x86-64_psabi.sh)
    exit_code=$?
    echo "Exit code: $exit_code"
   if [ $exit_code -eq 1 ]; then
    log_and_show "CPU doesn't meet required feature set"
    exit 1
    elif [ $exit_code -ge 2 ]; then
    log_and_show "CPU supports x86-64-v$((exit_code - 1))"
    #exit 0
     fi
    echo "获取到的cpu版本:"
    echo "$output"
    version=$(echo "$output" | grep -oP 'x86-64-v\K\d+')

    echo "$version" 
    if [ -z "$version" ]; then
        log_and_show "无法确定CPU版本"
        exit 1
    fi
     if [ "$version" -gt 3 ]; then
        red "高版本取消了v4，故这里需要由4改3"
        version=3
     fi

        echo "value: $version"

    cpu_version="x64v$version"
    log "检测到CPU版本: $cpu_version"
}

# 内核选择菜单
menu() {
    tyblue "===============安装xanmod内核==============="
    tyblue " 请选择你想安装的版本："
    green  "   1.EDGE(推荐)"
    green  "   2.STABLE(推荐)"
    tyblue "   3.TT"
    tyblue "   4.RT-EDGE"
    tyblue "   5.RT"
    tyblue "   6.LTS"
    red    "   7.不安装"
    echo

    local choice=""
    while [[ ! "$choice" =~ ^([1-9][0-9]*)$ ]] || ((choice>7)); do
        read -p "您的选择是：" choice
    done

    [ $choice -eq 7 ] && exit 0

    local xanmod_list=("-edge" "" "-tt" "-rt-edge" "-rt" "-lts")
    install="linux-xanmod${xanmod_list[$((choice-1))]}"
    log "选择的内核版本: $install"
}

# 检查内存
check_mem() {
    log "检查系统内存"
    if (($(free -m | sed -n 2p | awk '{print $2}')<300)); then
        red    "检测到内存小于300M，更换内核可能无法开机，请谨慎选择"
        yellow "按回车键以继续或ctrl+c中止"
        read -s
        echo
        log "警告：系统内存不足300M"
    fi
}

# 配置XanMod源
configure_xanmod_source() {
    log "配置XanMod源"
    cleanup_old_sources

    # 创建必要的目录
    sudo mkdir -p /etc/apt/keyrings

    # 下载并添加GPG密钥
    if ! wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg; then
        log_and_show "添加密钥失败！"
        exit 1
    fi

    # 添加软件源
    if ! echo 'deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list; then
        log_and_show "添加源失败！"
        exit 1
    fi

    # 更新软件源
    if ! apt update; then
        log_and_show "更新源失败！"
        exit 1
    fi
}

# 删除其他内核
remove_other_kernel() {
    log "开始删除其他内核"
    local temp_file
    temp_file="$(mktemp)"
    dpkg --list > "$temp_file"

    local kernel_list_headers=($(awk '{print $2}' "$temp_file" | grep '^linux-headers'))
    local kernel_list_image=($(awk '{print $2}' "$temp_file" | grep '^linux-image'))
    local kernel_list_modules=($(awk '{print $2}' "$temp_file" | grep '^linux-modules'))
    rm "$temp_file"

    local ok_install=0
    for ((i=${#kernel_list_image[@]}-1;i>=0;i--)); do
        if [ "${kernel_list_image[$i]}" == "${install_image_list[0]}" ]; then
            unset 'kernel_list_image[$i]'
            ((ok_install++))
        fi
    done

    if [ "$ok_install" -lt "1" ]; then
        log_and_show "内核可能安装失败！不卸载"
        return 1
    fi

    if [ ${#install_modules_list[@]} -eq 1 ]; then
        ok_install=0
        for ((i=${#kernel_list_modules[@]}-1;i>=0;i--)); do
            if [ "${kernel_list_modules[$i]}" == "${install_modules_list[0]}" ]; then
                unset 'kernel_list_modules[$i]'
                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ]; then
            log_and_show "内核可能安装失败！不卸载"
            return 1
        fi
    fi

    if [ $install_headers -eq 1 ]; then
        ok_install=0
        for ((i=${#kernel_list_headers[@]}-1;i>=0;i--)); do
            if [ "${kernel_list_headers[$i]}" == "${install_headers_list[0]}" ]; then
                unset 'kernel_list_headers[$i]'
                                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ]; then
            log_and_show "内核可能安装失败！不卸载"
            return 1
        fi
    fi

    if [ ${#kernel_list_image[@]} -eq 0 ] && [ ${#kernel_list_modules[@]} -eq 0 ] && ([ $install_headers -eq 0 ] || [ ${#kernel_list_headers[@]} -eq 0 ]); then
        log_and_show "未发现可卸载内核！不卸载"
        return 1
    fi

    yellow "卸载过程中如果询问YES/NO，请选择NO！"
    yellow "卸载过程中如果询问YES/NO，请选择NO！"
    yellow "卸载过程中如果询问YES/NO，请选择NO！"
    tyblue "按回车键以继续。。"
    read -s

    local exit_code=1
    if [ $install_headers -eq 1 ]; then
        apt -y purge "${kernel_list_image[@]}" "${kernel_list_modules[@]}" "${kernel_list_headers[@]}" && exit_code=0
    else
        apt -y purge "${kernel_list_image[@]}" "${kernel_list_modules[@]}" && exit_code=0
    fi

    if [ $exit_code -eq 0 ]; then
        apt-mark manual "^grub"
        log_and_show "卸载完成"
    else
        apt -y -f install
        apt-mark manual "^grub"
        log_and_show "卸载失败！"
    fi
}

# 主函数
main() {
    # 初始化日志
    log "=== 开始XanMod内核安装 脚本版本:$SCRIPT_VERSION ==="

    # 系统检查
    check_system

    # 选择内核版本
    menu

    # 安装依赖
    check_important_dependence_installed procps
    check_important_dependence_installed gnupg1
    check_important_dependence_installed wget
    check_important_dependence_installed ca-certificates
    check_important_dependence_installed initramfs-tools

    # 环境检查
    check_mem
    check_cpu

    # 设置安装版本
    install="$install-$cpu_version"
    echo "最终安装版本: $install"

    # 配置源
    configure_xanmod_source

    # 获取依赖列表
    local temp_list=($(LANG="en_US.UTF-8" LANGUAGE="en_US:en" apt-cache depends "$install" | grep -i "Depends:" | awk '{print $2}'))

    echo "列表内容：$temp_list"


    # 分析依赖
    local install_headers_list=()
    local install_image_list=()
    local install_modules_list=()
    for i in "${!temp_list[@]}"; do
    if [[ "${temp_list[$i]}" =~ ^linux-headers-.*-xanmod ]]; then
        install_headers_list+=("${temp_list[$i]}")
    elif [[ "${temp_list[$i]}" =~ ^linux-image-.*-xanmod ]]; then
        install_image_list+=("${temp_list[$i]}")
    elif [[ "${temp_list[$i]}" =~ ^linux-modules-.*-xanmod ]]; then
        install_modules_list+=("${temp_list[$i]}")
    fi
done

# 验证依赖
if [ ${#install_image_list[@]} -ne 1 ] || [ ${#install_modules_list[@]} -gt 1 ] || ([ $install_headers -eq 1 ] && [ ${#install_headers_list[@]} -ne 1 ]); then
    log_and_show "获取版本异常"
    exit 1
fi

# 安装内核
local exit_code=1
if [ $install_headers -eq 0 ]; then
    log "开始安装内核(不含headers)"
    apt -y --no-install-recommends install "${install_image_list[@]}" "${install_modules_list[@]}" && exit_code=0
else
    log "开始安装内核(含headers)"
    apt -y --no-install-recommends install "${install_image_list[@]}" "${install_modules_list[@]}" "${install_headers_list[@]}" && exit_code=0
fi

# 处理安装失败的情况
[ $exit_code -ne 0 ] && apt -y -f install

if [ $exit_code -ne 0 ]; then
    log_and_show "安装失败！"
    exit 1
fi

green "安装完成"
log "内核安装完成"

# 询问是否删除其他内核
if ask_if "是否卸载其它内核？(y/n)"; then
    remove_other_kernel
fi
    # 处理重启
    yellow "系统需要重启"
    if ask_if "现在重启系统? (y/n)"; then
        log "用户选择立即重启"
        reboot
    else
        yellow "请尽快重启！"
        log "用户选择稍后重启"
    fi
}

# 执行主函数
main
