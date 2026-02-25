package gr.ked.demo;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Liveness;
import org.eclipse.microprofile.health.Readiness;

/**
 * Custom health checks visible at /q/health/live and /q/health/ready.
 * In the demo: show these in the OCP console Topology → pod → Routes.
 */
public class HealthChecks {

    @Liveness
    @ApplicationScoped
    public static class AppLiveness implements HealthCheck {
        @Override
        public HealthCheckResponse call() {
            return HealthCheckResponse.named("app-live")
                    .up()
                    .withData("hostname", System.getenv().getOrDefault("HOSTNAME", "unknown"))
                    .build();
        }
    }

    @Readiness
    @ApplicationScoped
    public static class AppReadiness implements HealthCheck {
        @Override
        public HealthCheckResponse call() {
            // Could check DB connectivity here — keeping simple for demo clarity
            return HealthCheckResponse.named("app-ready")
                    .up()
                    .withData("status", "all systems nominal")
                    .build();
        }
    }
}
