// PUT /admin/status: prepares src/_data/status.json for the commit pipeline
// (see commit-body.groovy). The body was already checked by schemas/status.json.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.time.Instant
import java.time.temporal.ChronoUnit

def input = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
def file = [text: input.text, updatedAt: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()]

property.path = 'src/_data/status.json'
property.content = JsonOutput.prettyPrint(JsonOutput.toJson(file)) + '\n'
property.message = 'admin: update status'
property.successStatus = 200
property.result = file
CONTINUE
