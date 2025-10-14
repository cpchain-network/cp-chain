FROM golang:1.22.7-alpine3.20 AS builder

ARG VERSION=v0.0.0

RUN apk add --no-cache make gcc musl-dev linux-headers git jq bash

# build op-node with the shared go.mod & go.sum files
COPY ./cp-node /app/cp-node
COPY ./cp-service /app/cp-service
COPY ./common /app/common
COPY ./cp-supervisor /app/cp-supervisor
COPY ./cp-deployer /app/cp-deployer

COPY ./go.mod /app/go.mod
COPY ./go.sum /app/go.sum

WORKDIR /app/cp-node

RUN go mod tidy

ARG TARGETOS TARGETARCH

RUN go build -o bin/cp-node ./cmd/main.go

FROM alpine:3.21

COPY --from=builder /app/cp-node/bin/cp-node /usr/local/bin

CMD ["cp-node"]
