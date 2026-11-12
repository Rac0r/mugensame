// /now step 1: reduces GitHub's repo list to name, description, url, pushedAt
// and an empty commit slot (filled by now-commit.groovy).
// property.repos stays null when GitHub answered with an error.
import groovy.json.JsonSlurper

property.repos = null
try {
    def data = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (data instanceof List) {
        property.repos = data.collect { [name: it.name, description: it.description, url: it.html_url, pushedAt: it.pushed_at, commit: null] }
    }
} catch (ignored) {
}
CONTINUE
