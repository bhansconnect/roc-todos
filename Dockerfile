FROM alpine:latest

# Note: todos must already be built.
COPY todos /
CMD /todos