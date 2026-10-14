// PUT /admin/images/{filename}: checks name, type and size, then prepares the
// commit of src/images/<filename>. Creating only - an existing file gives 409.
import groovy.json.JsonOutput

def reject = { int status, String message ->
    Response.statusCode(status).contentType('application/json')
            .body(JsonOutput.toJson([error: message])).build()
}

String name = property.filename
if (!(name ==~ /[a-z0-9][a-z0-9._-]*\.(png|jpe?g|gif|webp|svg)/)) {
    return reject(400, "Invalid filename '${name}': lowercase letters, digits, . _ - and an image extension".toString())
}
String type = exchange.request.header.contentType ?: ''
if (!type.startsWith('image/')) {
    return reject(400, "Content-Type must be image/*, got '${type}'".toString())
}
byte[] bytes = exchange.request.body.content
if (bytes.length == 0) return reject(400, 'Empty image')
if (bytes.length > 5 * 1024 * 1024) return reject(413, 'Image is larger than 5 MB')

property.path = "src/images/${name}".toString()
property.content = bytes
property.message = "admin: add image ${name}".toString()
property.successStatus = 201
property.result = [url: "/mugensame/images/${name}".toString()]
CONTINUE
