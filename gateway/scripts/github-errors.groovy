// Runs on every admin API response. Rewrites GitHub error responses into this
// API's errors (spec: "Error mapping"); everything else - successes and
// Membrane's own 400/401 problem responses - passes unchanged.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res == null || res.statusCode < 400) return CONTINUE

def gh
try {
    gh = new JsonSlurper().parseText(res.bodyAsStringDecoded)
} catch (ignored) {
    return CONTINUE
}
if (!(gh instanceof Map) || !(gh.documentation_url ?: '').contains('docs.github.com')) return CONTINUE

int githubStatus = res.statusCode
int status
String error
switch (githubStatus) {
    case 409:
    case 422:
        status = 409
        error = 'Conflict: the file already exists or was changed in the meantime'
        break
    case 404:
        status = 404
        error = 'Not found'
        break
    case 401:
    case 403:
        status = 502
        error = 'GitHub rejected the request - check GITHUB_TOKEN (needs Contents: read and write on Rac0r/mugensame)'
        break
    default:
        status = 502
        error = 'GitHub error'
}

res.statusCode = status
res.statusMessage = [404: 'Not Found', 409: 'Conflict', 502: 'Bad Gateway'][status]
res.setBodyContent(JsonOutput.toJson([error: error, githubStatus: githubStatus, githubMessage: gh.message]).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
