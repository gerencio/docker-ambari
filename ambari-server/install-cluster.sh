#!/bin/bash

./ambari-shell.sh << EOF
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/2.2.0-kylin/ambari-server/blueprints/multi-node-hdfs-yarn.json
blueprint add --url https://raw.githubusercontent.com/gerencio/docker-ambari/2.2.0-kylin/ambari-server/blueprints/single-node-hdfs-yarn.json
cluster build --blueprint $BLUEPRINT
cluster autoAssign
cluster create --exitOnFinish true
EOF
