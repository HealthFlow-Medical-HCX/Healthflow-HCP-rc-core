FROM golang:1.22-alpine AS notification-service

RUN apk add make git gcc musl-dev
WORKDIR /app/notification-service

COPY . .
RUN go mod download
RUN make deps
RUN GOFLAGS=" -tags=musl" SPEC_FILE="./notification-service.yaml" make all

FROM alpine:3.19
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=notification-service /app/notification-service/notification-service /app/notification-service
USER appuser
EXPOSE 8765
CMD ["/app/notification-service", "--scheme", "http", "--port", "8765", "--host", "0.0.0.0"]
