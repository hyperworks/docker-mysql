# docker-mysql
mysql and utilities container


## Example

### Simple Database

```
$ docker run -d --name db01 --privileged=true --net=host \
-e NET_INTERFACE=eth1 \
-e MYSQL_PASS=admin \
-e MYSQL_PORT=3306 \
hyperworks/mysql
```

### Replicate

Replicate required etcd for save master machine data.
If etcd never has master data in specific dir the first container will be master
IP com from network interface, default is eth0
You have to run on `--net=host` for connect to each machines easier

MysqlPort default 3306
MYSQL_PASS default random

```
$ docker run -d --name db01 --privileged=true --net=host \
-e NET_INTERFACE=eth1 \
-e ETCDCTL_PEERS=192.168.99.100:4001 \
-e ETCD_DIR=mysqlconifg \
-e MYSQL_PASS=admin \
-e REPLICATION=true \
-e MYSQL_PORT=3306 \
hyperworks/mysql

$ docker run -d --name db02 --privileged=true --net=host \
-e NET_INTERFACE=eth1 \
-e ETCDCTL_PEERS=192.168.99.100:4001 \
-e ETCD_DIR=mysqlconifg \
-e MYSQL_PASS=admin \
-e REPLICATION=true \
-e MYSQL_PORT=3307 \
hyperworks/mysql
```

