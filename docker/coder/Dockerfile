ARG CODER_VERSION
ARG HAKIM_PROVIDER_VERSION=0.1.0
ARG TARGETOS=linux
ARG TARGETARCH=amd64

FROM golang:1.24-alpine AS provider-builder

ARG HAKIM_PROVIDER_VERSION=0.1.0
ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /src/providers/hakim

COPY providers/hakim/go.mod providers/hakim/go.sum ./
RUN go mod download

COPY providers/hakim ./

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
  go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=${HAKIM_PROVIDER_VERSION}" -o /out/terraform-provider-hakim_v${HAKIM_PROVIDER_VERSION} .

FROM ghcr.io/coder/coder:v${CODER_VERSION}

ARG HAKIM_PROVIDER_VERSION=0.1.0
ARG TARGETOS=linux
ARG TARGETARCH=amd64

USER root

RUN apk add --no-cache \
  age \
  jq

COPY --from=provider-builder /out/terraform-provider-hakim_v${HAKIM_PROVIDER_VERSION} /opt/terraform-providers/registry.terraform.io/shekohex/hakim/${HAKIM_PROVIDER_VERSION}/${TARGETOS}_${TARGETARCH}/terraform-provider-hakim_v${HAKIM_PROVIDER_VERSION}
COPY docker/coder/terraformrc /etc/terraform.d/terraform.rc

RUN mkdir -p /etc/terraform.d && chown -R 1000:1000 /opt/terraform-providers /etc/terraform.d

ENV TF_CLI_CONFIG_FILE=/etc/terraform.d/terraform.rc

USER 1000:1000
