FROM alpine:latest

# TODO: maybe one day have docker actually build this todo app.
# Note: todos must already be built.
COPY todos /
CMD /todos