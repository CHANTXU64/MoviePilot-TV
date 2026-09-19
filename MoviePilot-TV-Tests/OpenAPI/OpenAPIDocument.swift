import Foundation

@testable import MoviePilot_TV

enum OpenAPIDocumentError: Error, Equatable, CustomStringConvertible {
  case invalidJSON
  case missingPaths
  case unsupported(String)

  var description: String {
    switch self {
    case .invalidJSON:
      return "OpenAPI 文档不是合法 JSON 对象"
    case .missingPaths:
      return "OpenAPI 文档缺少 paths"
    case .unsupported(let reason):
      return "暂不支持的 OpenAPI 结构: \(reason)"
    }
  }
}

struct OpenAPIDocument: Equatable {
  let openAPIVersion: String
  let title: String?
  let version: String?
  let root: JSONValue
  let paths: [String: JSONValue]
  let components: JSONValue

  var operationCount: Int {
    paths.values.reduce(0) { count, item in
      count + OpenAPIPathIndex.httpMethods(in: item).count
    }
  }

  static func parse(data: Data) throws -> OpenAPIDocument {
    let root: JSONValue
    do {
      root = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw OpenAPIDocumentError.invalidJSON
    }
    return try parse(root: root)
  }

  static func parse(root: JSONValue) throws -> OpenAPIDocument {
    guard let object = root.objectValue else {
      throw OpenAPIDocumentError.invalidJSON
    }
    guard let paths = object["paths"]?.objectValue else {
      throw OpenAPIDocumentError.missingPaths
    }
    let info = object["info"]?.objectValue ?? [:]
    return OpenAPIDocument(
      openAPIVersion: object["openapi"]?.stringValue ?? object["swagger"]?.stringValue ?? "unknown",
      title: info["title"]?.stringValue,
      version: info["version"]?.stringValue,
      root: root,
      paths: paths,
      components: object["components"] ?? .object([:])
    )
  }

  func value(at jsonPointer: String) -> JSONValue? {
    OpenAPIRefResolver.value(at: jsonPointer, root: root)
  }
}

enum OpenAPIPathIndex {
  static let httpMethodNames: Set<String> = [
    "get", "put", "post", "delete", "options", "head", "patch", "trace",
  ]

  static func httpMethods(in pathItem: JSONValue) -> [String: JSONValue] {
    guard let object = pathItem.objectValue else { return [:] }
    var methods: [String: JSONValue] = [:]
    for (key, value) in object where httpMethodNames.contains(key) {
      methods[key] = value
    }
    return methods
  }

  static func normalizeAPIPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if let queryIndex = normalized.firstIndex(of: "?") {
      normalized = String(normalized[..<queryIndex])
    }
    if normalized.hasPrefix("/api/v1/") {
      normalized = String(normalized.dropFirst("/api/v1".count))
    } else if normalized == "/api/v1" {
      normalized = "/"
    }
    if !normalized.hasPrefix("/") {
      normalized = "/" + normalized
    }
    return normalized
  }

  static func segments(_ path: String) -> [String] {
    let normalized = normalizeAPIPath(path)
    if normalized == "/" { return [""] }
    return normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
  }

  static func isParameterSegment(_ segment: String) -> Bool {
    segment.hasPrefix("{") && segment.hasSuffix("}") && segment.count >= 3
  }

  static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
    let left = segments(lhs)
    let right = segments(rhs)
    guard left.count == right.count else { return false }
    for (leftSegment, rightSegment) in zip(left, right) {
      if leftSegment == rightSegment { continue }
      if leftSegment.isEmpty || rightSegment.isEmpty { return false }
      if isParameterSegment(leftSegment) || isParameterSegment(rightSegment) {
        continue
      }
      return false
    }
    return true
  }

  static func findPath(_ template: String, in paths: [String: JSONValue]) -> (path: String, item: JSONValue)? {
    let normalizedTemplate = normalizeAPIPath(template)
    if let exact = paths.first(where: { normalizeAPIPath($0.key) == normalizedTemplate }) {
      return (exact.key, exact.value)
    }
    for (path, item) in paths where pathsMatch(normalizedTemplate, path) {
      return (path, item)
    }
    return nil
  }

  static func familyPrefix(for path: String) -> String {
    let parts = normalizeAPIPath(path)
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)
    guard let first = parts.first, !first.isEmpty else { return "/" }
    return "/" + first
  }

  static func operationID(method: String, path: String) -> String {
    "\(method.uppercased()) \(normalizeAPIPath(path))"
  }
}

enum OpenAPIRefResolver {
  static func resolve(_ value: JSONValue, document: OpenAPIDocument, stack: [String] = []) throws
    -> JSONValue
  {
    guard let ref = value.objectValue?["$ref"]?.stringValue else {
      return value
    }
    if stack.contains(ref) {
      throw OpenAPIDocumentError.unsupported("循环引用 \(ref)")
    }
    guard let resolved = OpenAPIRefResolver.value(at: ref, root: document.root) else {
      throw OpenAPIDocumentError.unsupported("无法解析引用 \(ref)")
    }
    return try resolve(resolved, document: document, stack: stack + [ref])
  }

  static func value(at jsonPointer: String, root: JSONValue) -> JSONValue? {
    guard jsonPointer.hasPrefix("#/") else { return nil }
    var current = root
    let parts = jsonPointer.dropFirst(2).split(separator: "/").map {
      unescapePointer(String($0))
    }
    for part in parts {
      guard let object = current.objectValue, let next = object[part] else {
        return nil
      }
      current = next
    }
    return current
  }

  private static func unescapePointer(_ value: String) -> String {
    value.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
  }
}

struct OpenAPISchema: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case null
    case boolean
    case integer
    case number
    case string
    case array
    case object
    case union
    case opaque
    case recursive
    case unsupported(String)
  }

  var kind: Kind
  var types: Set<String>
  var nullable: Bool
  var required: Set<String>
  var properties: [String: OpenAPISchema]
  var items: OpenAPISchemaItem?
  var alternatives: [OpenAPISchema]
  var enumValues: [String]
  var deprecated: Bool
  var defaultValue: JSONValue?
  var additionalPropertiesAllowed: Bool
  var format: String?
}

final class OpenAPISchemaItem: Equatable, Sendable {
  let schema: OpenAPISchema

  init(_ schema: OpenAPISchema) {
    self.schema = schema
  }

  static func == (lhs: OpenAPISchemaItem, rhs: OpenAPISchemaItem) -> Bool {
    lhs.schema == rhs.schema
  }
}

extension OpenAPISchema {
  static var opaque: OpenAPISchema {
    OpenAPISchema(
    kind: .opaque,
    types: ["object"],
    nullable: true,
    required: [],
    properties: [:],
    items: nil,
    alternatives: [],
    enumValues: [],
    deprecated: false,
    defaultValue: nil,
    additionalPropertiesAllowed: true,
    format: nil
    )
  }

  static func unsupported(_ reason: String) -> OpenAPISchema {
    OpenAPISchema(
      kind: .unsupported(reason),
      types: [],
      nullable: true,
      required: [],
      properties: [:],
      items: nil,
      alternatives: [],
      enumValues: [],
      deprecated: false,
      defaultValue: nil,
      additionalPropertiesAllowed: true,
      format: nil
    )
  }

  var isUnsupported: Bool {
    if case .unsupported = kind { return true }
    return false
  }

  var unsupportedReason: String? {
    if case .unsupported(let reason) = kind { return reason }
    return nil
  }
}

enum OpenAPISchemaResolver {
  private static let maxDepth = 16
  private static let unsupportedKeywords = [
    "if", "then", "else", "not", "dependentSchemas", "patternProperties", "prefixItems",
  ]

  static func resolve(
    _ raw: JSONValue?,
    document: OpenAPIDocument,
    depth: Int = 0,
    stack: [String] = []
  ) -> OpenAPISchema {
    guard let raw else { return .opaque }
    if depth > maxDepth { return .opaque }

    if let ref = raw.objectValue?["$ref"]?.stringValue {
      if stack.contains(ref) {
        return OpenAPISchema(
          kind: .recursive,
          types: [],
          nullable: true,
          required: [],
          properties: [:],
          items: nil,
          alternatives: [],
          enumValues: [],
          deprecated: false,
          defaultValue: nil,
          additionalPropertiesAllowed: true,
          format: nil
        )
      }
      do {
        let resolved = try OpenAPIRefResolver.resolve(raw, document: document, stack: stack)
        return resolve(resolved, document: document, depth: depth, stack: stack + [ref])
      } catch {
        return .unsupported(String(describing: error))
      }
    }

    guard let object = raw.objectValue else { return .opaque }

    if let keyword = unsupportedKeywords.first(where: { object[$0] != nil }) {
      return .unsupported("包含 \(keyword)")
    }

    if let allOf = object["allOf"]?.arrayValue {
      return mergeAllOf(allOf, document: document, depth: depth, stack: stack, object: object)
    }

    if let anyOf = object["anyOf"]?.arrayValue ?? object["oneOf"]?.arrayValue {
      return mergeUnion(anyOf, document: document, depth: depth, stack: stack, object: object)
    }

    return schema(from: object, document: document, depth: depth, stack: stack)
  }

  private static func mergeAllOf(
    _ parts: [JSONValue],
    document: OpenAPIDocument,
    depth: Int,
    stack: [String],
    object: [String: JSONValue]
  ) -> OpenAPISchema {
    var merged = schema(from: object, document: document, depth: depth, stack: stack)
    for part in parts {
      let resolved = resolve(part, document: document, depth: depth + 1, stack: stack)
      if resolved.isUnsupported { return resolved }
      merged.properties.merge(resolved.properties) { _, new in new }
      merged.required.formUnion(resolved.required)
      merged.types.formUnion(resolved.types)
      merged.nullable = merged.nullable || resolved.nullable
      merged.deprecated = merged.deprecated || resolved.deprecated
      if merged.defaultValue == nil {
        merged.defaultValue = resolved.defaultValue
      }
      if resolved.kind == .object || merged.kind == .object {
        merged.kind = .object
      }
    }
    return merged
  }

  private static func mergeUnion(
    _ parts: [JSONValue],
    document: OpenAPIDocument,
    depth: Int,
    stack: [String],
    object: [String: JSONValue]
  ) -> OpenAPISchema {
    let resolvedParts = parts.map {
      resolve($0, document: document, depth: depth + 1, stack: stack)
    }
    if let unsupported = resolvedParts.first(where: \.isUnsupported) {
      return unsupported
    }

    let nonNull = resolvedParts.filter { !$0.types.subtracting(["null"]).isEmpty && $0.kind != .null }
    let nullable = resolvedParts.contains { $0.kind == .null || $0.types.contains("null") }
      || object["nullable"]?.boolValue == true

    if nonNull.count == 1, let only = nonNull.first {
      var schema = only
      schema.nullable = schema.nullable || nullable
      schema.deprecated = schema.deprecated || object["deprecated"]?.boolValue == true
      if schema.defaultValue == nil {
        schema.defaultValue = object["default"]
      }
      return schema
    }

    var types = Set(resolvedParts.flatMap(\.types))
    if nullable { types.insert("null") }
    var properties: [String: OpenAPISchema] = [:]
    var required: Set<String>?
    for part in nonNull where part.kind == .object {
      properties.merge(part.properties) { old, new in old }
      required = required.map { $0.intersection(part.required) } ?? part.required
    }

    return OpenAPISchema(
      kind: .union,
      types: types,
      nullable: nullable,
      required: required ?? [],
      properties: properties,
      items: nonNull.compactMap(\.items).first,
      alternatives: nonNull,
      enumValues: Array(Set(nonNull.flatMap(\.enumValues))).sorted(),
      deprecated: object["deprecated"]?.boolValue == true,
      defaultValue: object["default"],
      additionalPropertiesAllowed: true,
      format: object["format"]?.stringValue
    )
  }

  private static func schema(
    from object: [String: JSONValue],
    document: OpenAPIDocument,
    depth: Int,
    stack: [String]
  ) -> OpenAPISchema {
    let declaredTypes = declaredTypes(in: object)
    let nullable = declaredTypes.contains("null") || object["nullable"]?.boolValue == true
    let types = declaredTypes.isEmpty ? ["object"] : declaredTypes
    let kind = kind(for: types)

    var properties: [String: OpenAPISchema] = [:]
    if let rawProperties = object["properties"]?.objectValue {
      for (name, value) in rawProperties {
        properties[name] = resolve(value, document: document, depth: depth + 1, stack: stack)
      }
    }

    var items: OpenAPISchemaItem?
    if let rawItems = object["items"] {
      items = OpenAPISchemaItem(
        resolve(rawItems, document: document, depth: depth + 1, stack: stack)
      )
    }

    let additional: Bool
    if let additionalProperties = object["additionalProperties"] {
      switch additionalProperties {
      case .bool(let value):
        additional = value
      case .object:
        additional = true
      default:
        additional = true
      }
    } else {
      additional = true
    }

    let required = Set((object["required"]?.arrayValue ?? []).compactMap(\.stringValue))
    let enums = (object["enum"]?.arrayValue ?? []).compactMap(enumString)
    let format = object["format"]?.stringValue
    let isOpaqueObject =
      kind == .object && properties.isEmpty && additional
      && object["properties"] == nil
      && (object["title"]?.stringValue?.contains("Json") == true
        || format == "binary")

    return OpenAPISchema(
      kind: isOpaqueObject ? .opaque : kind,
      types: Set(types),
      nullable: nullable,
      required: required,
      properties: properties,
      items: items,
      alternatives: [],
      enumValues: enums,
      deprecated: object["deprecated"]?.boolValue == true,
      defaultValue: object["default"],
      additionalPropertiesAllowed: additional,
      format: format
    )
  }

  private static func declaredTypes(in object: [String: JSONValue]) -> Set<String> {
    var types: Set<String> = []
    switch object["type"] {
    case .string(let value):
      types.insert(value)
    case .array(let values):
      types.formUnion(values.compactMap(\.stringValue))
    default:
      break
    }
    if object["properties"] != nil || object["additionalProperties"] != nil {
      types.insert("object")
    }
    if object["items"] != nil {
      types.insert("array")
    }
    if object["enum"] != nil && types.isEmpty {
      types.insert("string")
    }
    return types
  }

  private static func kind(for types: Set<String>) -> OpenAPISchema.Kind {
    let nonNull = types.subtracting(["null"])
    if nonNull.count > 1 { return .union }
    switch nonNull.first {
    case "boolean":
      return .boolean
    case "integer":
      return .integer
    case "number":
      return .number
    case "string":
      return .string
    case "array":
      return .array
    case "object":
      return .object
    case "null":
      return .null
    default:
      return types.contains("null") ? .null : .opaque
    }
  }

  private static func enumString(_ value: JSONValue) -> String? {
    switch value {
    case .string(let value):
      return value
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .bool(let value):
      return value ? "true" : "false"
    default:
      return nil
    }
  }
}

struct OpenAPIParameter: Equatable {
  let name: String
  let location: String
  let required: Bool
  let deprecated: Bool
  let schema: OpenAPISchema
}

struct OpenAPIOperation: Equatable {
  let method: String
  let rawPath: String
  let normalizedPath: String
  let summary: String?
  let deprecated: Bool
  let parameters: [OpenAPIParameter]
  let requestBodyRequired: Bool
  let requestBodySchema: OpenAPISchema?
  let successContentType: String?
  let successSchema: OpenAPISchema?
  let innerDataSchema: OpenAPISchema?
  let unverifiedReason: String?

  var operationID: String {
    OpenAPIPathIndex.operationID(method: method, path: normalizedPath)
  }
}

enum OpenAPIOperationLoader {
  static func load(
    method: String,
    path: String,
    pathItem: JSONValue,
    document: OpenAPIDocument
  ) -> OpenAPIOperation? {
    let methods = OpenAPIPathIndex.httpMethods(in: pathItem)
    guard let operation = methods[method.lowercased()] else { return nil }

    do {
      let resolvedOperation = try OpenAPIRefResolver.resolve(operation, document: document)
      guard let object = resolvedOperation.objectValue else {
        return unverified(method: method, path: path, reason: "operation 不是对象")
      }

      let pathParameters = parameters(
        from: pathItem.objectValue?["parameters"]?.arrayValue ?? [],
        document: document
      )
      let operationParameters = parameters(
        from: object["parameters"]?.arrayValue ?? [],
        document: document
      )
      let mergedParameters = mergeParameters(pathParameters + operationParameters)

      let request = requestBody(from: object["requestBody"], document: document)
      let response = successResponse(from: object["responses"], document: document)
      let unverified = [request.schema, response.schema, response.inner]
        .compactMap(\.?.unsupportedReason)
        .first

      return OpenAPIOperation(
        method: method.uppercased(),
        rawPath: path,
        normalizedPath: OpenAPIPathIndex.normalizeAPIPath(path),
        summary: object["summary"]?.stringValue,
        deprecated: object["deprecated"]?.boolValue == true,
        parameters: mergedParameters,
        requestBodyRequired: request.required,
        requestBodySchema: request.schema,
        successContentType: response.contentType,
        successSchema: response.schema,
        innerDataSchema: response.inner,
        unverifiedReason: unverified
      )
    } catch {
      return unverified(method: method, path: path, reason: String(describing: error))
    }
  }

  static func load(
    method: String,
    template: String,
    document: OpenAPIDocument
  ) -> OpenAPIOperation? {
    guard let match = OpenAPIPathIndex.findPath(template, in: document.paths) else {
      return nil
    }
    return load(method: method, path: match.path, pathItem: match.item, document: document)
  }

  private static func unverified(method: String, path: String, reason: String) -> OpenAPIOperation {
    OpenAPIOperation(
      method: method.uppercased(),
      rawPath: path,
      normalizedPath: OpenAPIPathIndex.normalizeAPIPath(path),
      summary: nil,
      deprecated: false,
      parameters: [],
      requestBodyRequired: false,
      requestBodySchema: .unsupported(reason),
      successContentType: nil,
      successSchema: .unsupported(reason),
      innerDataSchema: nil,
      unverifiedReason: reason
    )
  }

  private static func parameters(
    from values: [JSONValue],
    document: OpenAPIDocument
  ) -> [OpenAPIParameter] {
    values.compactMap { value in
      let resolved: JSONValue
      do {
        resolved = try OpenAPIRefResolver.resolve(value, document: document)
      } catch {
        return nil
      }
      guard let object = resolved.objectValue,
        let name = object["name"]?.stringValue,
        let location = object["in"]?.stringValue
      else {
        return nil
      }
      return OpenAPIParameter(
        name: name,
        location: location,
        required: object["required"]?.boolValue ?? (location == "path"),
        deprecated: object["deprecated"]?.boolValue == true,
        schema: OpenAPISchemaResolver.resolve(object["schema"] ?? object["content"], document: document)
      )
    }
  }

  private static func mergeParameters(_ parameters: [OpenAPIParameter]) -> [OpenAPIParameter] {
    var seen: [String: OpenAPIParameter] = [:]
    for parameter in parameters {
      seen["\(parameter.location):\(parameter.name)"] = parameter
    }
    return seen.values.sorted {
      ($0.location, $0.name) < ($1.location, $1.name)
    }
  }

  private static func requestBody(
    from raw: JSONValue?,
    document: OpenAPIDocument
  ) -> (required: Bool, schema: OpenAPISchema?) {
    guard let raw else { return (false, nil) }
    let resolved: JSONValue
    do {
      resolved = try OpenAPIRefResolver.resolve(raw, document: document)
    } catch {
      return (false, .unsupported(String(describing: error)))
    }
    guard let object = resolved.objectValue else { return (false, nil) }
    let required = object["required"]?.boolValue ?? false
    let content = object["content"]?.objectValue ?? [:]
    let preferred =
      content["application/json"]
      ?? content["application/x-www-form-urlencoded"]
      ?? content.values.first
    return (
      required,
      OpenAPISchemaResolver.resolve(preferred?.objectValue?["schema"], document: document)
    )
  }

  private static func successResponse(
    from raw: JSONValue?,
    document: OpenAPIDocument
  ) -> (contentType: String?, schema: OpenAPISchema?, inner: OpenAPISchema?) {
    guard let responses = raw?.objectValue else { return (nil, nil, nil) }
    let preferredCode =
      ["200", "201", "202", "204"].first(where: { responses[$0] != nil })
      ?? responses.keys.sorted().first { $0.hasPrefix("2") }
    guard let code = preferredCode, let response = responses[code] else {
      return (nil, nil, nil)
    }
    let resolved: JSONValue
    do {
      resolved = try OpenAPIRefResolver.resolve(response, document: document)
    } catch {
      return (nil, .unsupported(String(describing: error)), nil)
    }
    let content = resolved.objectValue?["content"]?.objectValue ?? [:]
    let preferredType =
      ["application/json", "text/event-stream", "image/jpeg", "image/png", "image/webp"]
      .first(where: { content[$0] != nil })
      ?? content.keys.sorted().first
    guard let contentType = preferredType, let spec = content[contentType] else {
      return (nil, nil, nil)
    }
    let schema = OpenAPISchemaResolver.resolve(spec.objectValue?["schema"], document: document)
    let inner: OpenAPISchema?
    if let data = schema.properties["data"] {
      inner = data
    } else {
      inner = schema
    }
    return (contentType, schema, inner)
  }
}

extension JSONValue {
  fileprivate var boolValue: Bool? {
    switch self {
    case .bool(let value):
      return value
    default:
      return nil
    }
  }
}
