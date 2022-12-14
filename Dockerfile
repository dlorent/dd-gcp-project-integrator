FROM bash:5.2
RUN apk add --update --no-cache curl jq bash
COPY ./dd-gcp-project-integrator.sh /
ENTRYPOINT ["/dd-gcp-project-integrator.sh"]