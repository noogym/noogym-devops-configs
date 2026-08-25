FROM wso2/wso2am:4.7.0

ARG MYSQL_CONNECTOR_VERSION=8.0.33

ADD --chown=wso2carbon:wso2 \
  https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar \
  /home/wso2carbon/wso2am-4.7.0/repository/components/lib/
