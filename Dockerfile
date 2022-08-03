FROM rust:1.62.1-bullseye as builder

RUN cargo install sqlx-cli
COPY migrations /app/migrations
WORKDIR /app/
RUN echo "DATABASE_URL=\"sqlite:todos.db\"" > .env
RUN sqlx database setup

FROM debian:latet
# TODO: maybe one day have docker actually build this todo app.
# Note: todos must already be built.
WORKDIR /app/
COPY --from=builder /app/.env ./
COPY --from=builder /app/todos.db ./
COPY todos ./
CMD ["./todos"]
