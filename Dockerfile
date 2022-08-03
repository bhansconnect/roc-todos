FROM alpine:latest

# Note: todos must already be built.
COPY todos /

EXPOSE 3000
CMD /todos