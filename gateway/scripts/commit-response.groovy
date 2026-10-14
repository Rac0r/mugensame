// Replaces GitHub's successful commit response with this API's result:
// status property.successStatus, body property.result (with `commit` filled
// in when present), no body for 204. Errors are left to github-errors.groovy.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res.statusCode >= 400) return CONTINUE

int status = property.successStatus as int
res.statusCode = status
res.statusMessage = [200: 'OK', 201: 'Created', 204: 'No Content'][status]
if (status == 204) {
    res.setBodyContent(new byte[0])
    return CONTINUE
}

def result = new LinkedHashMap(property.result)
if (result.containsKey('commit')) {
    result.commit = new JsonSlurper().parseText(res.bodyAsStringDecoded).commit?.sha
}
res.setBodyContent(JsonOutput.toJson(result).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
