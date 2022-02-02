FROM crystallang/crystal:1.3.0-alpine

WORKDIR /app

# Add llvm deps.
RUN apk add --update --no-cache --force-overwrite \
      llvm10-dev llvm10-static g++ make sqlite-static


