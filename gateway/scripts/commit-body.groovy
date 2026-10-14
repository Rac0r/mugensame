// Builds the request body for GitHub's "create or update file contents" and
// "delete a file" endpoints from properties set by the route's own script:
//   property.message  commit message
//   property.content  String or byte[]; absent for deletes
//   property.sha      current blob sha; absent/null when creating
import groovy.json.JsonOutput

def body = [message: property.message, branch: System.getenv('GITHUB_BRANCH') ?: 'main']
if (property.content != null) {
    byte[] bytes = property.content instanceof byte[] ? property.content : property.content.toString().getBytes('UTF-8')
    body.content = bytes.encodeBase64().toString()
}
if (property.sha) body.sha = property.sha

exchange.request.setBodyContent(JsonOutput.toJson(body).getBytes('UTF-8'))
exchange.request.header.setContentType('application/json')
CONTINUE
