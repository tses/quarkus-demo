package gr.ked.demo;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Counter;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * /api/info  — shows hostname (pod name), version, colour label.
 * Used during the demo to prove WHICH pod is serving the request
 * and to demonstrate traffic splitting (v1=blue, v2=green).
 */
@Path("/api/info")
@Produces(MediaType.APPLICATION_JSON)
public class InfoResource {

    @ConfigProperty(name = "app.version", defaultValue = "1.0.0")
    String version;

    @ConfigProperty(name = "app.colour", defaultValue = "blue")
    String colour;

    @Inject
    MeterRegistry registry;

    private Counter infoCounter;

    void onStart(@jakarta.enterprise.event.Observes io.quarkus.runtime.StartupEvent ev) {
        infoCounter = registry.counter("demo.info.requests.total");
    }

    @GET
    public Map<String, Object> info() {
        if (infoCounter != null) infoCounter.increment();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("app",      "ocp-demo-app");
        result.put("version",  version);
        result.put("colour",   colour);
        result.put("hostname", hostname());
        result.put("timestamp", Instant.now().toString());
        return result;
    }

    private String hostname() {
        // In OCP the hostname IS the pod name — perfect for the demo
        String envHostname = System.getenv("HOSTNAME");
        if (envHostname != null && !envHostname.isBlank()) return envHostname;
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
