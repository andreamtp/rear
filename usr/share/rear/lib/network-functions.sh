# set of functions that will be used by our own implementation
# of dhclient-script, but these can/could be used by other
# scripts as well
#
# Most of the functions are coming from the fedora-14 dhclient-script

readonly -a MASKS=(
        0
        2147483648 3221225472 3758096384 4026531840
        4160749568 4227858432 4261412864 4278190080
        4286578688 4290772992 4292870144 4293918720
        4294443008 4294705152 4294836224 4294901760
        4294934528 4294950912 4294959104 4294963200
        4294965248 4294966272 4294966784 4294967040
        4294967168 4294967232 4294967264 4294967280
        4294967288 4294967292 4294967294 4294967295
        -1
)

exit_with_hooks() {
    exit_status="${1}"

    if [ -x ${ETCDIR}/dhclient-exit-hooks ]; then
        . ${ETCDIR}/dhclient-exit-hooks
    fi

    exit ${exit_status}
}

logmessage() {
    msg="${1}"
    logger -p ${LOGFACILITY}.${LOGLEVEL} -t "NET" "dhclient: ${msg}"
}

save_previous() {
    origfile="${1}"
    savefile="${SAVEDIR}/${origfile##*/}.predhclient.${interface}"

    if [ ! -d ${SAVEDIR} ]; then
        mkdir -p ${SAVEDIR}
    fi

    if [ -e ${origfile} ]; then
        contents="$(< ${origfile})"
        echo "${contents}" > ${savefile}
        rm -f ${origfile}
    else
        echo > ${savefile}
    fi

}

eventually_add_hostnames_domain_to_search() {
# For the case when hostname for this machine has a domain that is not in domain_search list
# 1) get the domain from this hostname
# 2) add this domain to search line in resolv.conf if it's not already
#    there (domain list that we have recently added there is a parameter of this function)
    search="${1}"
    domain=$(hostname 2>/dev/null | cut -s -d "." -f 2-)

    if [ -n "${domain}" ] &&
       [ ! "${domain}" = "localdomain" ] &&
       [ ! "${domain}" = "localdomain6" ] &&
       [ ! "${domain}" = "(none)" ] &&
       [[ ! "${domain}" = *\ * ]]; then
       is_in="false"
       for s in ${search}; do
           if [ "${s}" = "${domain}" ] ||
              [ "${s}" = "${domain}." ]; then
              is_in="true"
           fi
       done

       if [ "${is_in}" = "false" ]; then
          # Add domain name to search list (#637763)
          sed -i -e "s/${search}/${search} ${domain}/" /etc/resolv.conf
       fi
    fi
}

make_resolv_conf() {

    if [ "${reason}" = "RENEW" ] &&
       [ "${new_domain_name}" = "${old_domain_name}" ] &&
       [ "${new_domain_name_servers}" = "${old_domain_name_servers}" ]; then
        return
    fi

    if [ -n "${new_domain_name}" ] ||
       [ -n "${new_domain_name_servers}" ] ||
       [ -n "${new_domain_search}" ]; then
        save_previous /etc/resolv.conf
        rscf="$(mktemp /tmp/XXXXXX)"
        echo "; generated by /bin/dhclient-script" > ${rscf}

        if [ -n "${SEARCH}" ]; then
            search="${SEARCH}"
        else
            if [ -n "${new_domain_search}" ]; then
                # Remove instaces of \032 (#450042)
                search="${new_domain_search//\\032/ }"
            elif [ -n "${new_domain_name}" ]; then
                # Note that the DHCP 'Domain Name Option' is really just a domain
                # name, and that this practice of using the domain name option as
                # a search path is both nonstandard and deprecated.
                search="${new_domain_name}"
            fi
        fi

        if [ -n "${search}" ]; then
            echo "search ${search}" >> $rscf
        fi

        if [ -n "${RES_OPTIONS}" ]; then
            echo "options ${RES_OPTIONS}" >> ${rscf}
        fi

        for nameserver in ${new_domain_name_servers} ; do
            echo "nameserver ${nameserver}" >> ${rscf}
        done

        change_resolv_conf ${rscf}
        rm -f ${rscf}

        if [ -n "${search}" ]; then
            eventually_add_hostnames_domain_to_search "${search}"
        fi

    elif [ -n "${new_dhcp6_name_servers}" ] ||
         [ -n "${new_dhcp6_domain_search}" ]; then
        save_previous /etc/resolv.conf
        rscf="$(mktemp /tmp/XXXXXX)"
        echo "; generated by /bin/dhclient-script" > ${rscf}

        if [ -n "${SEARCH}" ]; then
            search="${SEARCH}"
        else
            if [ -n "${new_dhcp6_domain_search}" ]; then
                search="${new_dhcp6_domain_search//\\032/ }"
            fi
        fi

        if [ -n "${search}" ]; then
            echo "search ${search}" >> $rscf
        fi

        if [ -n "${RES_OPTIONS}" ]; then
            echo "options ${RES_OPTIONS}" >> ${rscf}
        fi

        for nameserver in ${new_dhcp6_name_servers} ; do
            echo "nameserver ${nameserver}" >> ${rscf}
        done

        change_resolv_conf ${rscf}
        rm -f $v ${rscf} >&2

        if [ -n "${search}" ]; then
            eventually_add_hostnames_domain_to_search "${search}"
        fi

    fi
}

# Invoke this when /etc/resolv.conf has changed:
change_resolv_conf ()
{
    s=$(/bin/grep '^[\ \	]*option' /etc/resolv.conf 2>/dev/null);
    if [ "x$s" != "x" ]; then
       s="$s"$'\n';
    fi;
    if [ $# -gt 1 ]; then
       n_args=$#;
       while [ $n_args -gt 0 ];
         do
            case "$s" in *$1*)
               shift;
               n_args=$(($n_args-1));
               continue;;
            esac;
            s="$s$1";
            shift;
            if [ $# -gt 0 ]; then
                s="$s"$'\n';
            fi;
            n_args=$(($n_args-1));
         done;
    elif [ $# -eq 1 ]; then
       if [ "x$s" != "x" ]; then
          s="$s"$(/bin/grep -vF "$s" $1);
       else
          s=$(cat $1);
       fi;
    fi;
    (echo "$s" > /etc/resolv.conf;) &>/dev/null;
    r=$?
    if [ $r -eq 0 ]; then
        logger -p local7.notice -t "$PROGRAM" -i "updated /etc/resolv.conf";
    fi;
    return $r;
}

my_ipcalc() {
    declare -i BITS ADDRESS="$(ip2num "$1")"

    if [[ "$2" ]]; then
        declare -i DEC MASK="$(ip2num "$2")"
        for BITS in ${!MASKS[@]}; do
                DEC=${MASKS[$BITS]}
                (( MASK == DEC )) && break
        done
        (( DEC < 0 )) && Error "Main: netmask [$2] seems to be invalid."
        NETADDR=$(num2ip "$(( ADDRESS & MASK ))")
    else
        NETADDR=$(num2ip "$ADDRESS")
        BITS=32
    fi
    echo "$NETADDR/$BITS"
}

quad2num() {
    if [ $# -eq 4 ]; then
        let n="${1} << 24 | ${2} << 16 | ${3} << 8 | ${4}"
        echo "${n}"
        return 0
    else
        echo "0"
        return 1
    fi
}

ip2num() {
	IFS="."
	quad2num ${1}
}

num2ip() {
    let n="${1}"
    let o1="(n >> 24) & 0xff"
    let o2="(n >> 16) & 0xff"
    let o3="(n >> 8) & 0xff"
    let o4="n & 0xff"
    echo "${o1}.${o2}.${o3}.${o4}"
}

get_network_address() {
# get network address for the given IP address and (netmask or prefix)
    ip="${1}"
    nm="${2}"

    if [ -n "${ip}" -a -n "${nm}" ]; then
        if [[ "${nm}" = *.* ]]; then
            :
        else
            nm=`prefix2netmask ${nm}`
        fi
        my_ipcalc ${ip} ${nm} | cut -d '/' -f 2
    fi
}

prefix2netmask() {
    pf="${1}"
    echo $(num2ip "${MASKS[$pf]}")
}

get_prefix() {
# get prefix for the given IP address and mask
    ip="${1}"
    nm="${2}"

    if [ -n "${ip}" -a -n "${nm}" ]; then
        my_ipcalc ${ip} ${nm} | cut -d '/' -f 2
    fi
}

class_bits() {
    let ip=$(IFS='.' ip2num $1)
    let bits=32
    let mask='255'
    for ((i=0; i <= 3; i++, 'mask<<=8')); do
        let v='ip&mask'
        if [ "$v" -eq 0 ] ; then
             let bits-=8
        else
             break
        fi
    done
    echo $bits
}

is_router_reachable() {
    # handle DHCP servers that give us a router not on our subnet
    router="${1}"
    routersubnet="$(get_network_address ${router} ${new_subnet_mask})"
    mysubnet="$(get_network_address ${new_ip_address} ${new_subnet_mask})"

    if [ ! "${routersubnet}" = "${mysubnet}" ]; then
        ip -4 route add ${router}/32 dev ${interface}
        if [ $? -eq 0 ]; then
            if ping -q -c1 -w2 -I ${interface} ${router}; then
                return 0
            else
                logmessage "DHCP router ${router} is unreachable on DHCP subnet ${mysubnet} router subnet ${routersubnet}"
                ip route del ${router}/32 dev ${interface}
                return 1
            fi
        else
            logmessage "failed to create host router for unreachable router ${router} not on subnet ${mysubnet}"
            return 1
        fi
    fi

    return 0
}

add_default_gateway() {
    router="${1}"
    metric=""

    if [ $# -gt 1 ] && [ ${2} -gt 0 ]; then
        metric="metric ${2}"
    fi

    if is_router_reachable ${router} ; then
        ip -4 route replace default via ${router} dev ${interface} ${metric}
        if [ $? -ne 0 ]; then
            logmessage "failed to create default route: ${router} dev ${interface} ${metric}"
            return 1
        else
            return 0
        fi
    fi

    return 1
}

flush_dev() {
# Instead of bringing the interface down (#574568)
# explicitly clear the ARP cache and flush all addresses & routes.
    ip -4 addr flush dev ${1} &>/dev/null
    ip -4 route flush dev ${1} &>/dev/null
    ip -4 neigh flush dev ${1} &>/dev/null
}

dhconfig() {
    if [ -n "${old_ip_address}" ] && [ -n "${alias_ip_address}" ] &&
       [ ! "${alias_ip_address}" = "${old_ip_address}" ]; then
        # possible new alias, remove old alias first
        ip -4 addr del ${old_ip_address} dev ${interface}:0
    fi

    if [ -n "${old_ip_address}" ] &&
       [ ! "${old_ip_address}" = "${new_ip_address}" ]; then
        # IP address changed. Delete all routes, and clear the ARP cache.
        flush_dev ${interface}
    fi

    if [ "${reason}" = "BOUND" ] || [ "${reason}" = "REBOOT" ] ||
       [ ! "${old_ip_address}" = "${new_ip_address}" ] ||
       [ ! "${old_subnet_mask}" = "${new_subnet_mask}" ] ||
       [ ! "${old_network_number}" = "${new_network_number}" ] ||
       [ ! "${old_broadcast_address}" = "${new_broadcast_address}" ] ||
       [ ! "${old_routers}" = "${new_routers}" ] ||
       [ ! "${old_interface_mtu}" = "${new_interface_mtu}" ]; then
        ip -4 addr add ${new_ip_address}/${new_prefix} broadcast ${new_broadcast_address} dev ${interface}
        ip link set dev ${interface} up

        # The 576 MTU is only used for X.25 and dialup connections
        # where the admin wants low latency.  Such a low MTU can cause
        # problems with UDP traffic, among other things.  As such,
        # disallow MTUs from 576 and below by default, so that broken
        # MTUs are ignored, but higher stuff is allowed (1492, 1500, etc).
        if [ -n "${new_interface_mtu}" ] && [ ${new_interface_mtu} -gt 576 ]; then
            ip link set ${interface} mtu ${new_interface_mtu}
        fi

        if [ -x ${ETCDIR}/dhclient-${interface}-up-hooks ]; then
            . ${ETCDIR}/dhclient-${interface}-up-hooks
        elif [ -x ${ETCDIR}/dhclient-up-hooks ]; then
            . ${ETCDIR}/dhclient-up-hooks
        fi

        # static routes
        if [ -n "${new_classless_static_routes}" ] ||
           [ -n "${new_static_routes}" ]; then
            if [ -n "${new_classless_static_routes}" ]; then
                IFS=', |' static_routes=(${new_classless_static_routes})
            else
                IFS=', |' static_routes=(${new_static_routes})
            fi
            route_targets=()

            for((i=0; i<${#static_routes[@]}; i+=2)); do
                target=${static_routes[$i]}
                if [ -n "${new_classless_static_routes}" ]; then
                    if [ ${target} = "0" ]; then
                        # If the DHCP server returns both a Classless Static Routes option and
                        # a Router option, the DHCP client MUST ignore the Router option. (RFC3442)
                        new_routers=""
                        prefix="0"
                    else
                        prefix=$(echo ${target} | cut -d "." -f 1)
                        target=$(echo ${target} | cut -d "." -f 2-)
                        IFS="." target_arr=(${target})
                        unset IFS
                        ((pads=4-${#target_arr[@]}))
                        for j in $(seq $pads); do
                            target=${target}".0"
                        done

                        # Client MUST zero any bits in the subnet number where the corresponding bit in the mask is zero.
                        # In other words, the subnet number installed in the routing table is the logical AND of
                        # the subnet number and subnet mask given in the Classless Static Routes option. (RFC3442)
                        target="$(get_network_address ${target} ${prefix})"
                    fi
                else
                    prefix=$(class_bits ${target})
                fi
                gateway=${static_routes[$i+1]}

                metric=''
                for t in ${route_targets[@]}; do
                    if [ ${t} = ${target} ]; then
                        if [ -z "${metric}" ]; then
                            metric=1
                        else
                            ((metric=metric+1))
                        fi
                    fi
                done

                if [ -n "${metric}" ]; then
                    metric="metric ${metric}"
                fi

                if is_router_reachable ${gateway}; then
                    ip -4 route replace ${target}/${prefix} proto static via ${gateway} dev ${interface} ${metric}

                    if [ $? -ne 0 ]; then
                        logmessage "failed to create static route: ${target}/${prefix} via ${gateway} dev ${interface} ${metric}"
                    else
                        route_targets=(${route_targets[@]} ${target})
                    fi
                fi
            done
        fi

        # gateways
        if [[ ( "${DEFROUTE}" != "no") &&
              (( -z "${GATEWAYDEV}" ) ||
               ( "${GATEWAYDEV}" = "${interface}" )) ]]; then
            if [[ ( -z "$GATEWAY" ) ||
                  (( -n "$DHCLIENT_IGNORE_GATEWAY" ) &&
                   ( "$DHCLIENT_IGNORE_GATEWAY" = [Yy]* )) ]]; then
                metric="${METRIC:-}"
                let i="${METRIC:-0}"
                default_routers=()

                for router in ${new_routers} ; do
                    added_router=-

                    for r in ${default_routers[@]} ; do
                        if [ "${r}" = "${router}" ]; then
                            added_router=1
                        fi
                    done

                    if [ -z "${router}" ] ||
                       [ "${added_router}" = "1" ] ||
                       [ $(IFS=. ip2num ${router}) -le 0 ] ||
                       [[ ( "${router}" = "${new_broadcast_address}" ) &&
                          ( "${new_subnet_mask}" != "255.255.255.255" ) ]]; then
                        continue
                    fi

                    default_routers=(${default_routers[@]} ${router})
                    add_default_gateway ${router} ${metric}
                    let i=i+1
                    metric=${i}
                done
            elif [ -n "${GATEWAY}" ]; then
                routersubnet=$(get_network_address ${GATEWAY} ${new_subnet_mask})
                mysubnet=$(get_network_address ${new_ip_address} ${new_subnet_mask})

                if [ "${routersubnet}" = "${mysubnet}" ]; then
                    ip -4 route replace default via ${GATEWAY} dev ${interface}
                fi
            fi
        fi

    fi

    if [ ! "${new_ip_address}" = "${alias_ip_address}" ] &&
       [ -n "${alias_ip_address}" ]; then
        ip -4 addr flush dev ${interface}:0 &>/dev/null
        ip -4 addr add ${alias_ip_address}/${alias_prefix} dev ${interface}:0
        ip -4 route replace ${alias_ip_address}/32 dev ${interface}:0
    fi

    make_resolv_conf

    if [ -n "${new_host_name}" ] && need_hostname; then
        hostname ${new_host_name} || echo "See -nc option in dhclient(8) man page."
    fi

    if [ -n "${DHCP_TIME_OFFSET_SETS_TIMEZONE}" ] &&
       [[ "${DHCP_TIME_OFFSET_SETS_TIMEZONE}" = [yY1]* ]]; then
        if [ -n "${new_time_offset}" ]; then
            # DHCP option "time-offset" is requested by default and should be
            # handled.  The geographical zone abbreviation cannot be determined
            # from the GMT offset, but the $ZONEINFO/Etc/GMT$offset file can be
            # used - note: this disables DST.
            ((z=new_time_offset/3600))
            ((hoursWest=$(printf '%+d' $z)))

            if (( $hoursWest < 0 )); then
                # tzdata treats negative 'hours west' as positive 'gmtoff'!
                ((hoursWest*=-1))
            fi

            tzfile=/usr/share/zoneinfo/Etc/GMT$(printf '%+d' ${hoursWest})
            if [ -e ${tzfile} ]; then
                #save_previous /etc/localtime
                cp -fp ${tzfile} /etc/localtime
                touch /etc/localtime
            fi
        fi
    fi

}

# Section 18.1.8. (Receipt of Reply Messages) of RFC 3315 says:
# The client SHOULD perform duplicate address detection on each of
# the addresses in any IAs it receives in the Reply message before
# using that address for traffic.
add_ipv6_addr_with_DAD() {
            ip -6 addr add ${new_ip6_address}/${new_ip6_prefixlen} \
                dev ${interface} scope global

            # repeatedly test whether newly added address passed
            # duplicate address detection (DAD)
            for i in $(seq 5); do
                sleep 1 # give the DAD some time

                # tentative flag = DAD is still not complete or failed
                duplicate=$(ip -6 addr show dev ${interface} tentative \
                              | grep ${new_ip6_address}/${new_ip6_prefixlen})

                # if there's no tentative flag, address passed DAD
                if [ -z "${duplicate}" ]; then
                    break
                fi
            done

            # if there's still tentative flag = address didn't pass DAD =
            # = it's duplicate = remove it
            if [ -n "${duplicate}" ]; then
                ip -6 addr del ${new_ip6_address}/${new_ip6_prefixlen} dev ${interface}
                exit_with_hooks 3
            fi
}

dh6config() {
    case "${reason}" in
        BOUND6)
            if [ -z "${new_ip6_address}" ] ||
               [ -z "${new_ip6_prefixlen}" ]; then
                exit_with_hooks 2
            fi

            add_ipv6_addr_with_DAD

            make_resolv_conf
            ;;

        RENEW6|REBIND6)
            if [ -z "${new_ip6_address}" ] ||
               [ -z "${new_ip6_prefixlen}" ]; then
                exit_with_hooks 2
            fi

            if [  ! "${new_ip6_address}" = "${old_ip6_address}" ]; then
                add_ipv6_addr_with_DAD
            fi

            if [ ! "${new_dhcp6_name_servers}" = "${old_dhcp6_name_servers}" ] ||
               [ ! "${new_dhcp6_domain_search}" = "${old_dhcp6_domain_search}" ]; then
                make_resolv_conf
            fi
            ;;

        DEPREF6)
            if [ -z "${new_ip6_prefixlen}" ]; then
                exit_with_hooks 2
            fi

            ip -6 addr change ${new_ip6_address}/${new_ip6_prefixlen} \
                dev ${interface} scope global preferred_lft 0
            ;;
    esac

}

get_hwaddr ()
{
    if [ -f /sys/class/net/${1}/address ]; then
        awk '{ print toupper($0) }' < /sys/class/net/${1}/address
    elif [ -d "/sys/class/net/${1}" ]; then
        LC_ALL= LANG= ip -o link show ${1} 2>/dev/null | \
            awk '{ print toupper(gensub(/.*link\/[^ ]* ([[:alnum:]:]*).*/,
                                        "\\1", 1)); }'
    fi
}

get_device_by_hwaddr ()
{
    LANG=C ip -o link | grep -v link/ieee802.11 | grep -i "$1" | awk -F ": " '{print $2}'
}

need_hostname ()
{
    CHECK_HOSTNAME=$(hostname)
    if [ "$CHECK_HOSTNAME" = "(none)" -o "$CHECK_HOSTNAME" = "localhost" -o \
        "$CHECK_HOSTNAME" = "localhost.localdomain" ]; then
        return 0
    else
        return 1
    fi
}

set_hostname ()
{
    hostname $1
    if ! grep -q search /etc/resolv.conf; then
        domain=$(echo $1 | sed 's/^[^\.]*\.//')
        if [ -n "$domain" ]; then
                rsctmp=$(mktemp /tmp/XXXXXX);
                cat /etc/resolv.conf > $rsctmp
                echo "search $domain" >> $rsctmp
                change_resolv_conf $rsctmp
                /bin/rm -f $rsctmp
        fi
    fi
}

check_device_down ()
{
     if LC_ALL=C ip -o link show dev $1 2>/dev/null | grep -q ",UP" ; then
        return 1
     else
        return 0
     fi
}

check_link_down ()
{
        if ! LC_ALL=C ip link show dev $1 2>/dev/null | grep -q ",UP" ; then
           ip link set dev $1 up &>/dev/null
        fi
        timeout=0
        delay=10
        [ -n "$LINKDELAY" ] && delay=$(($LINKDELAY * 2))
        while [ $timeout -le $delay ]; do
            [ "$(cat /sys/class/net/$REALDEVICE/carrier 2>/dev/null)" != "0" ] && return 1
            usleep 500000
            timeout=$((timeout+1))
        done
        return 0
}

check_default_route ()
{
    LC_ALL=C ip route list match 0.0.0.0/0 | grep -q default
}

find_gateway_dev ()
{
    if [ -n "${GATEWAY}" -a "${GATEWAY}" != "none" ] ; then
        dev=$(LC_ALL=C /bin/ip route get to "${GATEWAY}" 2>/dev/null | \
            sed -n 's/.* dev \([[:alnum:]]*\) .*/\1/p')
        if [ -n "$dev" ]; then
            GATEWAYDEV="$dev"
        fi
    fi
}

add_default_route ()
{
    check_default_route && return 0
    find_gateway_dev
    if [ "$GATEWAYDEV" != "" -a -n "${GATEWAY}" -a \
                "${GATEWAY}" != "none" ]; then
        if ! check_device_down $1; then
            if [ "$GATEWAY" = "0.0.0.0" ]; then
                /bin/ip route add default dev ${GATEWAYDEV}
            else
                /bin/ip route add default via ${GATEWAY}
            fi
        fi
    elif [ -f /etc/default-routes ]; then
        while read spec; do
            /bin/ip route add $spec
        done < /etc/default-routes
        rm -f /etc/default-routes
    fi
}

is_wireless_device ()
{
    [ -d "/sys/class/net/$1/wireless" ]
}

install_bonding_driver ()
{
   [ -d "/sys/class/net/$1" ] && return 0
   [ ! -f /sys/class/net/bonding_masters ] && ( modprobe bonding || return 1 )
   echo "+$1" > /sys/class/net/bonding_masters 2>/dev/null
   return 0
}

is_bonding_device ()
{
   [ -f "/sys/class/net/$1/bonding/slaves" ]
}


function get_ip4_from_fqdn()
{
    local fqdn=$1
    [ -z $fqdn ] && BugError "function get_ip_from_name() called without argument."

    local ip4_address=$(getent ahostsv4 $fqdn | awk '$1~/^[0-9][0-9]?[0-9]?\.[0-9]?[0-9]?[0-9]\.[0-9]?[0-9]?[0-9]\.[0-9]?[0-9]?[0-9]$/ && NR==1 { print $1 }' )
    #^((1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$

    echo "$ip4_address"
}
