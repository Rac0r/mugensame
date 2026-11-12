// /now step 1b (inside the for loop over GitHub's repo list): attaches the
// latest commit to the matching entry in property.repos. property.it is the
// current raw GitHub repo, the body is GitHub's answer for its HEAD commit.
// commit stays null when GitHub answered with an error (e.g. an empty repo).
import groovy.json.JsonSlurper

final int MAX_FILES = 10

def repo = property.repos?.find { it.name == property.it.name }
if (repo != null) {
    repo.commit = null
    try {
        def data = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
        if (data instanceof Map && data.sha && data.commit) {
            def files = (data.files ?: []).collect { [filename: it.filename, additions: it.additions, deletions: it.deletions] }
            repo.commit = [message  : data.commit.message,
                           url      : data.html_url,
                           files    : files.take(MAX_FILES),
                           moreFiles: Math.max(files.size() - MAX_FILES, 0)]
        }
    } catch (ignored) {
    }
}
CONTINUE
