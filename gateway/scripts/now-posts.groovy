// /now step 2 (only runs when the feed was XML, after xml2Json): the three
// newest items. xml2Json turns a single <item> into an object, not a list.
import groovy.json.JsonSlurper

property.posts = null
try {
    def item = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)?.rss?.channel?.item
    def items = item == null ? [] : (item instanceof List ? item : [item])
    property.posts = items.take(3).collect { [title: it.title, url: it.link, date: it.pubDate] }
} catch (ignored) {
}
CONTINUE
