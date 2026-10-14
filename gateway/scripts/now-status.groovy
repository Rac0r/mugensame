// /now step 3: src/_data/status.json as {text, updatedAt}; null when the file
// does not exist yet (GitHub's 404 JSON has no `text`).
import groovy.json.JsonSlurper

property.status = null
try {
    def s = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (s instanceof Map && s.text instanceof String) {
        property.status = [text: s.text, updatedAt: s.updatedAt]
    }
} catch (ignored) {
}
CONTINUE
