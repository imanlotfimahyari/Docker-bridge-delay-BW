# Docker-bridge-delay-BW-control

## Motivation
If you have multiple docker containers connected together through a bridge, then using this sample script, you can modify the delays from one container to another with `linux traffic controller (tc)`. This control is done from inside the bridge and not from inside of the containers which is useful if you do not want to touch the containers. It is also possible to control the `Bandwidth` as well.

## Introduction
The controll of the delay from `container A` towards `container B` is done in `VethXXX` which is connecting the `container B` to the bridge. So, for applying the different delays for data coming from different source containers, it is needed to distinguish between the source of the data in `VethXXX`. As every container has an IP address, this can be done through filtering the source IP address of the sender.

A simple structure with internal view of `VethXX` a bridge and the containers is demonstrated here: 

<p align="middle">
  <img src="./single-topo.png" width="300" height="250" />
  <img src="./mid2.png" width="300" height="250" /> 
</p>

## Using the script

You can use the scripts in two ways:

A. Starting a test structure using    
  ```bash
  DBDelay.sh testing X
  ```
  Where `X` is the desired number of the containers. This will build a network called `testNet` with a bridge named `myTestNet` and the containers named `Client1` to `ClientX`.  It will ask for each container the total bandwidth it accepts from the bridge (through VethX), the delay and the bandwidth regarding every other container towards this one. Do not forget to use symmetric delays between each pair of containers and keep in mind that sum of the total bandwidth assigned to flows crossing VethX should not exceed the main bandwidth assigned tio this VethX. Also, sum of the total bandwidth in the bridge should be less than 1/10 of the available system bandwidth.
  
  In this case, after fininishing your tests, you can clean the test structure using
  ```bash
  DBDelay.sh clean X
  ``` 
B. Applying the script on an existing bridge. 
  1. Run the script as
  ```bash
  DBDelay.sh BRIDGE_NAME
  ``` 
  Where ` BRIDGE_NAME` is the name of your bridge that you want to apply your desired delay and bandwith control (use `docker network ls` in case you do not remember the bridge name). It will ask for each container the total bandwidth it accepts from the bridge (through VethX), the delay and the bandwidth regarding every other container towards this one. Do not forget to use symmetric delays between each pair of containers and keep in mind that sum of the total bandwidth assigned to flows crossing VethX should not exceed the main bandwidth assigned tio this VethX. Also, sum of the total bandwidth in the bridge should be less than 1/10 of the available system bandwidth.
