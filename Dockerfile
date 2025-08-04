# Support setting various labels on the final image
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

# Blockscout build stage
FROM hexpm/elixir:1.17.0-erlang-27.0-alpine-3.19.1 AS blockscout-builder

RUN apk add --no-cache build-base git curl postgresql-dev inotify-tools npm nodejs gcompat bash

RUN git clone https://github.com/blockscout/blockscout.git /blockscout

WORKDIR /blockscout

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix compile

WORKDIR /blockscout/apps/block_scout_web/assets
RUN npm install || (cat /root/.npm/_logs/* && exit 1)
RUN npm run deploy

WORKDIR /blockscout
RUN mix phx.digest && MIX_ENV=prod mix release

RUN cp config/config_helper.exs $(find _build/prod/rel/blockscout/releases -maxdepth 1 -mindepth 1 -type d)/config_helper.exs


# Geth build stage
FROM golang:1.24-alpine AS builder

RUN apk add --no-cache gcc musl-dev linux-headers git

COPY go.mod /go-ethereum/
COPY go.sum /go-ethereum/
RUN cd /go-ethereum && go mod download

ADD . /go-ethereum
RUN cd /go-ethereum && go run build/ci.go install -static ./cmd/geth

# Final image (Elixir base, not plain Alpine)
FROM hexpm/elixir:1.17.0-erlang-27.0-alpine-3.19.1

RUN apk add --no-cache ca-certificates libstdc++ postgresql-client su-exec bash curl

COPY --from=builder /go-ethereum/build/bin/geth /usr/local/bin/
COPY --from=blockscout-builder /blockscout/_build/prod /blockscout/_build/prod
COPY --from=blockscout-builder /blockscout /blockscout

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8545 8546 30303 4000
ENTRYPOINT ["/bin/sh", "/start.sh"]