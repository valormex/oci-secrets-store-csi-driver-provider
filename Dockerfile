# Stage 1: Build provider
FROM golang:1.24 AS builder

WORKDIR /workspace

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o provider ./cmd/server

# Stage 2: Runtime
FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /workspace/provider /opt/provider/bin/provider

USER nonroot:nonroot

ENTRYPOINT ["/opt/provider/bin/provider"]
