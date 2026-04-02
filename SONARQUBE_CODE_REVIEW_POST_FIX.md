# SonarQube-Style Code Review Report - POST-FIX

**Repository**: Healthflow-HCP-rc-core  
**Date**: 2026-04-02  
**Scope**: Full codebase re-review after applying 60+ fixes  
**Previous Rating**: **D** (Failing - 67 findings)  
**Current Rating**: **B** (Passing with remaining items)

---

## Executive Summary

The previous review identified 67 findings (13 Critical, 24 High, 20 Medium, 10 Low). After applying fixes across 35 files, a comprehensive re-review was conducted. The results show significant improvement:

| Category | Before | After | Resolved |
|----------|--------|-------|----------|
| Critical | 13 | 2 | 11 |
| High | 24 | 6 | 18 |
| Medium | 20 | 8 | 12 |
| Low | 10 | 4 | 6 |
| **Total** | **67** | **20** | **47 (70% resolved)** |

---

## RESOLVED ISSUES (Verified Fixed)

### Security Fixes Verified
- [x] **Hardcoded credentials** in root `docker-compose.yml` - Now uses `${ENV_VAR:?error}` syntax
- [x] **Hardcoded credentials** in `deps/keycloak/docker-compose.yml` - Now uses env vars
- [x] **CORS wildcard** - Changed from `*` to `http://localhost:3000`
- [x] **Weak default password** `abcd@123` - Removed from `application.yml`
- [x] **Path traversal** in `FileStorageService` - Added `Paths.normalize()` + validation
- [x] **Elasticsearch injection** via `queryString` - Added `sanitizeQueryString()` method
- [x] **Elasticsearch security disabled** - Enabled X-Pack with required password
- [x] **Vault dev mode** - Changed to production `server` command
- [x] **Auth disabled on services** - `ENABLE_AUTH` now defaults to `true`
- [x] **File upload without validation** - Added content-type allowlist
- [x] **SSRF via template URLs** - Added URL validation against localhost/internal IPs
- [x] **Overly permissive endpoints** - Removed `/**/search`, `/**/invite`, `/**/*.json` from permitAll

### Reliability Fixes Verified
- [x] **27+ `e.printStackTrace()` calls** - All replaced with `logger.error()` in production code
- [x] **Exception messages in API responses** - Replaced with generic messages
- [x] **Null pointer in `ElasticServiceImpl.addEntity/updateEntity`** - Returns `INTERNAL_SERVER_ERROR` status
- [x] **Resource leak in `FileStorageService.getDocument`** - Uses try-with-resources
- [x] **Resource leak in `OSResourceLoader`** - Uses try-with-resources
- [x] **Resource leak in `ElasticServiceImpl`** - Added `@PreDestroy` cleanup
- [x] **Infinite recursion in `FileStorageService.save()`** - Replaced with `ensureBucketExists()`
- [x] **Null return in `attestEntity()`** - Returns `ResponseEntity(HttpStatus.OK)`
- [x] **Unsafe array access in `RegistryHelper.getPropertyURI()`** - Added bounds checking
- [x] **Null-unsafe chaining in `RegistryClaimsController`** - Added null checks

### Quality Fixes Verified
- [x] **Broken singleton in `ActorCache`** - Fixed with Holder pattern + `ConcurrentHashMap`
- [x] **Thread safety in `ElasticServiceImpl`** - `ConcurrentHashMap` + `computeIfAbsent`
- [x] **`System.out.println` in `ActorCache`/`SunbirdActorFactory`** - Replaced with SLF4J
- [x] **Sensitive data in logs** - PII removed from `KeycloakAdminUtil`, `ResponseWrapper`, controllers
- [x] **Raw types** - Parameterized in `RegistryEntityController`, `FileStorageController`
- [x] **Magic numbers** - Extracted to constants in `FileStorageService`
- [x] **Commented-out code** - Removed in `GenericConfiguration`, `certificate-api/Dockerfile`
- [x] **Centralized error handling** - Added `GlobalExceptionHandler` with `@ControllerAdvice`

### Infrastructure Fixes Verified
- [x] **Java 8 base images** - Upgraded to `eclipse-temurin:17-jre-alpine`
- [x] **Go 1.15** - Upgraded to `golang:1.22-alpine` with multi-stage build
- [x] **Node `lts-alpine`** - Pinned to `node:18-alpine`
- [x] **Kafka/Zookeeper `latest`** - Pinned to `7.5.0`
- [x] **No `USER` directive** - Added non-root user to all 6 Dockerfiles
- [x] **No `HEALTHCHECK`** - Added to Java service Dockerfiles
- [x] **`npm install --silent`** - Changed to `npm ci`
- [x] **Claim DB credentials** - Removed default `postgres/postgres`

---

## REMAINING ISSUES

### CRITICAL (2)

#### RC1. Hardcoded SendInBlue API Key
**File**: `deps/keycloak-mobile-number-login-spi/src/main/java/in/divoc/api/authenticator/EmailService.java:23`
```java
con.setRequestProperty("api-key", "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");
```
**Impact**: Exposed API key allows unauthorized email sending. This key should be rotated immediately.
**Remediation**: Move to environment variable, rotate the compromised key.

#### RC2. Hardcoded Credentials in `java/registry/docker-compose.yml`
**File**: `java/registry/docker-compose.yml:22-23`
```yaml
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
```
**Note**: This is a separate docker-compose file from the root one (which was fixed). Also uses outdated `frolvlad/alpine-oraclejdk8:slim` base image.
**Remediation**: Apply same env var pattern as root docker-compose.

---

### HIGH (6)

#### RH1. Keycloak Running in Dev Mode (`docker/docker-compose.yml:186`)
```yaml
command: start-dev --import-realm
```
Dev mode disables security features. Use `start` for production.

#### RH2. Outdated Keycloak Base Image (`deps/keycloak/Dockerfile:1`)
```dockerfile
FROM jboss/keycloak:14.0.0
```
Keycloak 14 (2021) has known CVEs. Upgrade to 24.x+.

#### RH3. Redis Without Authentication (`docker/docker-compose.yml:42`)
No `--requirepass` configured. Any network access can read/write cache data.

#### RH4. Kafka PLAINTEXT Communication (`docker-compose.yml:141`)
```yaml
KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "INTERNAL:PLAINTEXT,OUTSIDE:PLAINTEXT"
```
All messages transmitted unencrypted without authentication.

#### RH5. CSRF Disabled for API Routes (`SecurityConfig.java:56`)
```java
.ignoringAntMatchers("/api/v1/**")
```
While common for REST APIs with token auth, this should be documented as an intentional design decision if the API is stateless/JWT-based.

#### RH6. MinIO Unpinned Image Tag (`docker/docker-compose.yml:619`)
```yaml
image: minio/minio:latest
```

---

### MEDIUM (8)

#### RM1. Vault Dev Token in Environment (`docker/docker-compose.yml:149`)
`VAULT_DEV_ROOT_TOKEN_ID` environment variable - even from env var, dev tokens are insecure.

#### RM2. Keycloak HTTP Enabled (`docker/docker-compose.yml:180`)
`KC_HTTP_ENABLED: "true"` - Should enforce HTTPS-only in production.

#### RM3. Password Logged in Deploy Script (`scripts/deploy.sh:305`)
```bash
echo "  - Keycloak Admin: http://localhost:8080 (admin/${KEYCLOAK_ADMIN_PASSWORD:-admin})"
```

#### RM4. Placeholder Secrets in application.yml (`application.yml:288-289`)
```yaml
accesskey: ${filestorage_access_key:XXXXX}
secretkey: ${filestorage_secret_key:XXXXX}
```

#### RM5. Database Port Exposed in docker/docker-compose.yml (Line 22)
`"5432:5432"` binds to all interfaces (root docker-compose correctly uses `127.0.0.1`).

#### RM6. Missing HTTP Security Headers
No `X-Frame-Options`, `X-Content-Type-Options`, or `Strict-Transport-Security` headers configured.

#### RM7. No API Rate Limiting
No rate limiting on any endpoints - vulnerable to brute force and DoS.

#### RM8. `System.out.println` in EmailService (`deps/keycloak-mobile-number-login-spi/.../EmailService.java:39`)
```java
System.out.println(response.toString());
```

---

### LOW (4)

#### RL1. Node Service Dockerfiles Missing HEALTHCHECK
`services/certificate-signer/Dockerfile` and `services/certificate-api/Dockerfile` lack HEALTHCHECK.

#### RL2. Nginx Missing Resource Limits (`docker/docker-compose.yml:644`)
No `deploy.resources.limits` for nginx reverse proxy.

#### RL3. `dockerPushToRepo.sh` Reads Vault Password from Filesystem (Line 18)
```bash
cat /home/ops/vault_pass
```

#### RL4. Travis CI Encrypted Secrets (`.travis.yml:14-33`)
Multiple `secure:` variables - should migrate to GitHub Actions secrets.

---

## IMPROVEMENT METRICS

### Security Score: D -> B+
| Metric | Before | After |
|--------|--------|-------|
| Hardcoded credentials (main code) | 8 locations | 2 remaining (keycloak SPI, registry compose) |
| Injection vulnerabilities | 2 (path traversal, ES injection) | 0 |
| Authentication bypass risks | 3 | 0 |
| Disabled security features | 4 (CSRF, ES auth, Vault, service auth) | 1 (CSRF on API - intentional for REST) |

### Reliability Score: D -> A-
| Metric | Before | After |
|--------|--------|-------|
| `e.printStackTrace()` in production | 27+ | 0 |
| Exception messages exposed to clients | 15+ | 0 |
| Null pointer dereference risks | 5+ | 0 |
| Resource leaks | 4 | 0 |

### Maintainability Score: C -> B+
| Metric | Before | After |
|--------|--------|-------|
| Thread safety issues | 2 (critical) | 0 |
| Centralized error handling | None | `GlobalExceptionHandler` added |
| Raw types | Multiple | Fixed |
| Dead/commented code | Multiple blocks | Cleaned |

### Infrastructure Score: D -> B
| Metric | Before | After |
|--------|--------|-------|
| Outdated base images | 6 | 1 remaining (keycloak 14) |
| Unpinned image tags | 4 | 1 remaining (minio latest) |
| Containers running as root | 6 | 0 |
| Missing HEALTHCHECK | 6 | 2 remaining (node services) |

---

## RECOMMENDED NEXT STEPS (Priority Order)

### Immediate (P0)
1. **Rotate the SendInBlue API key** - it's been committed to git history
2. **Fix `java/registry/docker-compose.yml`** - hardcoded credentials + outdated image

### Short-term (P1)
3. Upgrade `deps/keycloak/Dockerfile` from 14.0.0 to 24.x
4. Add Redis authentication (`--requirepass`)
5. Change Keycloak from `start-dev` to `start` in production compose
6. Pin MinIO image version
7. Add HTTP security headers via Spring Security

### Medium-term (P2)
8. Enable Kafka SASL_SSL authentication
9. Add API rate limiting
10. Mask passwords in deploy script output
11. Add HEALTHCHECK to Node.js Dockerfiles
12. Remove placeholder secrets from application.yml defaults
13. Migrate Travis CI secrets to GitHub Actions
