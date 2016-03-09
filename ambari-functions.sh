:<<USAGE
########################################
curl -Lo .amb http://bit.ly/21X03f1 && . .amb
########################################

full documentation: https://github.com/gerencio/docker-ambari
USAGE

: ${NODE_PREFIX=amb}
: ${AMBARI_SERVER_NAME:=${NODE_PREFIX}-server}
: ${IMAGE:="gerencio/docker-ambari:2.2.0-kylin"}
: ${KYLIN:=kylin}
: ${KYLIN_IMAGE:="gerencio/docker-ambari-kylin:2.2.0-kylin-1.2.0"}
: ${DOCKER_OPTS:=""}
: ${CONSUL:=${NODE_PREFIX}-consul}
: ${CONSUL_IMAGE:="gerencio/docker-consul:v0.5.0-v6"}
: ${CLUSTER_SIZE:=4}
: ${DEBUG:=1}
: ${SLEEP_TIME:=2}
: ${DNS_PORT:=53}
: ${EXPOSE_DNS:=true}
: ${MOUNT_POINT:="/home/core/dockerdata"}
: ${DRY_RUN:=false}

run-command() {
  CMD="$@"
  if [[ "$DRY_RUN" == "false" ]]; then
    debug "$CMD"
    "$@"
  else
    debug [DRY_RUN] "$CMD"
  fi
}

amb-clean-nodes() {
   for i in $(docker inspect --format="{{.Config.Image}} {{.Id}}" $(docker ps -q)|grep $IMAGE | awk '{print $2}'); do
      _consul-deregister-service ${NODE_PREFIX}${NUMBER} $(get-host-ip $i)
      docker stop $i
      docker rm $i
   done
}

amb-clean-kylin() {
  _consul-deregister-service $KYLIN $(get-kylin-ip)
  docker stop $KYLIN
  docker rm $KYLIN
}

amb-clean-consul(){
  _consul-deregister-service ${NODE_PREFIX}-consul $(get-consul-ip)
  docker stop $CONSUL
  docker rm $CONSUL

}


amb-clean-all() {
  amb-clean-nodes
  amb-clean-kylin
  amb-clean-consul
}

amb-unset-env() {
  unset NODE_PREFIX AMBARI_SERVER_NAME IMAGE DOCKER_OPTS CONSUL CONSUL_IMAGE DEBUG SLEEP_TIME AMBARI_SERVER_IP EXPOSE_DNS DRY_RUN
}

get-ambari-server-ip() {
  AMBARI_SERVER_IP=$(get-host-ip ${AMBARI_SERVER_NAME})
}

get-consul-ip() {
  get-host-ip $CONSUL
}

get-kylin-ip() {
  get-host-ip $KYLIN
}

get-host-ip() {
  HOST=$1
  docker inspect --format="{{.NetworkSettings.IPAddress}}" ${HOST}
}

get-host-ip() {
  HOST=$1
  docker inspect --format="{{.NetworkSettings.IPAddress}}" ${HOST}
}

amb-members() {
  curl http://$(get-consul-ip):8500/v1/catalog/nodes | sed -e 's/,{"Node":"ambari-8080.*}//g' -e 's/,{"Node":"consul.*}//g'
}

amb-settings() {
  cat <<EOF
  NODE_PREFIX=$NODE_PREFIX
  CLUSTER_SIZE=$CLUSTER_SIZE
  AMBARI_SERVER_NAME=$AMBARI_SERVER_NAME
  IMAGE=$IMAGE
  KYLIN_IMAGE=$KYLIN_IMAGE
  DOCKER_OPTS=$DOCKER_OPTS
  AMBARI_SERVER_IP=$AMBARI_SERVER_IP
  CONSUL=$CONSUL
  CONSUL_IMAGE=$CONSUL_IMAGE
  EXPOSE_DNS=$EXPOSE_DNS
  DRY_RUN=$DRY_RUN
  MOUNT_POINT=$MOUNT_POINT
EOF
}

debug() {
  [ ${DEBUG} -gt 0 ] && echo "[DEBUG] $@" 1>&2
}

docker-ps() {
  #docker ps|sed "s/ \{3,\}/#/g"|cut -d '#' -f 1,2,7|sed "s/#/\t/g"
  docker inspect --format="{{.Name}} {{.NetworkSettings.IPAddress}} {{.Config.Image}} {{.Config.Entrypoint}} {{.Config.Cmd}}" $(docker ps -q)
}

docker-psa() {
  #docker ps|sed "s/ \{3,\}/#/g"|cut -d '#' -f 1,2,7|sed "s/#/\t/g"
  docker inspect --format="{{.Name}} {{.NetworkSettings.IPAddress}} {{.Config.Image}} {{.Config.Entrypoint}} {{.Config.Cmd}}" $(docker ps -qa)
}

amb-start-cluster() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}
  echo starting an ambari cluster with: $act_cluster_size nodes

  amb-start-first
  [ $act_cluster_size -gt 1 ] && for i in $(seq $((act_cluster_size - 1))); do
    amb-start-node $i
  done
}


amb-start-cluster-kylin() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}
  echo starting an ambari cluster with: $act_cluster_size nodes

  amb-start-first
  [ $act_cluster_size -gt 2 ] && for i in $(seq $((act_cluster_size - 2))); do
    amb-start-node $i
  done

  #last node for kylin service
  if [ $act_cluster_size -gt 2 ]; then 
    amb-start-kylin $act_cluster_size -1
  fi
}



_amb_run_shell() {
  COMMAND=$1
  : ${COMMAND:? required}
  get-ambari-server-ip
  NODES=$(docker inspect --format="{{.Config.Image}} {{.Name}}" $(docker ps -q)|grep $IMAGE|grep $NODE_PREFIX|wc -l|xargs)
  run-command docker run -it --rm -e EXPECTED_HOST_COUNT=$((NODES-1)) -e BLUEPRINT=$BLUEPRINT --link ${AMBARI_SERVER_NAME}:ambariserver  --link ${KYLIN}:kylinserver --entrypoint /bin/sh $KYLIN_IMAGE -c $COMMAND
}

amb-shell() {
  _amb_run_shell /tmp/ambari-shell.sh
}




amb-deploy-cluster() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}

  if [[ $# -gt 1 ]]; then
    BLUEPRINT=$2
  else
    [ $act_cluster_size -gt 1 ] && BLUEPRINT=multi-node-hdfs-yarn || BLUEPRINT=single-node-hdfs-yarn
  fi

  : ${BLUEPRINT:?" required (single-node-hdfs-yarn / multi-node-hdfs-yarn / hdp-singlenode-default / hdp-multinode-default)"}

  amb-start-cluster $act_cluster_size
  _amb_run_shell /tmp/install-cluster.sh
}

amb-deploy-cluster-kylin() {
  local act_cluster_size=$1
  : ${act_cluster_size:=$CLUSTER_SIZE}

  if [[ $# -gt 1 ]]; then
    BLUEPRINT=$2
  else
    [ $act_cluster_size -gt 1 ] && BLUEPRINT=multi-node-hdfs-yarn || BLUEPRINT=single-node-hdfs-yarn
  fi

  : ${BLUEPRINT:?" required (single-node-hdfs-yarn / multi-node-hdfs-yarn / hdp-singlenode-default / hdp-multinode-default)"}

  amb-start-cluster-kylin $act_cluster_size
  _amb_run_shell /tmp/install-cluster.sh
}

amb-start-first() {
  local dns_port_command=""
  if [[ "$EXPOSE_DNS" == "true" ]]; then
     dns_port_command="-p 53:$DNS_PORT/udp"
  fi

  local mount_command=""
  if [[ "$MOUNT_POINT" == "" ]]; then
     mount_command="-v $MOUNT_POINT/$AMBARI_SERVER_NAME:/tmp"
  fi

  run-command docker run -d $dns_port_command --name $CONSUL -h $CONSUL.service.consul $CONSUL_IMAGE -server -bootstrap
  sleep 5

  run-command docker run  -d $mount_commandi -p 8080:8080  -e BRIDGE_IP=$(get-consul-ip) $DOCKER_OPTS --name $AMBARI_SERVER_NAME -h $AMBARI_SERVER_NAME.service.consul $IMAGE /start-server

  get-ambari-server-ip

  _consul-register-service $AMBARI_SERVER_NAME $AMBARI_SERVER_IP
  _consul-register-service ambari-8080 $AMBARI_SERVER_IP
}

amb-copy-to-hdfs() {
  get-ambari-server-ip
  FILE_PATH=${1:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  FILE_NAME=${2:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  DIR=${3:?"usage: <FILE_PATH> <NEW_FILE_NAME_ON_HDFS> <HDFS_PATH>"}
  amb-create-hdfs-dir $DIR
  DATANODE=$(curl -si -X PUT "http://$AMBARI_SERVER_IP:50070/webhdfs/v1$DIR/$FILE_NAME?user.name=hdfs&op=CREATE" |grep Location | sed "s/\..*//; s@.*http://@@")
  DATANODE_IP=$(get-host-ip $DATANODE)
  curl -T $FILE_PATH "http://$DATANODE_IP:50075/webhdfs/v1$DIR/$FILE_NAME?op=CREATE&user.name=hdfs&overwrite=true&namenoderpcaddress=$AMBARI_SERVER_IP:8020"
}

amb-create-hdfs-dir() {
  get-ambari-server-ip
  DIR=$1
  curl -X PUT "http://$AMBARI_SERVER_IP:50070/webhdfs/v1$DIR?user.name=hdfs&op=MKDIRS" > /dev/null 2>&1
}

amb-scp-to-first() {
  get-ambari-server-ip
  FILE_PATH=${1:?"usage: <FILE_PATH> <DESTINATION_PATH>"}
  DEST_PATH=${2:?"usage: <FILE_PATH> <DESTINATION_PATH>"}
  scp $FILE_PATH root@$AMBARI_SERVER_IP:$DEST_PATH
}

amb-start-node() {
  get-ambari-server-ip
  : ${AMBARI_SERVER_IP:?"AMBARI_SERVER_IP is needed"}
  NUMBER=${1:?"please give a <NUMBER> parameter it will be used as node<NUMBER>"}
  if [[ $# -eq 1 ]]; then
    MORE_OPTIONS="-d"
  else
    shift
    MORE_OPTIONS="$@"
  fi

  local mount_command=""
  if [[ "$MOUNT_POINT" != "" ]]; then
     mount_command="-v $MOUNT_POINT/${NODE_PREFIX}$NUMBER:/tmp"
  fi

  local mount_ports=""
  if [[ "${NODE_PREFIX}$NUMBER" == "amb1" ]]; then
     mount_ports=" -p 60020:60020 -p 60000:60000  -p 10000:10000 -p 8088:8088 -p 8042:8042 -p 60010:60010 -p 50070:50070 -p 8020:8020 -p 19888:19888  "
  fi


  run-command docker run $MORE_OPTIONS $mount_command $mount_ports  -e BRIDGE_IP=$(get-consul-ip) $DOCKER_OPTS --name ${NODE_PREFIX}$NUMBER -h ${NODE_PREFIX}${NUMBER}.service.consul $IMAGE /start-agent

  _consul-register-service ${NODE_PREFIX}${NUMBER} $(get-host-ip ${NODE_PREFIX}$NUMBER)
}


amb-remove-node() {
  get-ambari-server-ip
  : ${AMBARI_SERVER_IP:?"AMBARI_SERVER_IP is needed"}
  NUMBER=${1:?"please give a <NUMBER> parameter it will be used as node<NUMBER>"}
  if [[ $# -eq 1 ]]; then
    MORE_OPTIONS="-d"
  else
    shift
    MORE_OPTIONS="$@"
  fi

  

  run-command docker stop ${NODE_PREFIX}$NUMBER 
  run-command docker rm ${NODE_PREFIX}$NUMBER 

  _consul-deregister-service ${NODE_PREFIX}${NUMBER} $(get-host-ip ${NODE_PREFIX}$NUMBER)
}


amb-start-kylin() {
  get-ambari-server-ip
  : ${AMBARI_SERVER_IP:?"AMBARI_SERVER_IP is needed"}

  local mount_command=""
  if [[ "$MOUNT_POINT" != "" ]]; then
     mount_command="-v $MOUNT_POINT/${NODE_PREFIX}-kylin:/tmp"
  fi


  run-command docker run -d $mount_command -p 7070:7070  -e BRIDGE_IP=$(get-consul-ip) $DOCKER_OPTS --name $KYLIN -h $KYLIN.service.consul $KYLIN_IMAGE -c "/start-agent && /usr/local/serf/bin/start-serf-agent.sh"

  _consul-register-service $KYLIN $(get-kylin-ip)
}

_consul-register-service() {
  curl -X PUT -d "{
    \"Node\": \"$1\",
    \"Address\": \"$2\",
    \"Service\": {
      \"Service\": \"$1\"
    }
  }" http://$(get-consul-ip):8500/v1/catalog/register
}


_consul-deregister-service() {
  curl -X PUT -d "{
    \"Node\": \"$1\",
    \"Address\": \"$2\",
    \"Service\": {
      \"Service\": \"$1\"
    }
  }" http://$(get-consul-ip):8500/v1/catalog/deregister
}
