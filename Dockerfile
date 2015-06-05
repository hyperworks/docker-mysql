FROM ubuntu:trusty

# Install packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
  apt-get -yq install mysql-server-5.6 pwgen curl python && \
  rm -rf /var/lib/apt/lists/*

RUN curl http://cdn.mysql.com/Downloads/Connector-Python/mysql-connector-python_2.0.4-1ubuntu14.04_all.deb > /tmp/mysql-connector-python_2.0.4-1ubuntu14.04_all.deb
RUN curl http://cdn.mysql.com/Downloads/MySQLGUITools/mysql-utilities_1.5.4-1ubuntu14.04_all.deb > /tmp/mysql-utilities_1.5.4-1ubuntu14.04_all.deb

RUN dpkg -i /tmp/mysql-connector-python_2.0.4-1ubuntu14.04_all.deb
RUN dpkg -i /tmp/mysql-utilities_1.5.4-1ubuntu14.04_all.deb

# Remove pre-installed database
RUN rm -rf /var/lib/mysql/*

# Remove syslog configuration
RUN rm /etc/mysql/conf.d/mysqld_safe_syslog.cnf


RUN curl -L https://github.com/coreos/etcd/releases/download/v2.0.11/etcd-v2.0.11-linux-amd64.tar.gz -o /tmp/etcd-v2.0.11-linux-amd64.tar.gz
RUN tar xzvf /tmp/etcd-v2.0.11-linux-amd64.tar.gz
RUN cp /etcd-v2.0.11-linux-amd64/etcdctl /usr/local/bin/etcdctl
RUN rm -rf /tmp/etcd-v2.0.11-linux-amd64.tar.gz /etcd-v2.0.11-linux-amd64

# Add MySQL configuration
ADD my.cnf /etc/mysql/conf.d/my.cnf
ADD mysqld_charset.cnf /etc/mysql/conf.d/mysqld_charset.cnf

# Add MySQL scripts
ADD import_sql.sh /import_sql.sh
ADD run.sh /run.sh
RUN chmod 755 /*.sh

# Exposed ENV
ENV MYSQL_PORT 3600
ENV MYSQL_USER admin
ENV MYSQL_PASS **Random**
ENV ON_CREATE_DB **False**

# Replication ENV
ENV REPLICATION **False**
ENV REPLICATION_MASTER **False**
ENV REPLICATION_SLAVE **False**
ENV REPLICATION_USER replica
ENV REPLICATION_PASS replica

# Add VOLUMEs to allow backup of config and databases
VOLUME  ["/etc/mysql", "/var/lib/mysql"]

EXPOSE 3306

CMD ["/run.sh"]


