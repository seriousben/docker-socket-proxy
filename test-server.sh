#!/bin/bash

pre_eval="${1:-}"

eval "$pre_eval"
env
/bin/sh -c "/sbin/syslogd -O /dev/stdout && haproxy -f /usr/local/etc/haproxy/haproxy.cfg"
