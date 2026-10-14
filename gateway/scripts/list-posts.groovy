// GET /admin/posts: turns GitHub's listing of src/posts into [{slug, sha}] for
// Markdown files. Error responses are left to github-errors.groovy.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res.statusCode >= 400) return CONTINUE

def entries = new JsonSlurper().parseText(res.bodyAsStringDecoded)
def posts = entries
        .findAll { it.type == 'file' && it.name.endsWith('.md') }
        .collect { [slug: it.name[0..-4], sha: it.sha] }
res.setBodyContent(JsonOutput.toJson(posts).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
