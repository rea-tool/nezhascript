#!/bin/bash

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="${NZ_AGENT_PATH}/nezha.sh"
NZ_VERSION="v0.10.6"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

os_arch=""

pre_check() {
    command -v systemctl >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi

    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
    elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
    elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
    elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi

    ## China_IP
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "是否选用中国镜像完成安装? [Y/n] " input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;

            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi

    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/naiba/nezha/master"
        GITHUB_URL="github.com"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" "
        Docker_IMG="ghcr.io\/naiba\/nezha-dashboard"
    else
        GITHUB_RAW_URL="jihulab.com/nezha/nezha/-/raw/master"
        GITHUB_URL="dn-dao-github-mirror.daocloud.io"
        Get_Docker_URL="get.daocloud.io/docker"
        Get_Docker_Argu=" -s docker --mirror Aliyun"
        Docker_IMG="registry.cn-shanghai.aliyuncs.com\/naibahq\/nezha-dashboard"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

show_usage() {
    echo "哪吒监控 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "  install             - 安装监控Agent"
    echo "  start               - 安装监控Agent"
    echo "  config              - 修改Agent配置"
    echo "  log                 - 查看Agent日志"
    echo "  uninstall           - 卸载Agent"
    echo "  restart             - 重启Agent"
    echo "--------------------------------------------------------"
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
        (install_soft curl wget git unzip)
}
selinux(){
    #判断当前的状态
    getenforce | grep '[Ee]nfor'
    if [ $? -eq 0 ];then
        echo -e "SELinux是开启状态，正在关闭！" 
        setenforce 0 &>/dev/null
        find_key="SELINUX="
        sed -ri "/^$find_key/c${find_key}disabled" /etc/selinux/config
    fi
}

install_agent() {
    install_base
    selinux

    echo -e "> 安装监控Agent"

    echo -e "正在获取监控Agent版本号"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/naiba/nezha/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://fastly.jsdelivr.net/gh/naiba/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
    fi
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://gcore.jsdelivr.net/gh/naiba/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
    fi

    if [ ! -n "$version" ]; then
        echo -e "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/naiba/nezha/releases/latest"
        return 0
    else
        echo -e "当前最新版本为: ${version}"
    fi

    # 哪吒监控文件夹
    mkdir -p $NZ_AGENT_PATH
    chmod 777 -R $NZ_AGENT_PATH

    if [ $# -ge 3 ]; then
        modify_agent_config "$@"
    else
        modify_agent_config 0
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_agent(){
    bash ${NZ_AGENT_SERVICE}|| echo "${red}请尝试再次启动${plain}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_agent_config() {
    echo -e "> 修改Agent配置"

    wget -t 2 -T 10 -O $NZ_AGENT_SERVICE https://raw.githubusercontent.com/rea-tool/nezhascript/main/nezha.sh >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi
    chmod +x ${NZ_AGENT_SERVICE}

    if [ $# -lt 3 ]; then
        echo "请先在管理面板上添加Agent，记录下密钥" &&
            read -ep "请输入一个解析到面板所在IP的域名（不可套CDN）: " nz_grpc_host &&
            read -ep "请输入面板RPC端口: (5555)" nz_grpc_port &&
            read -ep "请输入Agent 密钥: " nz_client_secret
        if [[ -z "${nz_grpc_host}" || -z "${nz_client_secret}" ]]; then
            echo -e "${red}所有选项都不能为空${plain}"
            before_show_menu
            return 1
        fi
        if [[ -z "${nz_grpc_port}" ]]; then
            nz_grpc_port=5555
        fi
    else
        nz_grpc_host=$1
        nz_grpc_port=$2
        nz_client_secret=$3
    fi

    sed -i "s/nz_grpc_host/${nz_grpc_host}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nz_grpc_port/${nz_grpc_port}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nz_client_secret/${nz_client_secret}/" ${NZ_AGENT_SERVICE}

    shift 3
    if [ $# -gt 0 ]; then
        args=" $*"
        sed -i "/ExecStart/ s/$/${args}/" ${NZ_AGENT_SERVICE}
    fi

    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"

    # systemctl daemon-reload
    # systemctl enable nezha-agent
    # systemctl restart nezha-agent
    start_agent

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}
uninstall_agent() {
    echo -e "> 卸载Agent"

    rm -rf $NZ_AGENT_SERVICE
    rm -rf $NZ_AGENT_PATH
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}


show_menu() {
    echo -e "
    ${green}哪吒监控管理脚本${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/naiba/nezha ---
    ————————————————-
    ${green}1.${plain}  安装监控Agent
    ${green}2.${plain}  启动Agent
    ${green}3.${plain}  修改Agent配置
    ${green}4.${plain}  卸载Agent
    ${green}5.${plain}  重启Agent
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-13]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        install_agent
        ;;
    2)
        start_agent
        ;;
    3)
        modify_agent_config
        ;;
    4)
        uninstall_agent
        ;;
    5)
        start_agent
        ;;
    *)
        echo -e "${red}请输入正确的数字 [0-13]${plain}"
        ;;
    esac
}

if [[ ! -f /usr/local/bin/nezha ]]; then
    cp wula.sh /usr/local/bin/nezha
    chmod +x /usr/local/bin/nezha
fi


if [[ $# > 0 ]]; then
    case $1 in
    "install")
        shift
        if [ $# -ge 3 ]; then
            install_agent "$@"
        else
            install_agent 0
        fi
        ;;
    "start")
        start_agent 0
        ;;
    "config")
        modify_agent_config 0
        ;;
    "uninstall")
        uninstall_agent 0
        ;;
    "restart")
        start_agent 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
