FROM wso2/wso2am:4.7.0 AS apim

FROM mysql:8.0

COPY --from=apim /home/wso2carbon/wso2am-4.7.0/dbscripts/mysql.sql /wso2-dbscripts/shared/mysql.sql
COPY --from=apim /home/wso2carbon/wso2am-4.7.0/dbscripts/apimgt/mysql.sql /wso2-dbscripts/apimgt/mysql.sql
COPY init/01-init-wso2-databases.sh /docker-entrypoint-initdb.d/01-init-wso2-databases.sh
