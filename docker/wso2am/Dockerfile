FROM wso2/wso2am:4.7.0

ARG MYSQL_CONNECTOR_VERSION=8.0.33

COPY --chown=wso2carbon:wso2 \
  wso2-config/ \
  /home/wso2carbon/wso2-config-volume/

COPY --chown=wso2carbon:wso2 \
  docker/wso2am/entrypoint.sh \
  /home/wso2carbon/noogym-entrypoint.sh

ADD --chown=wso2carbon:wso2 \
  https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar \
  /home/wso2carbon/wso2am-4.7.0/repository/components/lib/

RUN chmod +x /home/wso2carbon/noogym-entrypoint.sh

ENTRYPOINT ["/home/wso2carbon/noogym-entrypoint.sh"]
