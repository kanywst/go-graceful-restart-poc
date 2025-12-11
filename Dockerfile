FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -o /server ./cmd/server/

FROM alpine:latest

RUN apk update && apk add curl bash

WORKDIR /root/app

COPY --from=builder /server /root/app/server
COPY scripts/restart.sh /root/app/scripts/restart.sh

RUN chmod +x /root/app/scripts/restart.sh

CMD ["tail", "-f", "/dev/null"]
