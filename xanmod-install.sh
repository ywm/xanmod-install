#!/bin/bash
install_headers=0

#定义几个颜色
purple()                           #基佬紫
{
    echo -e "\033[35;1m${@}\033[0m"
}
tyblue()                           #天依蓝
{
    echo -e "\033[36;1m${@}\033[0m"
}
green()                            #水鸭青
{
    echo -e "\033[32;1m${@}\033[0m"
}
yellow()                           #鸭屎黄
{
    echo -e "\033[33;1m${@}\033[0m"
}
red()                              #姨妈红
{
    echo -e "\033[31;1m${@}\033[0m"
}

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
    green  "   1.CACULE(推荐)"
    green  "   2.EDGE(推荐)"
    tyblue "   3.STABLE(推荐)"
    tyblue "   4.LTS"
    tyblue "   5.RT-EDGE"
    tyblue "   6.RT-STABLE"
    red    "   7.不安装"
    echo
    local choice=""
    while [[ "$choice" != "1" && "$choice" != "2" && "$choice" != "3" && "$choice" != "4" && "$choice" != "5" && "$choice" != "6" && "$choice" != "7" ]]
    do
        read -p "您的选择是：" choice
    done
    [ $choice -eq 7 ] && exit 0
    local xanmod_list=("-cacule" "-edge" "" "-lts" "-rt-edge" "-rt")
    install="linux-xanmod${xanmod_list[((choice-1))]}"
}

check_mem()
{
    if [ "$(cat /proc/meminfo | grep 'MemTotal' | awk '{print $3}' | tr [:upper:] [:lower:])" == "kb" ]; then
        if [ "$(cat /proc/meminfo | grep 'MemTotal' | awk '{print $2}')" -le 400000 ]; then
            red    "检测到内存过小，更换内核可能无法开机，请谨慎选择"
            yellow "按回车键以继续或ctrl+c中止"
            read -s
            echo
        fi
    else
        red    "请确保服务器的内存>=512MB，否则更换最新版内核可能无法开机"
        yellow "按回车键继续或ctrl+c中止"
        read -s
        echo
    fi
}

check_important_dependence_installed()
{
    if dpkg -s $1 > /dev/null 2>&1; then
        apt-mark manual $1
    else
        if ! apt -y --no-install-recommends install $1; then
            apt update
            if ! apt -y --no-install-recommends install $1; then
                yellow "重要组件安装失败！！"
                exit 1
            fi
        fi
    fi
}

remove_other_kernel()
{
    yellow "卸载过程中如果弹出对话框，请选择NO！"
    yellow "卸载过程中如果弹出对话框，请选择NO！"
    yellow "卸载过程中如果弹出对话框，请选择NO！"
    tyblue "按回车键以继续。。"
    read -s
    local kernel_list_image=($(dpkg --list | awk '{print $2}' | grep '^linux-image'))
    local kernel_list_modules=($(dpkg --list | awk '{print $2}' | grep '^linux-modules'))
    local i
    local ok_install=0
    for ((i=${#kernel_list_image[@]}-1;i>=0;i--))
    do
        if [ "${kernel_list_image[$i]}" == "${install_image_list[0]}" ]; then
            unset kernel_list_image[$i]
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
                unset kernel_list_modules[$i]
                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ] ; then
            red "内核可能安装失败！不卸载"
            return 1
        fi
    fi
    if [ $install_headers -eq 1 ]; then
        local kernel_list_headers=($(dpkg --list | awk '{print $2}' | grep '^linux-headers'))
        ok_install=0
        for ((i=${#kernel_list_headers[@]}-1;i>=0;i--))
        do
            if [ "${kernel_list_headers[$i]}" == "${install_headers_list[0]}" ]; then
                unset kernel_list_headers[$i]
                ((ok_install++))
            fi
        done
        if [ "$ok_install" -lt "1" ] ; then
            red "内核可能安装失败！不卸载"
            return 1
        fi
        apt -y purge ${kernel_list_image[@]} ${kernel_list_modules[@]} ${kernel_list_headers[@]}
    else
        apt -y purge ${kernel_list_image[@]} ${kernel_list_modules[@]}
    fi
    [ $? -ne 0 ] && red "卸载失败！" && exit 1
    apt-mark manual "^grub"
}

main()
{
    menu
    check_mem
    check_important_dependence_installed gnupg1
    echo 'deb http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    wget -qO - https://dl.xanmod.org/gpg.key | apt-key --keyring /etc/apt/trusted.gpg.d/xanmod-kernel.gpg add -
    [ $? -ne 0 ] && red "添加源失败！" && exit 1
    apt update
    [ $? -ne 0 ] && red "更新源失败！" && exit 1
    local temp_list="$(apt show "$install" | grep -i "^Depends:" | cut -d : -f 2)"
    local temp
    local i
    for ((i=$(echo "$temp_list" | awk -F , '{print NF}');i>0;i--))
    do
        temp="$(echo "$temp_list" | awk -F , "{print \$$i}" | awk '{print $1}')"
        if [[ "$temp" =~ ^linux-headers-.*-xanmod ]]; then
            install_headers_list+=("$temp")
        elif [[ "$temp" =~ ^linux-image-.*-xanmod ]]; then
            install_image_list+=("$temp")
        elif [[ "$temp" =~ ^linux-modules-.*-xanmod ]]; then
            install_modules_list+=("$temp")
        fi
    done
    if [ ${#install_image_list[@]} -ne 1 ] || [ ${#install_modules_list[@]} -gt 1 ] || ([ $install_headers -eq 1 ] && [ ${#install_headers_list[@]} -ne 1 ]); then
        red "获取版本异常"
        exit 1
    fi
    if [ $install_headers -eq 0 ]; then
        apt -y --no-install-recommends install ${install_image_list[@]} ${install_modules_list[@]}
    else
        apt -y --no-install-recommends install ${install_image_list[@]} ${install_modules_list[@]} ${install_headers_list[@]}
    fi
    [ $? -ne 0 ] && red "安装失败！" && exit 1
    choice=""
    while [ "$choice" != "y" -a "$choice" != "n" ]
    do
        read -p "是否卸载其它内核？(y/n)" choice
    done
    [ $choice == y ] && remove_other_kernel
    green "安装完成"
    yellow "系统需要重启"
    choice=""
    while [[ "$choice" != "y" && "$choice" != "n" ]]
    do
        read -p "现在重启系统? [y/n]" choice
    done
    ([ $choice == y ] && reboot) || yellow "请尽快重启！"
}

main
