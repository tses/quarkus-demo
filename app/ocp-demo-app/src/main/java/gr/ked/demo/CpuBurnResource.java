package gr.ked.demo;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * /api/burn?seconds=10
 *
 * Intentionally burns CPU on all available cores for N seconds.
 * Used during the HPA demo to trigger auto-scaling:
 *   watch: kubectl top pods  →  pods > CPU threshold  →  new pod spawns
 *
 * The trick: spawn a thread per CPU core, each doing tight math loops.
 */
@Path("/api/burn")
@Produces(MediaType.APPLICATION_JSON)
public class CpuBurnResource {

    private static final int MAX_SECONDS = 120;

    @Inject
    MeterRegistry registry;

    @GET
    public Map<String, Object> burn(
            @QueryParam("seconds") @DefaultValue("30") int seconds) {

        seconds = Math.min(seconds, MAX_SECONDS); // safety cap

        int cores = Runtime.getRuntime().availableProcessors();
        long durationMs = (long) seconds * 1000;
        long end = System.currentTimeMillis() + durationMs;

        // Record the burn in metrics so Prometheus/Grafana shows a spike
        Timer.Sample sample = Timer.start(registry);

        // Spin up one thread per core — saturates CPU
        Thread[] burners = new Thread[cores];
        for (int i = 0; i < cores; i++) {
            burners[i] = new Thread(() -> {
                // tight math loop — not IO-bound, can't be parked
                double x = 0;
                while (System.currentTimeMillis() < end) {
                    x += Math.sqrt(Math.random() * 999999);
                }
            });
            burners[i].setDaemon(true);
            burners[i].start();
        }

        // Wait for all burners (blocks the HTTP thread, which is fine — demo only)
        for (Thread t : burners) {
            try { t.join(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        }

        sample.stop(registry.timer("demo.cpu.burn.duration"));

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("burned_seconds", seconds);
        result.put("cores_used",     cores);
        result.put("hostname",       System.getenv().getOrDefault("HOSTNAME", "unknown"));
        result.put("message",        "CPU burn complete — check HPA / top pods");
        return result;
    }
}
