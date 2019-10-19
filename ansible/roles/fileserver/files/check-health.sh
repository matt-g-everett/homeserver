#!/bin/bash

DATE_FORMAT='%Y-%m-%dT%H:%M:%S'
ONLINE_REPORT_FREQ='7 days'
FAILURE_REPORT_FREQ='1 day'
declare -A STATUSES=( [ONLINE]=0 [DEGRADED]=1 [OUTAGE]=3 )

scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
lastHealthFile='/var/run/zfs-health'
logFile='/var/log/zfs-health.log'

healthy=1
outage=0

log () {
    echo "[$(now)] ${1}" | tee -a ${logFile}
}

formatted_date () {
    echo $(date -d "${1}" +${DATE_FORMAT})
}

now () {
    echo $(date +${DATE_FORMAT})
}

send_email () {
    # Create a temporary file to hold the email
    report=$(mktemp)

    # Email headers
    echo "Subject: homeserver status: ${currentStatus}" >> ${report}
    if [[ ${important} == 1 ]]; then
        echo "Importance: high" >> ${report}
    fi
    echo -e "MIME-Version: 1.0\nContent-Type: text/html; charset=utf-8" >> ${report}

    # Email body
    echo -e "\n<html><head></head><body><pre style=\"font-family: monospace\">" >> ${report}
    for p in ${zpools[@]}; do
        zpool status -v ${p} >> ${report}
        echo "" >> ${report}
    done
    echo "</pre></body></html>" >> ${report}

    # Send the email
    cat ${report} | ssmtp matt.g.everett@gmail.com
    
    # Clean up the temporary file
    rm ${report}
}

# Create a default file if we don't already have one
if [[ ! -f ${lastHealthFile} ]]; then
    lastChecked=$(formatted_date '2 weeks ago')
    lastStatus=ONLINE
    lastSent=$(formatted_date '2 weeks ago')

    echo "${lastChecked} ${lastStatus} ${lastSent}" > ${lastHealthFile}
fi

# Read the last status
read lastChecked lastStatus lastSent < <(cat ${lastHealthFile})

zpools=(store data)
for p in ${zpools[@]}; do
    h=$(zpool list -H -o health ${p})
    if [[ ${h} != "ONLINE" ]]; then
        healthy=0
        if [[ ${h} != "DEGRADED" ]]; then
            outage=1
        fi
    fi
done

important=1
currentStatus=OUTAGE
if [[ ${healthy} == 1 && ${outage} == 0 ]]; then
    currentStatus=ONLINE
    important=0
elif [[ ${healthy} == 0 && ${outage} == 0 ]]; then
    currentStatus=DEGRADED
fi

# currentStatus=${1}

currentLevel=${STATUSES[${currentStatus}]}
lastLevel=${STATUSES[${lastStatus}]}
log "Current: ${currentStatus} (${currentLevel}) Last: ${lastStatus} (${lastLevel})"
if [[ ${currentLevel} != ${lastLevel} ]]; then
    log "Status changed, sending email..."
    send_email
    lastSent=$(now)
else
    if [[ ${currentStatus} == 'ONLINE' ]]; then
        restateOnlineThreshold=$(formatted_date "${lastSent} ${ONLINE_REPORT_FREQ}")
        if [[ $(now) > ${restateOnlineThreshold} ]]; then
            log "Sending routine report..."
            send_email
            lastSent=$(now)
        fi
    else
        restateFailureThreshold=$(formatted_date "${lastSent} ${FAILURE_REPORT_FREQ}")
        if [[ $(now) > ${restateFailureThreshold} ]]; then
            log "Sending problem report..."
            send_email
            lastSent=$(now)
        fi
    fi
fi

lastStatus=${currentStatus}
lastChecked=$(now)
echo "${lastChecked} ${lastStatus} ${lastSent}" > ${lastHealthFile}
