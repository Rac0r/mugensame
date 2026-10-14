// After a `call:` to GET contents/<path>: stores the file's blob sha in
// property.sha, or null when GitHub answered with an error (e.g. 404 because
// the file does not exist). `call:` hides the status code, so the body decides.
import groovy.json.JsonSlurper

property.sha = null
try {
    def meta = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (meta instanceof Map && meta.sha) property.sha = meta.sha
} catch (ignored) {
}
CONTINUE
