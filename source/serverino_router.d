module serverino_params;

import std.typecons;
import std.conv;
import std.traits;
import std.meta;
import std.logger;
import std.algorithm.searching : canFind;
import std.datetime : Clock, UTC, SysTime;
import std.string;
import std.json;

import serverino;
import json_serialization;

public import http_status;

alias Routes = void function(Request, Output)[string];
alias HandlerFunc = void function(Request, Output);

// These will be filled once the routes are defined
string[string] pathParams;

// To track the request duration during debug mode
SysTime startTime;

// Below routes will be filled if Route helpers are used.
Routes postStaticRoutes = null;
Routes postRoutes = null;
Routes putStaticRoutes = null;
Routes putRoutes = null;
Routes getStaticRoutes = null;
Routes getRoutes = null;
Routes deleteStaticRoutes = null;
Routes deleteRoutes = null;

/// UDA.
struct paramName
{
    string name;
}

public enum ignoreParam;  /// UDA. struct members with @ignoreParam will be ignored while parsing params 

/* Utility function to set the content type
 * ```d
 * output.setContentType("application/json");
 * ```
 */
void setContentType(Output output, string type)
{
    output.addHeader("Content-Type", type);
}

/* Utility function to write JSON to output
 * ```d
 * @endpoint @route!"/ping"
 * void pingHandler(Request request, Output output)
 * {
 *     output.writeJsonBody(["ok": true]);
 * }
 * ```
 */
void writeJsonBody(T)(Output output, T data, HttpStatus status = HttpStatus.ok)
{
    output.status = status;
    output.setContentType("application/json");
    output.write(data.serializeToJSONValueString);
}

bool validParamType(string param, string type)
{
    // TODO: Add more types
    alias types = AliasSeq!(ulong, int, string);

    try
    {
        static foreach(t; types)
        {
            mixin(`
                if (type == "` ~ t.stringof ~ `")
                {
                    param.to!` ~ t.stringof ~ `;
                    return true;
                }
            `);
        }

        return false;
    }
    catch (Exception)
        return false;
}

Nullable!(string[string]) matchedPathParams(string pattern, string path)
{
    string[string] params;

    // Split the pattern and path into parts
    auto patternParts = pattern.strip("/").split("/");
    auto pathParts = path.strip("/").split("/");
    auto starPattern = pattern.canFind("*");

    // Pattern group should match the given path parts
    if (patternParts.length != pathParts.length && !starPattern)
        return Nullable!(string[string]).init;

    // For each pattern parts, if it starts with `:`
    // then collect it as path param else path part should
    // match the respective part of the pattern.
    foreach(idx, p; patternParts)
    {
        if (p[0] == ':')
        {
            // Check if the type is provided, try to convert to
            // that type. Return false if it is not a valid type.
            // Advantage: We can have two routes for each type
            // `/api/v1/shares/:id:ulong` and `/api/v1/shares/:folder_name`
            auto patternAndType = p[1..$].split(":");
            if (patternAndType.length > 1 && !validParamType(patternAndType[0], patternAndType[1]))
                return Nullable!(string[string]).init;

            if (pathParts.length <= idx)
                return Nullable!(string[string]).init;

            params[patternAndType[0]] = pathParts[idx];
        }
        else if (p[0] == '*')
        {
            if (p.length > 1)
            {
                // If name is provided with *, then collect
                // the rest of the path parts as current param
                auto param = pathParts[idx..$].join("/");
                if (param.empty)
                    return Nullable!(string[string]).init;

                params[p[1..$]] = param;
            }
            // No need to compare the rest of the path parts
            break;
        }
        else if(pathParts.length <= idx || p != pathParts[idx])
            return Nullable!(string[string]).init;
    }

    return params.nullable;
}

bool pathMatch(const(Request) req, string pattern)
{
    auto data = matchedPathParams(pattern, req.path);

    if (!data.isNull)
        pathParams = data.get;

    return !data.isNull;
}

/* Define the post route in worker's scope.
 *
 * ```d
 * @onWorkerStart void handleWorkerStart()
 * {
 *   defineRoutes;
 *   // Other things in Worker
 * }
 *
 * void defineRoutes()
 * {
 *     postRoute!"/api/v1/folders"(&createFolderHandler);
 *     postRoute!"/api/v1/folders/:id:long/notes"(&createNoteHandler);
 * }
 * ```
 */
void postRoute(string pattern)(HandlerFunc handler)
{
    static if(pattern.canFind(":") || pattern.canFind("*"))
        postRoutes[pattern] = handler;
    else
        postStaticRoutes[pattern] = handler;
}

/* Refer postRoute for usage.
 *
 * ```d
 * putRoute!"/api/v1/folders/:id:long"(&editFolderHandler);
 * ```
 */
void putRoute(string pattern)(HandlerFunc handler)
{
    static if(pattern.canFind(":") || pattern.canFind("*"))
        putRoutes[pattern] = handler;
    else
        putStaticRoutes[pattern] = handler;
}

/* Refer postRoute for usage.
 *
 * ```d
 * getRoute!"/api/v1/folders"(&listFoldersHandler);
 * ```
 */
void getRoute(string pattern)(HandlerFunc handler)
{
    static if(pattern.canFind(":") || pattern.canFind("*"))
        getRoutes[pattern] = handler;
    else
        getStaticRoutes[pattern] = handler;
}

/* Refer postRoute for usage.
 *
 * ```d
 * deleteRoute!"/api/v1/folders/:id:long"(&deleteFolderHandler);
 * ```
 */
void deleteRoute(string pattern)(HandlerFunc handler)
{
    static if(pattern.canFind(":") || pattern.canFind("*"))
        deleteRoutes[pattern] = handler;
    else
        deleteStaticRoutes[pattern] = handler;
}

void findRouteHandler(Request request, Output output, Routes staticRoutes, Routes routes)
{
    auto handler = request.path in staticRoutes;
    if (handler !is null)
        return (*handler)(request, output);

    foreach(route; routes.byKeyValue)
    {
        if (request.pathMatch(route.key))
            return (*(route.value))(request, output);
    }
}

void setStartTime()
{
    // Set only if no other routes initialized startTime
    if (startTime == SysTime())
        startTime = Clock.currTime(UTC());
}

@endpoint
void routesHandler(Request request, Output output)
{
    setStartTime;

    if (request.method == Request.Method.Post)
        findRouteHandler(request, output, postStaticRoutes, postRoutes);
    else if (request.method == Request.Method.Put)
        findRouteHandler(request, output, putStaticRoutes, putRoutes);
    else if (request.method == Request.Method.Get)
        findRouteHandler(request, output, getStaticRoutes, getRoutes);
    else if (request.method == Request.Method.Delete)
        findRouteHandler(request, output, deleteStaticRoutes, deleteRoutes);

    debug
    {
        auto duration = (Clock.currTime(UTC()) - startTime);
        tracef("Response %s %s - %s (%s)", request.method, request.path, output.status, duration.toString);
    }
}

string getParamName(T, string member)()
{
    static if (getUDAs!(__traits(getMember, T, member), paramName).length > 0)
        return getUDAs!(__traits(getMember, T, member), paramName)[0].name;

    return member;
}

bool isParamIgnored(T, string member)()
{
    return hasUDA!(__traits(getMember, T, member), ignoreParam);
}

class ParamsParseException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

string nullableType(T)()
{
    import std.string;
    string type = T.stringof;
    auto parts = type.split("!");
    if (parts.length > 1)
        return parts[1];

    return parts[0];
}

Nullable!T getParam(T)(Request req, string key, JSONValue bodyParams = JSONValue(), string[string] pathParams = string[string].init)
{
    Nullable!T value;
    auto pathParamValue = key in pathParams;
    auto bodyParam = key in bodyParams;

    if (pathParamValue !is null)
        value = (*pathParamValue).to!(T);
    else if (req.get.has(key))
        value = req.get.read(key).to!(T);
    else if (bodyParam !is null)
        value = (*bodyParam).get!(T);
    else if (req.post.has(key))
        value = req.post.read(key).to!(T);
    else if (req.form.has(key))
    {
        auto fd = req.form.read(key);
        if (!fd.isFile)
            value = fd.data.to!(T).nullable;
    }

    return value;
}

/* Parse all params including URL params. Provides uniform way to
 * provide access to Params similar to Ruby on Rails. JSON params
 * are also supported.
 *
 * ```d
 * struct LoginRequest
 * {
 *     string username;
 *     string password;
 *     string authenticityToken;
 * }
 *
 * void loginHandler(Request request, Output output)
 * {
 *     auto params = parseParams!LoginRequest(request);
 *     // Use params.username, params.password and
 *     // params.authenticityToken as needed.
 * }
 * ```
 *
 * This function checks the params in the following order. If the Content
 * type is set to application/json then parses the body JSON.
 *
 * 1) Path params - Path params are only available if the routing helper
 *    from this library.
 * 2) Query Params - Get params from Query.
 * 3) JSON Params - Try to get params from JSON body.
 * 4) Post params
 * 5) Multipart formdata
 *
 * No support for files params. Use `request.form` to read the files data.
 */
T parseParams(T)(Request req)
{
    static if (is(T == struct))
        T params;
    else
        T params = new T;

    JSONValue bodyJson;
    if (req.body.contentType == "application/json")
    {
        try
            bodyJson = parseJSON(req.body.data.to!string);
        catch (Exception)
            throw new ParamsParseException("Invalid JSON");
    }

    alias fieldTypes = FieldTypeTuple!(T);
    alias fieldNames = FieldNameTuple!(T);

    static foreach(idx, fieldName; fieldNames)
    {
        static if (!isParamIgnored!(T, fieldName))
        {
            // Param name same as memberName unless @paramName
            // attribute added to the member.
            enum name = getParamName!(T, fieldName);

            static if(__traits(hasMember, __traits(getMember, params, memberName), "isNull"))
                enum type = nullableType!(fieldTypes[idx]);
            else
                enum type = fieldTypes[idx].stringof;

            // Example conversion:
            // try
            // {
            //     auto param = getParam!(int)(req, "page", bodyJson, pathParams);
            //     if (!param.isNull)
            //         params.page = param.get;
            // }
            // catch (Exception)
            // {
            //     throw new ParamsParseException("Failed to parse \"page\". Invalid content");
            // }
            mixin(`
                try
                {
                    auto param = getParam!(` ~ type ~ `)(req, "` ~ name ~ `", bodyJson, pathParams);
                    if (!param.isNull)
                         params.` ~ fieldName ~ ` = param.get;
                }
                catch (Exception)
                {
                    throw new ParamsParseException("Failed to parse \"` ~ name ~ `\". Invalid content");
                }
            `);
        }

    }

    return params;
}
