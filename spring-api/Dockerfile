# ── Build stage ──────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN apk add --no-cache maven \
    && mvn clean package -DskipTests -q

# ── Runtime stage ────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

# Render injects PORT env var; default to 8080 for local docker runs.
ENV PORT=8080
EXPOSE ${PORT}

# NOTE: exec-form ENTRYPOINT does NOT expand ${PORT}, so shell form is used.
# JVM tuned for Render's 512MB free-tier RAM.
ENTRYPOINT ["sh", "-c", "java -XX:+UseSerialGC -Xms128m -Xmx384m -XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Dspring.main.lazy-initialization=true -Dserver.port=${PORT:-8080} -jar app.jar"]
