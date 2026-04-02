FROM quay.io/keycloak/keycloak:24.0

COPY themes /opt/keycloak/themes
COPY providers /opt/keycloak/providers

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]