# Serverino Routing and Params helpers

Add `serverino-router` to your project by running,

```
dub add serverino-router
```

## Routing

Helper functions available to map the URL pattern to the handler function. Make sure these route details are available for workers.

```d
@onWorkerStart void handleWorkerStart()
{
    postRoute!"/api/v1/folders"(&createFolderHandler);
    putRoute!"/api/v1/folders/:id:long"(&editFolderHandler);
    getRoute!"/api/v1/folders"(&listFoldersHandler);
    getRoute!"/api/v1/folders/:id:long"(&getFolderHandler);
    deleteRoute!"/api/v1/folders/:id:long"(&deleteFolderHandler);
    // ...
}
```

URL params are accessible as `pathParams`. For example, `pathParams["id"]` (string type but validated for the specified type). URL params are also available for `parseParams` function (See next section).

## Params

Helper functions to parse all types of params and convert into D struct/class. Similar to Ruby on Rails, all the params will be available in one place.

Example:

```d
struct LoginRequest
{
    string username;
    string password;
    string authenticityToken;
}

void loginHandler(Request request, Output output)
{
    auto params = parseParams!LoginRequest(request);
    // Use params.username, params.password and
    // params.authenticityToken as needed.
}
```

This function checks the params in the following order. If the Content
type is set to application/json then parses the body JSON.

1. Path params - Path params are only available if the routing helper
   from this library.
2. Query Params - Get params from Query.
3. JSON Params - Try to get params from JSON body.
4. Post params
5. Multipart formdata

**TODO**: Support for parsing files is still not available. Use `request.form` to read the files data.

Use `@paramName` UDA if the param name is different from the struct field name. For example,

```d
struct ArticleRequest
{
    string title;
    string content;
    @paramName("author_id") long authorId;
}
```

Use `@ignoreParam` to not try parsing that param. It may be a derived column or complex type and parsing may fail for that type. For example,

```d
struct DocumentRequest
{
    string name;
    string content;
    @ignoreParam ubyte[] contentBinary;
}
```

```d
auto params = parseParams!DocumentRequest(request);
// ..Process the params
params.contentBinary = content.representation;
// ...
```

### Why?

Handling all params from one place has its own advantageous. A few of them are listed below.

1. Easily support multiple ways to send data(JSON or Formdata).
2. Easy to switch web framework without changing all the handlers.
3. Discards the extra/unwanted fields and parses only whatever requested by the struct.
4. Simplifies the validations and params handling in Controllers(or Handlers).

## Other utilities

### Start Time.

When the router is used, it sets the `startTime` and uses it to print duration in the debug build. Use `nginx` logging to log the request and response details. If Auth or any other endpoint defined with higher priority, make sure to set the Start time by calling `setStartTime` function.

```d
@endpoint @priority(1000)
void sessionStartAndAuthHandler(Request request, Output output)
{
    setStartTime;
    // ... other logic
}
```

### Set Content Type

A utility function to set the content type.

```d
output.setContentType("application/json");
```

### Write JSON body

```d
@endpoint @route!"/ping"
void pingHandler(Request request, Output output)
{
    output.writeJsonBody(["ok": true]);
}
```

Or with Status code,

```d
auto note = Note.create(...);
output.writeJsonBody(note, HttpStatus.created);
```
