#!/bin/bash
version="1.0"

function usage {
    s=$(basename $0)
    echo ""
    echo "Crontab Extender v$version : a cli for extended crontab management."
    echo ""
    echo "Copyright (c) Bernard Nauwelaerts 2012 - GPL v4 Licenced"
    echo ""
    cat << ____END
 
      Usage:
        
        List xtabs          : $s -l
        Show xtab info      : $s -i id
        Execute xtab        : $s -x id [-f]
        Remove xtab         : $s -r id
        Clean expired xtabs : $s -c
        Add xtab            : $s -a 'command arg' [-y year] [-t 'exec_time'] [-n max_execs] [-e expiration_time] [-d]
        
      Options :
      
        -d : dryrun
        -f : force
      
      Notes :
      
        - exec_time is expected to be given in crontab format "mm hh dd MM w".
          defaults to the day of adding at 23:59
        - max_execs limits the numer of exectutions to the given value. Defaults to 0 (infinite)
        - year limits the executions to the given year. accepts lists and ranges like 2012-2015,2017.
          Defaults to * (every year)
        - expiration_time limits the executions to the time given in format YYYYMMDDhhmm
        
        - Expired xtabs are placed in ~/.xtab_history
        
____END
    exit 1
}
xtab=$0
id=""
command=""
time=""
numexec=0
dryrun=0
force=0
info=""
year="*"
expire="999999999999"

for arg in "$@"; do
    echo $arg | grep ' # ' && echo "Illegal character # in value" && exit 500;
    case $arg in
    -l)
        action="list"
        break;
        ;;
    -d)
        dryrun=1
        needs=""
        ;;
    -f)
        force=1
        needs=""
        ;;
    -i)
        action="info"
        needs="action";
        ;;
    -a)
        needs="action"
        action="add"
        ;;
    -r)
        needs="action"
        action="remove"
        ;;
    -c)
        needs=""
        action="clean"
        ;;
    -t)
        needs="property"
        property='time'
        ;;
    -n)
        needs="property"
        property="numexec"
        ;;
    -y)
        needs="property"
        property="year"
        ;;
    -e)
        needs="property"
        property="expire"
        ;;
    -x)
        needs="action"
        action="execute"
        ;;
    *)
        case $needs in
        action)
            case $action in
            info)
                id=$arg
            ;;
            add)
                if [[ "$command" != "" ]]; then
                    command=$command" "$arg
                else
                    command=$arg
                fi
            ;;
            remove)
                id=$arg
            ;;
            execute)
                id=$arg
            ;;
            esac
        ;;
        property)
            case $property in
            time)
                if [[ "$time" != "" ]]; then
                    time="$time"' '"$arg"
                else
                    time="$arg"
                fi
            ;;
            numexec)
                numexec="$arg"
            ;;
            year)
                year="$arg"
            ;;
            expire)
                expire="$arg"
            ;;
            esac
        ;;
        esac
    esac
done

function is_expired {
    tab="$1"
    y=$(echo "$tab" | awk -F ' # ' '{print $2}')
    l=$(echo "$tab" | awk -F ' # ' '{print $4}')
    e=$(echo "$tab" | awk -F ' # ' '{print $5}')
    n=$(echo "$l" | cut -d'-' -f1)
    m=$(echo "$l" | cut -d'-' -f2)
    c=$(date +%Y%m%d%H%M)
    u=$(date +%Y)
    if [[ $m=~^[0-9]+$ && $m -gt 0 && $n=~^[0-9]+$ && $n -ge $m ]]; then
        echo "Num runs Expired"
    elif [[ $y=~^[0-9]+$ && $(year "$y") -lt 0 ]]; then
        echo "Year Expired"
    elif [[ $e=~^[0-9]+$ && $c=~^[0-9]+$ && $c -gt $e ]]; then
        echo "Date Expired"
    fi
}

function clean {
    if [[ $dryrun -eq 1 ]]; then
        crontab -l | while read tab; do
            if [[ $(echo "$tab" | grep "$xtab -x ") == "" || $(is_expired "$tab") == "" ]]; then
                printf "Save\t%s\n" "$tab"
            else
                printf "Remove\t%s\n" "$tab"
            fi
        done;        
    else
        (
        crontab -l | while read tab; do
            if [[ $(echo "$tab" | grep "$xtab -x ") == "" || $(is_expired "$tab") == "" ]]; then
                echo "$tab"
            else
                echo "$tab" >> ~/.xtab_history
            fi
        done;
        ) | crontab -
    fi
}
function execute {
    id="$1"
    l=$(crontab -l | grep -v "$xtab -x $id")
    tab=$(crontab -l | grep "$xtab -x $id")
    n=$(echo "$tab" | awk -F ' # ' '{
        split($4, a, "-");
        cmd="date \"+%Y/%m/%d %H:%M:%S\""; cmd|getline date; close(cmd);
        printf "%s # %s # %s # %d-%d # %s # %s # -", $1, $2, $3, a[1]+1, a[2], $5, date
    }')
    e=$(is_expired "$tab")
    y=$(echo "$tab" | awk -F ' # ' '{print $2}')    
    c=$(echo "$tab" | awk -F ' # ' '{print $3}')
    if [[ "$y" == "*" || $force -eq 1 || $(year "$y") -gt 0 ]]; then
        if [[ $dryrun -eq 0 &&  $e == "" ]]; then
            echo "Executing $id $c"; eval "$c"
            e=$(is_expired "$n")
        fi
        if [[ $e == "" ]]; then
            if [[ $dryrun -eq 0 ]]; then
                printf "%s\n%s\n" "$l" "$n" | crontab -
            else
                echo "Would execute $c"
            fi
        elif [[ $dryrun -eq 0 ]]; then
            echo "$l" | crontab -
        else
            echo "$e $n"
        fi
    fi
}

function info {
    id="$1"
    echo "xtab ID     : $id"
    crontab -l | grep "$xtab -x $id" | awk -F ' # ' '{
        split($1, a, " ");        
        printf "Year        : %s\n", $2;
        printf "Day of week : %s\n", a[5];
        printf "Date        : %s/%s\n", a[3],a[4];
        printf "Time        : %s:%s\n", a[2], a[1];
        printf "Command     : %s\n", $3;
        printf "Execs-limit : %s\n", $4;
        printf "Expires     : %s\n", $5;
        printf "Last run    : %s\n", $6;     
    }'
}
function add {
    time=$1
    year=$2
    cmd=$3
    s=$(hash "$time" "$year" "$cmd")
    t=$(tab "$xtab"" -x ""$s" "$time")
    n="$t"" # $year # $cmd # 0-$numexec # $expire #  # -"
    l=$(crontab -l | grep -v "$xtab -x $s")
    if [[ $dryrun -eq 0 ]]; then
        printf "%s\n%s\n" "$l" "$n" | crontab -
    else
        printf "%s\n%s\n" "$l" "$n"
    fi
    echo $s
}
function remove {
    id="$1"
    l=$(crontab -l | grep -v "$xtab -x $id")
    if [[ $dryrun -eq 0 ]]; then
        printf "%s\n" "$l" | crontab -
    fi
    echo xtab "$id" removed.
}
function tab {
    cmd="$1"
    time="$2";
    echo "$time"'   '"$cmd"
}
function istabexists {
    id="$1"
    if [[ "$id" == "" ]]; then
        echo You have to specify an xtab ID >&2
        exit 404
    elif [[ $(crontab -l | grep "$xtab -x $id") == '' ]]; then
        echo xtab "$id" not found. >&2
        exit 404
    fi
}
function year {
    u=$(date +%Y)
    [[ "$1" == '*' ]] && echo 1 && exit
    echo $u,$1 | awk -F ',' '{
        u=$1;
        m=0
        r=0
        for(i=2; i<=NF; ++i) {
            split($i, y, "-");
            for(j=1; j<=2; ++j) {
                if (match(y[j], /^[0-9]+$/) && y[j] > m) {
                    m = y[j]
                }
            }
            if (match(y[2], /^[0-9]+$/) && y[2] >= u && match(y[1], /^[0-9]+$/) && y[1] <= u || !match(y[2], /^[0-9]+$/) && match(y[1], /^[0-9]+$/) && y[1] == u) {
                r = 1
            }
        }
        if ( m < u ) {
            r=-1
        }
        print r
    }'
}
function hash {
    time=$1
    year=$2
    cmd=$3
    echo $(echo "$time $year $cmd" | md5sum | cut -f1 -d' ')
}

case $action in
    list)
        crontab -l | grep "$xtab -x " | awk -F ' # ' '{
            split($1, a, " ");
            y=$2
            if (length(y) > 4) {
                y=substr(y, 0, 5)"~" 
            }
            printf "%s %s/%s\t%s:%s\t%s %s\t%s\t%s\n", a[8], a[3], a[4], a[2], a[1], a[5], y, $4, $3;
        }'
    ;;
    add)
        if [[ "$time" == "" ]]; then
            time="59 23	"$(date "+%d %m %u");
        fi
        add "$time" "$year" "$command"
    ;;
    remove)
        istabexists "$id"
        remove "$id"
    ;;
    info)
        istabexists "$id"
        info "$id"
    ;;
    execute)
        istabexists "$id"
        execute "$id"
    ;;
    clean)
        clean
    ;;
    *)
        usage
    ;;
esac
exit 0