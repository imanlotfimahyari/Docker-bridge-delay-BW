#! /usr/bin/env bash


# Cleaning the test structure
function cleanUp() {
  # Number of test containers
  OLD_C=0
  cmd="docker ps --format {{.ID}}:{{.Names}}"
  for i in $($cmd); do
    container_name=$(docker ps --format {{.ID}}:{{.Names}}|grep $i|cut -d ":" -f 2)
    if [[ "${container_name:0:6}" == "client" ]] ; then
      OLD_C=$(($OLD_C+1))
    fi
  done

  # Stopping and removing already existing containers and the bridge
  for i in $(seq 1 $OLD_C);do
    echo "Stop: $(sudo docker container stop client$i)"
    echo "remove: $(sudo docker container rm client$i)"
  done
  for i in $(docker network ls); do
    if [[ "$i" == "myTestBridge" ]]; then
      echo "Removing the bridge: $(sudo docker network rm myTestBridge)"
    fi
  done

  # Delete previous files
  rm docker-compose.yml containers_update.log container_bridge_info.txt
}


# Generating test structure
function testNet() {

  # Generating the docker-composer file
  echo -e "version: '3.7'" >> docker-compose.yml
  echo -e "   " >> docker-compose.yml
  echo -e "networks:" >> docker-compose.yml
  echo -e "  testNet:" >> docker-compose.yml
  echo -e "    name: myTestBridge" >> docker-compose.yml
  echo -e "    driver: bridge" >> docker-compose.yml
  echo -e "   " >> docker-compose.yml
  echo -e "services:" >> docker-compose.yml
  for i in $(seq 1 $NEW_C);do
    echo -e "  client${i}:" >> docker-compose.yml
    echo -e "    container_name: client${i}" >> docker-compose.yml
    echo -e "    build: ./client" >> docker-compose.yml
    echo -e "    tty: true" >> docker-compose.yml
    echo -e "    networks:" >> docker-compose.yml
    echo -e "      - testNet" >> docker-compose.yml
    echo -e "    cap_add:" >> docker-compose.yml
    echo -e "      - NET_ADMIN" >> docker-compose.yml
    echo -e "   " >> docker-compose.yml
  done

  # Creating containers and the bridge
  sudo docker-compose up -d
  BR_NAME="myTestBridge"
}


# Getting bridge and the containers info
function netInfo() {

  ## Getting the container names and interface data
  INTF="eth0"
  CONTAINER_NAMES=""
  CONTAINER_IPS=""
  CONTAINER_VETH_IN_BRIDGES=""

  for i in $(docker network inspect $BR_NAME | grep \"Name\" |grep -v \"$BR_NAME\"|cut -d ":" -f 2|cut -d "\"" -f 2); do
    container_name=$i

    # Not the best way but currently to make sure that iproute2 package is installed in the docker containers
    ERRR=$(docker exec -it $container_name ip)
    if [[ "${ERRR:0:3}" == "OCI" ]]; then
      echo "$container_name log:" >> containers_update.log
      docker exec -it $container_name apt-get update >> containers_update.log 2>&1
      docker exec -it $container_name apt-get install -y iproute2 >> containers_update.log 2>&1
    fi

    container_IP=$(docker network inspect $BR_NAME|grep -A3 \"${container_name}\"|grep "IP"|sed "s/ //g"|cut -d "," -f 1|cut -d ":" -f 2)
    veth_in_container=$(sudo docker exec $container_name ip a|grep ${INTF}@|cut -d ':' -f 1)
    veth_in_bridge=$(sudo ip a|grep "if${veth_in_container}"|cut -d ":" -f 2|cut -d '@' -f 1|sed "s/ //g")
    echo -e "${container_name} ${container_IP} ${veth_in_bridge}" >> container_bridge_info.txt
    echo "$container_name $container_IP $veth_in_bridge"
    CONTAINER_NAMES="$CONTAINER_NAMES $container_name"
    CONTAINER_IPS="$CONTAINER_IPS $container_IP"
    CONTAINER_VETH_IN_BRIDGES="$CONTAINER_VETH_IN_BRIDGES $veth_in_bridge"
  done
}

function modify() {

  ## STRUCTURE for cbq and htb

  #       f ->            1:0            root handle 1: cbq|htb "qdisc"
  #       i |              |
  #       l |             1:1            classid 1:1 cbq|htb "class"
  #       t |            /   \
  #       e |           /     \
  #       r ->       1:2      1:3   ...  leaf classes
  #                   |        |
  #                  20:       30:  ...  leaf qdiscs
  #               (netem     (netem
  #               delay)     delay)

  ## Running the delay and BW modification
  COUNT_VETH=0
  IFS=' ' read -ra VETHS <<< "$CONTAINER_VETH_IN_BRIDGES" # array of Veths
  echo ""
  echo "***********************"
  echo "*** s t a r t i n g ***"
  echo "***********************"
  echo ""
  for veth in "${VETHS[@]}" ; do # for each Veth
    DST_NAME=""
    COUNT_VETH=$(($COUNT_VETH+1))
    COUNT_SRC_NAME=0
    echo ">>>>>>>>>>>>>>>>>>>>>"
    echo "VETH : $veth "
    IFS=' ' read -ra NAMES <<< "$CONTAINER_NAMES" # array of container names
    for name in "${NAMES[@]}" ; do # loop on names
      COUNT_SRC_NAME=$(($COUNT_SRC_NAME+1))
      # if it is the name of the container that is connected to this Veth
      if [[ $COUNT_SRC_NAME -eq $COUNT_VETH ]] ; then
        DST_NAME=$name
        # Receive total BW towards this container
        echo "BW   : $name? (EX: 100Mbit)"
        read BW0
        break
      fi
    done
    echo ">>>>>>>>>>>>>>>>>>>>>"

    # add root qdisc and root class
    if [[ "$TEST_CLASS" == "cbq" ]]; then
      sudo tc qdisc replace dev $veth root handle 1:0 cbq bandwidth $BW0 avpkt 1000 ##(2)
      sudo tc class add dev $veth parent 1:0 classid 1:1 cbq bandwidth $BW0 rate $BW0 allot 1514 avpkt 1000 ##(3)
    elif [[ "$TEST_CLASS" == "htb" ]]; then
      sudo tc qdisc replace dev $veth root handle 1:0 htb ##(2)
      sudo tc class add dev $veth parent 1:0 classid 1:1 htb rate $BW0 ceil $BW0 ##(3)
    fi

    COUNT_SRC_NAME=0
    IFS=' ' read -ra NAMES1 <<< "$CONTAINER_NAMES" # array of container names
    TMP_ID=1
    for name in "${NAMES1[@]}" ; do
      COUNT_SRC_NAME=$(($COUNT_SRC_NAME+1))
      if [[ "$name" == "$DST_NAME" ]] ; then
        continue
      fi
      # Receive from one container BW towards this container
      echo "BW   : $name --> $DST_NAME? (EX: 10Mbit)"
      read BW1
      # Receive delay towards this container
      echo "Delay: $name --> $DST_NAME? (EX: 100ms)"
      read DELAY
      COUNT_SRC_IP=0

      TMP_CONTAINER_IPS=$CONTAINER_IPS
      IFS=' ' read -ra IPS <<< "$TMP_CONTAINER_IPS" # array of container IPs
      for ip in ${IPS[@]} ; do
        COUNT_SRC_IP=$(($COUNT_SRC_IP+1))
        if [[ $COUNT_SRC_IP -ne $COUNT_SRC_NAME ]] ; then
          continue
        fi
        echo "Src ip: $ip"
        TMP_ID=$(($TMP_ID+1))
        # Add "class", "qdisc" and "filter"
        # Defining a new child class to apply filter and qdisc
        if [[ "$TEST_CLASS" == "cbq" ]]; then
          sudo tc class add dev $veth parent 1:1 classid 1:$TMP_ID cbq bandwidth $BW0 rate $BW1 allot 1514 avpkt 1000
        elif [[ "$TEST_CLASS" == "htb" ]]; then
          sudo tc class add dev $veth parent 1:1 classid 1:$TMP_ID htb rate $BW1 ceil $BW0
        fi
        # Filtering the flow based on the src IP for this class
        sudo tc filter add dev $veth parent 1:0 protocol ip u32 match ip src ${ip:1:-1} flowid 1:$TMP_ID
        # Adding the desired delay for this class
        sudo tc qdisc add dev $veth parent 1:$TMP_ID handle ${TMP_ID}0: netem delay $DELAY
        echo "--------------"
      done
    done
  done
}


# Modify the already active bridge
function modifyNet() {
  for i in $(docker network ls); do
    if [[ "$i" == "$BR_NAME" ]]; then
      echo "Removing the bridge: $(sudo docker network rm myTestNet)"
    fi
  done

  #statements
}



## Parse mode
if [[ $# -eq 3 ]] ; then
  MODE="$1"
  NEW_C=$2
  TEST_CLASS="$3"
elif [[ $# -eq 2 ]]; then
  MODE="$1"
  BR_NAME="$2"
elif [[ $# -eq 1 ]]; then
  MODE="$1"
else
  echo "Wrong number of arguments"
  exit 0
fi


if [[ "$MODE" == "clean" ]] ; then
  cleanUp
elif [[ "$MODE" == "test" ]]; then
  if [[ "$TEST_CLASS" == "htb" ]] || [[ "$TEST_CLASS" == "cbq" ]]; then
    cleanUp
    testNet
    netInfo
    modify
  else
    echo "Class for tc not defined in this code...!"
    exit 0
  fi
elif [[ "$MODE" == "modify" ]]; then
  netInfo
  modify
else
  echo "Unknown argument/s"
  exit 0
fi
