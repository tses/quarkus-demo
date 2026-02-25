package gr.ked.demo;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.*;

@QuarkusTest
public class InfoResourceTest {

    @Test
    public void testInfoEndpoint() {
        given()
            .when().get("/api/info")
            .then()
            .statusCode(200)
            .body("app",     equalTo("ocp-demo-app"))
            .body("hostname", notNullValue())
            .body("version",  notNullValue());
    }

    @Test
    public void testHealthLive() {
        given()
            .when().get("/q/health/live")
            .then()
            .statusCode(200)
            .body("status", equalTo("UP"));
    }

    @Test
    public void testHealthReady() {
        given()
            .when().get("/q/health/ready")
            .then()
            .statusCode(200)
            .body("status", equalTo("UP"));
    }

    @Test
    public void testSwaggerUI() {
        given()
            .when().get("/q/openapi")
            .then()
            .statusCode(200);
    }
}
