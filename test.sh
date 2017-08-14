#!/bin/bash

set -euo pipefail
set -x

#LOG_FILE=test.log
LOG_FILE=/dev/stdout

server_pid=
docker_socket_pid=

fake_docker_socket() {
    $(ncat -k -U -l /var/run/docker.sock --exec '/bin/cat'; rm /var/run/docker.sock) & > $LOG_FILE 2>&1
    docker_socket_pid="$!"
}

request() {
    local method="$1"
    local path="$2"
    headers="$(timeout -t 1 curl -s -D - -X "$method" "http://localhost:2375/$2" -o /dev/null)"

    # Not 403 and not from docker socket
    if [ "$(echo "$headers" | grep -c "403 Forbidden")" != "0" ] || [ "$(echo "$headers" | grep -c "User-Agent: curl")" != "1" ]; then
	return 1
    fi
}

start() {
    bash -c "/test-server.sh '$@'" &
    server_pid="$!"
    /wait-for-it.sh -t 1 localhost:2375 -q > $LOG_FILE 2>&1 
}

stop() {
    sleep 5s
    kill -f -9 "$server_pid" > /dev/null 2>&1 || true
    rm -f /var/run/docker.sock > /dev/null 2>&1 || true 
}

expect_success() {
    local label="$1"
    local method="$2"
    local path="$3"
    local pre_eval="${4:-}"

    echo -n "$label  "

    fake_docker_socket
    start "$pre_eval"

    err=0
    request "$method" "$path" || err=$? && true
    if [ "$err" != "0" ]; then
        echo "Fail"
        exit 22
    fi
    stop
    echo "Pass"
}

expect_failure() {
    local label="$1"
    local method="$2"
    local path="$3"
    local envs="${4:-}"

    echo -n "$label  "

    fake_docker_socket 
    start "$envs"

    err=0
    request "$method" "$path" && echo "Fail" && exit 44
    stop
    echo "Pass"
}

main() {
    sed -i "s/server-state-file.*$//" /usr/local/etc/haproxy/haproxy.cfg 
    sed -i "s/local0/local0 debug/" /usr/local/etc/haproxy/haproxy.cfg 
    expect_failure "swarm disabled " "GET" "v3/swarm"
    expect_success "swarm enabled  " "GET" "v3/events" "export EVENTS=1"
}

onExit() {
    exitCode=$?
    [ "$exitCode" != "0" ] && [ "$LOG_FILE" != "/dev/stdout" ] && cat $LOG_FILE
    stop 
    exit $exitCode
}

trap 'onExit' EXIT

main
