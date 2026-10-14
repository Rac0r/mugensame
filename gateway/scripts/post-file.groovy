// Prepares a commit of src/posts/<slug>.md for the commit pipeline:
//   POST   /admin/posts         slug derived from the title (same rules as the
//                               site's slugify filter in eleventy.config.js)
//   PUT    /admin/posts/{slug}  slug from the path (property.slug), file replaced
//   DELETE /admin/posts/{slug}  slug from the path, no content
// Answers 400 itself for an unusable slug or an impossible date.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeParseException

String slugify(String s) {
    s.toLowerCase().trim().replaceAll(/[^a-z0-9]+/, '-').replaceAll(/(^-|-$)+/, '')
}

// A JSON string is a valid YAML double-quoted scalar, so this escapes : # " etc.
String yamlString(Object s) {
    JsonOutput.toJson(s.toString())
}

def badRequest = { String message ->
    Response.statusCode(400).contentType('application/json')
            .body(JsonOutput.toJson([error: message])).build()
}

String method = exchange.request.method
def input = method == 'DELETE' ? null : new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
String slug = method == 'POST' ? slugify(input.title) : property.slug

if (!(slug ==~ /[a-z0-9]+(-[a-z0-9]+)*/)) {
    return badRequest("No usable slug '${slug}': titles need at least one letter or digit, path slugs look like 'my-post'".toString())
}

property.slug = slug
property.path = "src/posts/${slug}.md".toString()

if (method == 'DELETE') {
    property.message = "admin: delete post ${slug}".toString()
    property.successStatus = 204
    return CONTINUE
}

// PUT replaces the whole file, so a missing date would re-date the post and a
// missing draft flag would publish a draft - both must be sent explicitly.
if (method == 'PUT' && (input.date == null || input.draft == null)) {
    return badRequest("PUT replaces the whole post: also send 'date' and 'draft' (GET /admin/posts/${slug} shows the current values)".toString())
}

String date
try {
    date = (input.date ? LocalDate.parse(input.date) : LocalDate.now(ZoneOffset.UTC)).toString()
} catch (DateTimeParseException ignored) {
    return badRequest("Invalid date '${input.date}', expected an existing day as YYYY-MM-DD".toString())
}

def lines = ['---',
             "title: ${yamlString(input.title)}".toString(),
             "description: ${yamlString(input.description)}".toString(),
             "date: ${date}".toString()]
if (input.draft) lines << 'draft: true'
if (input.tags) {
    lines << 'tags:'
    input.tags.each { lines << "  - ${yamlString(it)}".toString() }
}
lines << '---' << '' << input.body.stripTrailing() << ''

property.content = lines.join('\n')
property.message = "admin: ${method == 'POST' ? 'create' : 'update'} post ${slug}".toString()
property.successStatus = method == 'POST' ? 201 : 200
property.result = [slug: slug, path: property.path, commit: null]
CONTINUE
