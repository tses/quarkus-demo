# Runtime image for the Quarkus fast-jar built by `mvn package`
# (target/quarkus-app/). Used by the Tekton pipeline (buildah) in ACT 5.
# BASE_IMAGE is an ARG so the base layer is easy to swap (ACS gate demo).
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/openjdk-17-runtime:1.24
FROM ${BASE_IMAGE}

ENV LANGUAGE='en_US:en'

# Apply OS security errata released after the base image was built
# (otherwise fixable RPM CVEs fail the ACS build-time policy)
USER 0
RUN microdnf -y update --nodocs --setopt=install_weak_deps=0 && microdnf clean all

# Dependencies first: they change less often than the app → better layer reuse
COPY --chown=185 target/quarkus-app/lib/ /deployments/lib/
COPY --chown=185 target/quarkus-app/*.jar /deployments/
COPY --chown=185 target/quarkus-app/app/ /deployments/app/
COPY --chown=185 target/quarkus-app/quarkus/ /deployments/quarkus/

EXPOSE 8080
USER 185
ENV JAVA_OPTS_APPEND="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"

ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]
