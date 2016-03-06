#!/bin/bash

./ambari-shell.sh << EOF
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/ambari-server/multi-node-hdfs-yarn.json
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/ambari-server/single-node-hdfs-yarn.json
cluster build --blueprint $BLUEPRINT
cluster autoAssign
cluster create --exitOnFinish true
EOF
