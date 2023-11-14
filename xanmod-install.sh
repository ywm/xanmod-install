#!/bin/bash
install_headers=0

#定义几个颜色
purple()                           #基佬紫
{
    echo -e "\\033[35;1m${*}\\033[0m"
}
tyblue()                           #天依蓝
{
    echo -e "\\033[36;1m${*}\\033[0m"
}
green()                            #原谅绿
{
    echo -e "\\033[32;1m${*}\\033[0m"
}
yellow()                           #鸭屎黄
{
    echo -e "\\033[33;1m${*}\\033[0m"
}
red()                              #姨妈红
{
    echo -e "\\033[31;1m${*}\\033[0m"
}
blue()                             #蓝色
{
    echo -e "\\033[34;1m${*}\\033[0m"
}
#检查基本命令
check_base_command()
{
    local i
    local temp_command_list=('bash' 'true' 'false' 'exit' 'echo' 'test' 'sort' 'sed' 'awk' 'grep' 'cut' 'cd' 'rm' 'cp' 'mv' 'head' 'tail' 'uname' 'tr' 'md5sum' 'cat' 'find' 'type' 'command' 'wc' 'ls' 'mktemp' 'swapon' 'swapoff' 'mkswap' 'chmod' 'chown' 'export')
    for i in ${!temp_command_list[@]}
    do
        if ! command -V "${temp_command_list[$i]}" > /dev/null; then
            red "命令\"${temp_command_list[$i]}\"未找到"
            red "不是标准的Linux系统"
            exit 1
        fi
    done
}
#安装单个重要依赖
test_important_dependence_installed()
{
    local temp_exit_code=1
    if LANG="en_US.UTF-8" LANGUAGE="en_US:en" dpkg -s "$1" 2>/dev/null | grep -qi 'status[ '$'\t]*:[ '$'\t]*install[ '$'\t]*ok[ '$'\t]*installed[ '$'\t]*$'; then
        if LANG="en_US.UTF-8" LANGUAGE="en_US:en" apt-mark manual "$1" | grep -qi 'set[ '$'\t]*to[ '$'\t]*manually[ '$'\t]*installed'; then
            temp_exit_code=0
        else
            red "安装依赖 \"$1\" 出错！"
            green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
            yellow "按回车键继续或者Ctrl+c退出"
            read -s
        fi
    elif apt -y --no-install-recommends install "$1"; then
        temp_exit_code=0
    else
        apt update
        apt -y -f install
        apt -y --no-install-recommends install "$1" && temp_exit_code=0
    fi
    return $temp_exit_code
}
check_important_dependence_installed()
{
    if ! test_important_dependence_installed "$@"; then
        red "重要组件\"$1\"安装失败！！"
        yellow "按回车键继续或者Ctrl+c退出"
        read -s
    fi
}
ask_if()
{
    local choice=""
    while [ "$choice" != "y" ] && [ "$choice" != "n" ]
    do
        tyblue "$1"
        read choice
    done
    [ $choice == y ] && return 0
    return 1
}

if [[ -d "/proc/vz" ]]; then
    red "Error: Your VPS is based on OpenVZ, which is not supported."
    exit 1
fi
check_base_command
if [[ "$(type -P apt)" ]]; then
    if [[ "$(type -P dnf)" ]] || [[ "$(type -P yum)" ]]; then
        red "同时存在apt和yum/dnf"
        red "不支持的系统！"
        exit 1
    fi
else
    red "xanmod内核仅支持Debian系的系统，如Ubuntu,Debian,deepin,UOS"
    exit 1
fi
if [ "$EUID" != "0" ]; then
    red "请用root用户运行此脚本！！"
    exit 1
fi

menu()
{
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
    while [[ ! "$choice" =~ ^([1-9][0-9]*)$ ]] || ((choice>7))
    do
        read -p "您的选择是：" choice
    done
    [ $choice -eq 7 ] && exit 0
    local xanmod_list=("-edge" "" "-tt" "-rt-edge" "-rt" "-lts")
    install="linux-xanmod${xanmod_list[$((choice-1))]}"
    red "$install"
}

check_mem()
{
    if (($(free -m | sed -n 2p | awk '{print $2}')<300)); then
        red    "检测到内存小于300M，更换内核可能无法开机，请谨慎选择"
        yellow "按回车键以继续或ctrl+c中止"
        read -s
        echo
    fi
}

remove_other_kernel()
{
    local temp_file
    temp_file="$(mktemp)"
    dpkg --list > "$temp_file"
    local kernel_list_headers
    kernel_list_headers=($(awk '{print $2}' "$temp_file" | grep '^linux-headers'))
    local kernel_list_image
    kernel_list_image=($(awk '{print $2}' "$temp_file" | grep '^linux-image'))
    local kernel_list_modules
    kernel_list_modules=($(awk '{print $2}' "$temp_file" | grep '^linux-modules'))
    rm "$temp_file"
    local i
    local ok_install=0
    for ((i=${#kernel_list_image[@]}-1;i>=0;i--))
    do
        if [ "${kernel_list_image[$i]}" == "${install_image_list[0]}" ]; then
            unset 'kernel_list_image[$i]'
            ((ok_install++))
        fi
    done
    if [ "$ok_install" -lt "1" ] ; then
        red "内核可能安装失败！不卸载"
        return 1
    fi
    if [ ${#install_modules_list[@]} -eq 1 ]; then
        ok_install=0
        for ((i=${#kernel_list_modules[@]}-1;i>=0;i--))
        do
            if [ "${kernel_list_modules[$i]}" == "${install_modules_list[0]}" ]; then
                unset 'kernel_list_modules[$i]'
                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ] ; then
            red "内核可能安装失败！不卸载"
            return 1
        fi
    fi
    if [ $install_headers -eq 1 ]; then
        ok_install=0
        for ((i=${#kernel_list_headers[@]}-1;i>=0;i--))
        do
            if [ "${kernel_list_headers[$i]}" == "${install_headers_list[0]}" ]; then
                unset 'kernel_list_headers[$i]'
                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ] ; then
            red "内核可能安装失败！不卸载"
            return 1
        fi
    fi
    if [ ${#kernel_list_image[@]} -eq 0 ] && [ ${#kernel_list_modules[@]} -eq 0 ] && ([ $install_headers -eq 0 ] || [ ${#kernel_list_headers[@]} -eq 0 ]); then
        red "未发现可卸载内核！不卸载"
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
        green "卸载完成"
    else
        apt -y -f install
        apt-mark manual "^grub"
        red "卸载失败！"
    fi
}

main()
{
    menu
    check_important_dependence_installed procps
    check_mem
    check_important_dependence_installed gnupg1
    check_important_dependence_installed wget
    check_important_dependence_installed ca-certificates
    check_important_dependence_installed initramfs-tools
    local temp_xanmod_apt_source=0
    [[ -f '/etc/apt/sources.list.d/xanmod-kernel.list' ]] && temp_xanmod_apt_source=1
    echo 'deb http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    if ! wget -qO - https://dl.xanmod.org/gpg.key | apt-key --keyring /etc/apt/trusted.gpg.d/xanmod-kernel.gpg add -; then
        red "添加源失败！"
        exit 1
    fi
    if ! apt update; then
        red "更新源失败！"
        exit 1
    fi
    local temp_list
    red "$install"
    temp_list=($(LANG="en_US.UTF-8" LANGUAGE="en_US:en" apt-cache depends "$install" | grep -i "Depends:" | awk '{print $2}'))
    red "这里是查看位"
    red "$temp_list"
    local i
    for i in ${!temp_list[@]}
    do
        red "${temp_list[$i]}"
        if [[ "${temp_list[$i]}" =~ ^linux-headers-.*-xanmod ]]; then
            install_headers_list+=("${temp_list[$i]}")
        elif [[ "${temp_list[$i]}" =~ ^linux-image-.*-xanmod ]]; then
            install_image_list+=("${temp_list[$i]}")
        elif [[ "${temp_list[$i]}" =~ ^linux-modules-.*-xanmod ]]; then
            install_modules_list+=("${temp_list[$i]}")
        fi
    done
    green "${#install_image_list[@]}"
    green "${#install_modules_list[@]}"
    green "$install_headers"
    green "${#install_headers_list[@]}"
    if [ ${#install_image_list[@]} -ne 1 ] || [ ${#install_modules_list[@]} -gt 1 ] || ([ $install_headers -eq 1 ] && [ ${#install_headers_list[@]} -ne 1 ]); then
        red "获取版本异常"
        exit 1
    fi
    local exit_code=1
    if [ $install_headers -eq 0 ]; then
        apt -y --no-install-recommends install "${install_image_list[@]}" "${install_modules_list[@]}" && exit_code=0
    else
        apt -y --no-install-recommends install "${install_image_list[@]}" "${install_modules_list[@]}" "${install_headers_list[@]}" && exit_code=0
    fi
    [ $exit_code -ne 0 ] && apt -y -f install
    if [ $temp_xanmod_apt_source -eq 0 ]; then
        rm /etc/apt/sources.list.d/xanmod-kernel.list
        apt update
    fi
    if [ $exit_code -ne 0 ]; then
        red "安装失败！"
        exit 1
    fi
    green "安装完成"
    ask_if "是否卸载其它内核？(y/n)" && remove_other_kernel
    yellow "系统需要重启"
    if ask_if "现在重启系统? (y/n)"; then
        reboot
    else
        yellow "请尽快重启！"
    fi
}

main
