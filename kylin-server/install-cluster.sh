#!/bin/bash

export PATH=/usr/jdk64/jdk1.7.0_67/bin:$PATH


./ambari-shell.sh << EOF
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/2.2.0-kylin/ambari-server/blueprints/multi-node-hdfs-yarn.json
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/2.2.0-kylin/ambari-server/blueprints/single-node-hdfs-yarn.json
cluster build --blueprint $BLUEPRINT
cluster autoAssign
cluster create --exitOnFinish true
EOF

clear

SERF_RPC_ADDR=${KYLINSERVER_PORT_7373_TCP##*/}
serf event --rpc-addr=$SERF_RPC_ADDR kylin

./wait-for-kylin.sh
