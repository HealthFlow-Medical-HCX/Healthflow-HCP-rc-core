FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} app.jar
RUN chown appuser:appgroup /app.jar
USER appuser
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:8082/health || exit 1
ENTRYPOINT ["java","-jar","/app.jar"]
