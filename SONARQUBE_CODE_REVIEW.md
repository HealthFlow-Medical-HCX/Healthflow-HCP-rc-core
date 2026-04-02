# SonarQube-Style Code Review Report

**Repository**: Healthflow-HCP-rc-core  
**Date**: 2026-04-02  
**Scope**: Full codebase (Java, Docker, CI/CD, Infrastructure)  
**Rating**: **D** (Failing - Critical security and quality issues found)

---

## Executive Summary

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Security | 8 | 11 | 7 | 3 | 29 |
| Reliability | 3 | 6 | 5 | 2 | 16 |
| Maintainability | 0 | 4 | 8 | 5 | 17 |
| **Total** | **11** | **21** | **20** | **10** | **62** |

---

## SECURITY HOTSPOTS

### S1. Hardcoded Credentials (CRITICAL)

Multiple files contain hardcoded passwords, secrets, and API keys that should be managed via a secrets manager.

| File | Line(s) | Credential |
|------|---------|------------|
| `docker-compose.yml` | 24 | `POSTGRES_PASSWORD=postgres` |
| `docker-compose.yml` | 40 | `sunbird_sso_admin_client_secret=0358fa30-6014-4192-9551-7c61b15b774c` |
| `docker-compose.yml` | 62 | `KEYCLOAK_PASSWORD=admin` |
| `docker-compose.yml` | 109 | `MINIO_ROOT_PASSWORD=12345678` |
| `java/registry/src/main/resources/application.yml` | 218-220 | Default Keycloak password `abcd@123` |
| `java/claim/src/main/resources/application.properties` | 3-5 | `username=postgres, password=postgres` |
| `deps/keycloak/docker-compose.yml` | 9-10, 19-20 | `POSTGRES_PASSWORD=keycloak`, `DB_PASSWORD=keycloak` |
| `java/registry/docker-compose.yml` | 18-23, 40 | Hardcoded client secret and DB credentials |

**Remediation**: Use environment variables, Docker secrets, or HashiCorp Vault for all credentials. Never commit secrets to version control.

---

### S2. CSRF Protection Disabled (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/config/SecurityConfig.java:54`

```java
HttpSecurity httpConfig = http.csrf().disable();
```

CSRF protection is completely disabled, making the application vulnerable to cross-site request forgery attacks.

**Remediation**: Enable CSRF protection with proper token management. If the API is stateless/JWT-based, document the rationale.

---

### S3. Wildcard CORS Configuration (HIGH)

**File**: `java/registry/src/main/resources/application.yml:31`

```yaml
cors_allowedOrigin: *
```

Allows requests from any origin, enabling cross-site attacks.

**Remediation**: Configure specific allowed origins for each environment.

---

### S4. Path Traversal Vulnerability (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:90-94`

```java
private String getDirectoryPath(String requestedURI) {
    String versionDelimiter = "/v1/";
    String[] split = requestedURI.split(versionDelimiter);
    return split[1]; // No sanitization or path traversal prevention
}
```

User-controlled URI input is used directly to construct file storage paths without validation. An attacker could use `../` sequences to access or overwrite files outside the intended directory.

Also at line 76, `file.getOriginalFilename()` is used without sanitization.

**Remediation**: Normalize paths, reject `..` sequences, validate against an allowlist of permitted directories.

---

### S5. Elasticsearch Injection via queryString Operator (HIGH)

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:361`

```java
case queryString:
    query = query.must(QueryBuilders.queryStringQuery(value.toString()));
    break;
```

User-supplied values are passed directly to `QueryBuilders.queryStringQuery()` without sanitization. This allows Elasticsearch query injection, potentially enabling data exfiltration or denial of service.

**Remediation**: Sanitize or escape special Elasticsearch query characters, or remove the `queryString` operator entirely.

---

### S6. Authentication Bypass by Configuration (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/config/SecurityConfig.java:64-67`

```java
} else {
    httpConfig.authorizeRequests()
        .anyRequest()
        .permitAll();
}
```

Authentication can be completely disabled via `authentication.enabled=false`, opening all endpoints to anonymous access.

**Files**: `docker/docker-compose.yml:330, 347, 371` - Multiple services have `ENABLE_AUTH: "false"`

**Remediation**: Remove the ability to disable authentication entirely. Use role-based access instead.

---

### S7. Overly Permissive Endpoint Authorization (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/config/SecurityConfig.java:56-61`

```java
.antMatchers("/**/invite", "/health", "/error",
    "/_schemas/**", "/**/templates/**", "/**/*.json", "/**/verify",
    "/swagger-ui", "/**/search", "/**/attestation/**",
    "/api/docs/swagger.json","/api/docs/*.json", "/plugin/**")
.permitAll()
```

Sensitive endpoints like `/**/search`, `/**/attestation/**`, `/**/invite`, and `/**/*.json` are publicly accessible without authentication.

**Remediation**: Restrict search, attestation, and invite endpoints to authenticated users. Remove `/**/*.json` wildcard.

---

### S8. Insecure HTTP Communication Between Services (HIGH)

**File**: `java/registry/src/main/resources/application.yml` (multiple lines)

All inter-service communication uses unencrypted HTTP:
- Encryption service: `http://localhost:8013/...`
- Signature service: `http://localhost:8079/...`
- Certificate service: `http://localhost:8078/...`
- Keycloak: `http://localhost:8080/...`
- Notification service: `http://localhost:8765/...`

**Remediation**: Use HTTPS with proper TLS certificates for all service-to-service communication, even within a private network (defense in depth).

---

### S9. Elasticsearch Security Disabled (CRITICAL)

**File**: `docker/docker-compose.yml:65-66`

```yaml
xpack.security.enabled=false
xpack.security.enrollment.enabled=false
```

Elasticsearch is running without authentication or encryption. Any network access can read/modify all data.

**Remediation**: Enable X-Pack security with authentication and TLS.

---

### S10. Vault Running in Development Mode (CRITICAL)

**File**: `docker/docker-compose.yml:156`

```yaml
command: server -dev
```

HashiCorp Vault in dev mode disables TLS, uses in-memory storage (data lost on restart), and uses an unsafe root token.

**Remediation**: Use production mode with proper storage backend, TLS, and auto-unseal.

---

### S11. Exposed Service Ports Without Authentication (CRITICAL)

**File**: `docker-compose.yml`

| Port | Service | Risk |
|------|---------|------|
| 5432 | PostgreSQL | Direct DB access with default credentials |
| 9200/9300 | Elasticsearch | Unauthenticated data access |
| 9990 | WildFly Admin | Admin console exposed |
| 2181 | Zookeeper | Unauthenticated cluster management |
| 9092 | Kafka | Unauthenticated message queue access |
| 9000/9001 | MinIO | Object storage with weak credentials |

**Remediation**: Bind ports to localhost or internal networks only. Use authentication for all services.

---

### S12. File Upload Without Validation (MEDIUM)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:71-88`

No file type validation, size limits, or content verification before storing uploaded files. Allows upload of potentially malicious files.

**Remediation**: Validate file type (allowlist), enforce size limits, scan content for malware signatures.

---

### S13. Sensitive Data in Log Statements (MEDIUM)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java:71`

```java
logger.info("Inviting entity {}", rootNode);  // Logs entire request body
```

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java:176`

```java
logger.info("Updating entityType {} request body {}", entityName, rootNode);  // Logs entire request body
```

**File**: `java/middleware/registry-middleware/keycloak/src/main/java/dev/sunbirdrc/keycloak/KeycloakAdminUtil.java:67`

```java
logger.info("Creating user with mobile_number : " + userName);  // Logs PII
```

Request bodies and PII (phone numbers, emails) are logged at INFO level, potentially exposing sensitive healthcare data.

**Remediation**: Log only non-sensitive identifiers at INFO level. Use DEBUG for detailed payloads with proper log filtering.

---

### S14. External Template URL Injection (MEDIUM)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java:410-412`

```java
if (externalTemplatesEnabled && !StringUtils.isEmpty(request.getHeader(Template))) {
    return request.getHeader(Template);
}
```

When `externalTemplatesEnabled` is true, a user-controlled HTTP header value is used as a template URL. This could enable SSRF attacks.

**Remediation**: Validate the URL against an allowlist of permitted template sources.

---

## RELIABILITY ISSUES

### R1. Stack Traces Exposed to Clients (HIGH)

`e.printStackTrace()` is used extensively instead of proper logging, potentially leaking implementation details:

| File | Line(s) |
|------|---------|
| `FileStorageService.java` | 84, 114, 142, 153 |
| `RegistryClaimsController.java` | 69, 83, 86, 181, 203 |
| `RegistryEntityController.java` | 404, 546, 593, 623 |
| `RegistryTemplateController.java` | 25 |

**Remediation**: Replace all `e.printStackTrace()` with `logger.error("message", e)`. Return generic error messages to clients.

---

### R2. Potential Null Pointer Dereferences (HIGH)

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:185`

```java
return response.status(); // response can be null if IOException is caught at line 182
```

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:229`

```java
return response.status(); // same pattern - response null if exception caught
```

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java:571`

```java
return null; // attestEntity method returns null ResponseEntity
```

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:93`

```java
return split[1]; // ArrayIndexOutOfBoundsException if URI doesn't contain "/v1/"
```

**Remediation**: Add null checks, validate input, return proper error responses.

---

### R3. Resource Leaks (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:134-139`

```java
InputStream inputStream = minioClient.getObject(...);
bytes = IOUtils.toByteArray(inputStream);
// inputStream never closed
```

The `InputStream` from MinIO is never closed, causing potential resource leaks.

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:86-101`

`RestHighLevelClient` instances are cached in a static HashMap but never closed on application shutdown.

**Remediation**: Use try-with-resources for all `InputStream`/`Closeable` objects. Implement proper lifecycle management for cached clients.

---

### R4. Infinite Recursion Risk (MEDIUM)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:41-47`

```java
public void save(InputStream inputStream, String objectName) throws Exception {
    if (!isBucketExists()) {
        createNewBucket();
        save(inputStream, objectName);  // Recursive call - infinite loop if bucket creation fails silently
    }
    // ...
}
```

The TODO comment on line 45 acknowledges this risk.

**Remediation**: Remove recursion. Create bucket once, then proceed with save. Add a boolean check or retry limit.

---

### R5. Raw Type Usage (MEDIUM)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java`

```java
Map resultMap = new HashMap();  // Lines 81, 230 - raw types
```

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/service/FileStorageService.java:147`

```java
public ResponseEntity deleteDocument(...)  // Raw ResponseEntity
```

**Remediation**: Use parameterized generics throughout.

---

### R6. Exception Messages Exposed in API Responses (HIGH)

Multiple controllers set `exception.getMessage()` directly in error responses:

| File | Line(s) |
|------|---------|
| `RegistryEntityController.java` | 133, 164, 207, 249, 287, 319, 477, 527, 592, 622 |
| `RegistryClaimsController.java` | 115, 182 |

Internal exception messages may reveal stack details, SQL queries, or system paths to attackers.

**Remediation**: Return generic error messages. Log the full exception server-side.

---

## MAINTAINABILITY ISSUES

### M1. God Class - RegistryHelper (HIGH)

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/helper/RegistryHelper.java`

This class has 30+ injected dependencies, 50+ methods, and handles authentication, entity CRUD, attestation, signing, notification, and file storage. It violates the Single Responsibility Principle.

**Remediation**: Break into smaller focused services (AuthService, EntityService, AttestationService, NotificationService).

---

### M2. Catching Generic Exception (HIGH)

Almost every controller method catches `Exception` broadly instead of specific exceptions:

```java
} catch (Exception e) {
    // generic handling
}
```

Found in: `RegistryEntityController.java` (lines 88-101, 115, 130, 160, 204, 245, 286, 318, 356, 381, 475, 522, 545, 590, 620), `RegistryClaimsController.java` (lines 67, 81, 85, 112, 179), `FileStorageController.java`, etc.

**Remediation**: Catch specific exceptions. Use `@ExceptionHandler` or `@ControllerAdvice` for centralized error handling.

---

### M3. Duplicated Error Handling Pattern (MEDIUM)

Every controller method duplicates the same error response pattern:

```java
responseParams.setStatus(Response.Status.UNSUCCESSFUL);
responseParams.setErrmsg(e.getMessage());
return new ResponseEntity<>(response, HttpStatus.INTERNAL_SERVER_ERROR);
```

This pattern appears 15+ times across controllers.

**Remediation**: Extract to a `@ControllerAdvice` with `@ExceptionHandler` methods.

---

### M4. Magic Strings and Numbers (MEDIUM)

| File | Line | Value |
|------|------|-------|
| `FileStorageService.java` | 52 | `10485760` (10MB) - unexplained size limit |
| `FileStorageService.java` | 91 | `"/v1/"` - hardcoded version delimiter |
| `FileStorageService.java` | 126 | `2, TimeUnit.HOURS` - unexplained expiry |
| `ElasticServiceImpl.java` | 98 | `null != client` - should use Objects.nonNull or check differently |
| `RegistryEntityController.java` | 48 | `"transactionId"` - should be a constant |

**Remediation**: Extract to named constants with descriptive names.

---

### M5. Deprecated API Usage (MEDIUM)

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java`

Uses `RestHighLevelClient` which is deprecated in Elasticsearch 7.15+ and removed in 8.x. Should migrate to the new Java API Client.

**File**: `java/registry/src/main/java/dev/sunbirdrc/registry/controller/RegistryEntityController.java:628`

`@Deprecated` method `getSignedEntityByToken` still present in codebase.

---

### M6. Thread Safety Issues (MEDIUM)

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:48-49`

```java
private static Map<String, Set<String>> indexWiseExcludeFields = new HashMap<>();
private static Map<String, RestHighLevelClient> esClient = new HashMap<>();
```

Static mutable `HashMap` accessed from multiple threads without synchronization. `createClient()` at line 86 has a check-then-act race condition.

**Remediation**: Use `ConcurrentHashMap` or add proper synchronization.

---

### M7. Commented-Out Code (LOW)

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:131-132, 137-140`

Large blocks of commented-out Elasticsearch configuration code.

**File**: `java/elastic-search/src/main/java/dev/sunbirdrc/elastic/ElasticServiceImpl.java:257`

Commented-out code: `// Map<String, Object> entityMap = (Map<String, Object>) readMap.get(index);`

**Remediation**: Remove dead/commented code. Use version control history if needed later.

---

### M8. Missing Input Validation on API Endpoints (MEDIUM)

No validation on path variables or request bodies:

- `entityName` path variable is never validated against known entity types before processing
- `entityId` is not validated for format/length
- `requestBody` JSON is not validated for size limits
- `searchNode` in search endpoint has no query complexity limits

**Remediation**: Add `@Valid` annotations, custom validators, and request size limits.

---

## INFRASTRUCTURE & DEPENDENCY ISSUES

### I1. Outdated/Vulnerable Base Images (CRITICAL)

| File | Image | Issue |
|------|-------|-------|
| `java/registry/Dockerfile` | `openjdk:8-jdk-alpine` | Java 8 EOL, Alpine OpenJDK deprecated |
| `java/claim/Dockerfile` | `openjdk:8-jdk-alpine` | Same |
| `Dockerfile` | `frolvlad/alpine-java:jdk8-slim` | Unmaintained third-party image |
| `deps/keycloak/Dockerfile` | `jboss/keycloak:14.0.0` | Keycloak 14 from 2021, known CVEs |
| `services/notification-service/Dockerfile` | `golang:1.15-alpine` | Go 1.15 from 2020, many known vulnerabilities |

**Remediation**: Upgrade to Java 17/21 LTS, Keycloak 25+, Go 1.22+. Pin all image versions.

---

### I2. Unpinned Docker Image Tags (HIGH)

| File | Line | Image |
|------|------|-------|
| `docker-compose.yml` | 124 | `confluentinc/cp-zookeeper:latest` |
| `docker-compose.yml` | 131 | `confluentinc/cp-kafka:latest` |
| `services/certificate-signer/Dockerfile` | 1 | `node:lts-alpine` |
| `services/certificate-api/Dockerfile` | 1 | `node:lts-alpine` |

**Remediation**: Pin all image versions for reproducible builds.

---

### I3. Docker Containers Running as Root (MEDIUM)

None of the Dockerfiles specify a non-root `USER` directive:
- `Dockerfile`
- `java/registry/Dockerfile`
- `java/claim/Dockerfile`
- `services/certificate-api/Dockerfile`
- `services/certificate-signer/Dockerfile`
- `services/notification-service/Dockerfile`

**Remediation**: Add `USER` directive to run as non-root user.

---

### I4. Missing Docker Resource Limits (MEDIUM)

Root `docker-compose.yml` lacks `deploy.resources.limits` for most services, risking resource exhaustion.

---

### I5. CI/CD Auto-Approve (HIGH)

**File**: `.github/workflows/deploy-sunbird-rc.yml:388`

```yaml
terraform apply -auto-approve
```

Infrastructure changes applied without manual review/approval gate.

**Remediation**: Add approval step for production deployments.

---

### I6. Java 8 Target (HIGH)

**File**: `java/pom.xml:14-16`

Project targets Java 1.8 which is end-of-life. Missing security patches and modern language features.

**Remediation**: Migrate to Java 17 or 21 LTS.

---

## RECOMMENDED PRIORITY ACTIONS

### Immediate (P0 - Critical)
1. Remove all hardcoded credentials; implement secrets management
2. Enable Elasticsearch security (X-Pack authentication + TLS)
3. Stop running Vault in dev mode
4. Fix path traversal vulnerability in `FileStorageService`
5. Restrict exposed service ports to internal networks
6. Upgrade outdated base images (Java 8, Keycloak 14, Go 1.15)

### Short-term (P1 - High)
7. Enable CSRF protection or document JWT-based stateless architecture
8. Restrict CORS to specific origins
9. Replace all `e.printStackTrace()` with proper logging
10. Sanitize Elasticsearch `queryString` operator input
11. Fix null pointer dereference risks in `ElasticServiceImpl`
12. Close resource leaks (InputStreams, ES clients)
13. Remove generic exception messages from API responses
14. Add file upload validation (type, size, content)
15. Pin all Docker image versions

### Medium-term (P2 - Medium)
16. Implement `@ControllerAdvice` for centralized error handling
17. Refactor `RegistryHelper` God class
18. Add input validation on all API endpoints
19. Use `ConcurrentHashMap` for thread-safe ES client cache
20. Add non-root USER directives to all Dockerfiles
21. Add Docker resource limits
22. Add CI/CD approval gates for production deployments

### Long-term (P3 - Low)
23. Remove all commented-out code
24. Migrate from deprecated `RestHighLevelClient` to new ES Java Client
25. Extract magic numbers to named constants
26. Remove deprecated `getSignedEntityByToken` endpoint
27. Migrate from Travis CI to GitHub Actions (Travis CI deprecated)
