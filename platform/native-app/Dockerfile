# Release gate validation image; this does not package the macOS native app.
FROM node@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920

RUN mkdir -p /app/sbom && chown -R node:node /app
WORKDIR /app

COPY --chown=node:node component.json README.md ./
COPY --chown=node:node sbom/native-app.cdx.json ./sbom/native-app.cdx.json

USER node

CMD ["sh", "-c", "test -f component.json && test -f sbom/native-app.cdx.json"]
