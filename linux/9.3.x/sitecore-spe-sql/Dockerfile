ARG BASE_IMAGE

FROM $BASE_IMAGE as builder

USER root

RUN apt-get -y update \
    && apt-get -y --allow-unauthenticated install unzip \
    && wget -progress=bar:force -q -O sqlpackage.zip https://go.microsoft.com/fwlink/?linkid=2113331 \
    && unzip -qq sqlpackage.zip -d /opt/sqlpackage \
    && chmod +x /opt/sqlpackage/sqlpackage

COPY *.zip /opt/wdp/

RUN unzip -qq /opt/wdp/Sitecore*scwdp.zip -d /opt/wdp/

COPY attach-databases.sh /opt/
COPY install-databases.sh /opt/

ENV DB_PREFIX='sc'

RUN mkdir -p /install \
    && chmod -R 700 /install \
    && cp /clean/* /install/ \
    && ( /opt/mssql/bin/sqlservr & ) | grep -q "Service Broker manager has started" \
    && ./opt/attach-databases.sh /install \
    && ./opt/install-databases.sh /opt/wdp

FROM $BASE_IMAGE

COPY --from=builder ["/install/*", "/clean/"]
