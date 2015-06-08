#!/bin/bash

VOLUME_HOME="/var/lib/mysql"
CONF_FILE="/etc/mysql/conf.d/my.cnf"
LOG="/var/log/mysql/error.log"

# Set permission of config file
chmod 644 ${CONF_FILE}
chmod 644 /etc/mysql/conf.d/mysqld_charset.cnf

StartMySQL ()
{
    /usr/bin/mysqld_safe > /dev/null 2>&1 &

    # Time out in 1 minute
    LOOP_LIMIT=13
    for (( i=0 ; ; i++ )); do
        if [ ${i} -eq ${LOOP_LIMIT} ]; then
            echo "Time out. Error log is shown as below:"
            tail -n 100 ${LOG}
            exit 1
        fi
        echo "=> Waiting for confirmation of MySQL service startup, trying ${i}/${LOOP_LIMIT} ..."
        sleep 5
        mysql -uroot -e "status" > /dev/null 2>&1 && break
    done
}

CreateMySQLUser()
{
  StartMySQL

        #Setup DB
        if [ "$ON_CREATE_DB" = "**False**" ]; then
            unset ON_CREATE_DB
        else
            echo "Creating MySQL database ${ON_CREATE_DB}"
            mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${ON_CREATE_DB};"
            echo "Database created!"
        fi

  if [ "$MYSQL_PASS" = "**Random**" ]; then
      unset MYSQL_PASS
  fi

  PASS=${MYSQL_PASS:-$(pwgen -s 12 1)}
  _word=$( [ ${MYSQL_PASS} ] && echo "preset" || echo "random" )
  echo "=> Creating MySQL user ${MYSQL_USER} with ${_word} password"

  mysql -uroot -e "CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '$PASS'"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION"


  echo "=> Done!"

  echo "========================================================================"
  echo "You can now connect to this MySQL Server using:"
  echo ""
  echo "    mysql -u$MYSQL_USER -p$PASS -h<host> -P<port>"
  echo ""
  echo "Please remember to change the above password as soon as possible!"
  echo "MySQL user 'root' has no password but only allows local connections"
  echo "========================================================================"

  mysqladmin -uroot shutdown
}

ImportSql()
{
  StartMySQL

  for FILE in ${STARTUP_SQL}; do
     echo "=> Importing SQL file ${FILE}"
     mysql -uroot < "${FILE}"
  done

  mysqladmin -uroot shutdown
}

# Main
if [ ${REPLICATION_MASTER} == "**False**" ]; then
    unset REPLICATION_MASTER
fi

if [ ${REPLICATION_SLAVE} == "**False**" ]; then
    unset REPLICATION_SLAVE
fi



# Initialize empty data volume and create MySQL user
if [[ ! -d $VOLUME_HOME/mysql ]]; then
    echo "=> An empty or uninitialized MySQL volume is detected in $VOLUME_HOME"
    echo "=> Installing MySQL ..."
    if [ ! -f /usr/share/mysql/my-default.cnf ] ; then
        cp /etc/mysql/my.cnf /usr/share/mysql/my-default.cnf
    fi
    mysql_install_db > /dev/null 2>&1
    echo "=> Done!"
    echo "=> Creating admin user ..."

    echo "port=${MYSQL_PORT}" >> $CONF_FILE

    CreateMySQLUser
else
    echo "=> Using an existing volume of MySQL"
fi

# Import Startup SQL
if [ -n "${STARTUP_SQL}" ]; then
    if [ ! -f /sql_imported ]; then
        echo "=> Initializing DB with ${STARTUP_SQL}"
        ImportSql
        touch /sql_imported
    fi
fi

if [ -n "${REPLICATION}" ] && [ -n "${ETCDCTL_PEERS}" ] ; then

    if [ -z "${IP_ADDR}" ]; then
        IP_ADDR="$(ifconfig ${NET_INTERFACE} | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}')"
    fi
    echo "=> IP: ${IP_ADDR}"
    echo "=> MYSQL_PORT=${MYSQL_PORT}"

    if [ ! -f /gtid_configured ]; then
        echo "=> Configuring MySQL GTID mode"
        RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"


        echo "=> Writting configuration file '${CONF_FILE}' with gtid-mode=on and log-slave-updates=true"
        sed -i "s/^#server-id.*/server-id=${RAND}/" ${CONF_FILE}
        sed -i "s/^#log-bin.*/log-bin=${RAND}.log/" ${CONF_FILE}
        sed -i "s/^#report-host/report-host=${IP_ADDR}/" ${CONF_FILE}
        sed -i "s/^#report-port/report-port=${MYSQL_PORT}/" ${CONF_FILE}
        sed -i "s/^#binlog-format=ROW/binlog-format=ROW/" ${CONF_FILE}
        sed -i "s/^#enforce-gtid-consistency=true/enforce-gtid-consistency=true/" ${CONF_FILE}
        sed -i "s/^#log-slave-updates=true/log-slave-updates=true/" ${CONF_FILE}
        sed -i "s/^#gtid-mode=on/gtid-mode=on/" ${CONF_FILE}
        sed -i "s/^#master-info-repository=TABLE/master-info-repository=TABLE/" ${CONF_FILE}
        sed -i "s/^#relay-log-info-repository=TABLE/relay-log-info-repository=TABLE/" ${CONF_FILE}
        sed -i "s/^#sync-master-info=1/sync-master-info=1/" ${CONF_FILE}
        echo "=> Starting MySQL ..."
        StartMySQL
        echo "=> Done!"
        mysqladmin -uroot shutdown
        touch /gtid_configured
    else
        echo "=> MySQL GTID already configured, skip"
    fi

    if [ -z "${ETCD_DIR}" ]; then
        ETCD_DIR="mysql"
    fi

    MASTER_HOST=$(etcdctl get $ETCD_DIR/master/host)
    echo "=> MASTER_HOST=${MASTER_HOST}"
    MASTER_PORT=$(etcdctl get $ETCD_DIR/master/port)
    echo "=> MASTER_PORT=${MASTER_PORT}"

    if [  "$MASTER_HOST" != "$IP_ADDR" ] || [ "$MASTER_PORT" != $MYSQL_PORT ]; then
        # Found master valu in etcd
        if [ -n "${MASTER_HOST}" ]; then
          # Set MySQL REPLICATION - SLAVE
            if [ -n "${IP_ADDR}" ] && [ -n "${MYSQL_PORT}" ]; then
                MASTER_USER=$(etcdctl get $ETCD_DIR/master/user)
                MASTER_PASS=$(etcdctl get $ETCD_DIR/master/pass)
                RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
                echo "=> Writting configuration file '${CONF_FILE}' with server-id=${RAND}"
                echo "=> Setting master connection info on slave"
                echo "=> Starting MySQL ..."
                StartMySQL
                mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='${MASTER_HOST}',MASTER_USER='${MASTER_USER}',MASTER_PASSWORD='${MASTER_PASS}',MASTER_PORT=${MASTER_PORT}, MASTER_CONNECT_RETRY=30"
                ETCD_SLAVE_PATH="${IP_ADDR}_${MYSQL_PORT}"
                etcdctl set $ETCD_DIR/slaves/$ETCD_SLAVE_PATH/host $IP_ADDR
                etcdctl set $ETCD_DIR/slaves/$ETCD_SLAVE_PATH/port $MYSQL_PORT
                etcdctl set $ETCD_DIR/slaves/$ETCD_SLAVE_PATH/user $MYSQL_USER
                etcdctl set $ETCD_DIR/slaves/$ETCD_SLAVE_PATH/pass $MYSQL_PASS
                echo "=> Done!"
                mysqladmin -uroot shutdown
            fi
        else
            # Set MySQL REPLICATION - MASTER
            if [ -n "${IP_ADDR}" ] && [ -n "${MYSQL_PORT}" ]; then
                echo "=> Configuring MySQL replication as master ..."
                etcdctl set $ETCD_DIR/master/host $IP_ADDR
                etcdctl set $ETCD_DIR/master/port $MYSQL_PORT
                etcdctl set $ETCD_DIR/master/user $MYSQL_USER
                etcdctl set $ETCD_DIR/master/pass $MYSQL_PASS
                echo "=> Done!"
            fi
        fi
    else
      echo "=> Already master"
    fi
fi

echo "=> MySQL Config"
cat ${CONF_FILE}

tail -F $LOG &
exec mysqld_safe
