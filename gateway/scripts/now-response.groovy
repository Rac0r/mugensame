// /now: merges the three sources into the response. A source that failed is null.
import groovy.json.JsonOutput
import java.time.Instant
import java.time.temporal.ChronoUnit

def now = [generatedAt: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
           status     : property.status,
           repos      : property.repos,
           posts      : property.posts]
Response.ok()
        .contentType('application/json')
        .body(JsonOutput.prettyPrint(JsonOutput.toJson(now)))
        .build()
