version: '3'
services:
  api-manager:
    image: 'wso2/wso2am:4.3.0'
    container_name: api-manager
    ports:
      - '5672:5672'
      - '8243:8243'
      - '8280:8280'
      - '9443:9443'
      - '9099:9099'
      - '9611:9611'
      - '9711:9711'
      - '9999:9999'
    depends_on:
      - mysql-db
    environment:
      - WSO2_USER=${APIM_ADMIN_USER}
      - WSO2_PASSWORD=${APIM_ADMIN_PASSWORD}
      - WSO2_DATABASE_HOST=mysql-db
      - WSO2_DATABASE_PORT=3306
      - WSO2_DATABASE_NAME=wso2amdb
      - WSO2_DATABASE_USER=wso2amdbuser
      - WSO2_DATABASE_PASSWORD=${APIM_DB_PASSWORD}
    networks:
      - wso2am_network
  mysql-db:
    image: 'mysql:5.7'
    container_name: mysql-db
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_USER: wso2amdbuser
      MYSQL_PASSWORD: ${APIM_DB_PASSWORD}
      MYSQL_DATABASE: wso2amdb
    networks:
      - wso2am_network
  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: phpmyadmin
    ports:
      - '8088:80'
    depends_on:
      - mysql-db
    environment:
      - PMA_HOST=mysql-db
      - PMA_PORT=3306
      - PMA_ARBITRARY=1
    networks:
      - wso2am_network
networks:
  wso2am_network:
    driver: bridge
