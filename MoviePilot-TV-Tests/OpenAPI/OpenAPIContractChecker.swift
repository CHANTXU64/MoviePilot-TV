import Foundation

@testable import MoviePilot_TV

enum OpenAPIFindingSeverity: String, Equatable {
  case failure
  case review
  case info
}

enum OpenAPIFindingKind: String, Equatable, CaseIterable {
  case pathMissing
  case methodMissing
  case undeclaredParameter
  case missingRequiredParameter
  case parameterTypeMismatch
  case undeclaredBodyField
  case missingRequiredBodyField
  case bodyFieldTypeMismatch
  case responseFieldMissing
  case responseFieldNullability
  case responseFieldTypeMismatch
  case responseStructureChanged
  case newWritableField
  case defaultChanged
  case deprecated
  case relatedEndpointAdded
  case unusedEndpoint
  case coverageGap
  case unverifiedSchema
  case fetchFailed
  case catalogMissing
}

struct OpenAPIFinding: Equatable {
  let severity: OpenAPIFindingSeverity
  let kind: OpenAPIFindingKind
  let operationID: String
  let path: String
  let message: String
  var excepted: Bool = false
}

struct OpenAPIException: Equatable {
  let id: String
  let operation: String
  let kind: OpenAPIFindingKind
  let path: String?
  let reason: String
}

struct OpenAPICoverageGap: Equatable {
  enum Kind: String {
    case catalogWithoutContract
    case catalogWithoutBehavioralTest
    case pathOnly
    case opaqueSchema
    case relatedUnevaluated
    case sourceUnregistered
    case roundTripOmission
  }

  let kind: Kind
  let operationID: String
  let message: String
}

struct OpenAPIContractReport: Equatable {
  var backendVersion: String?
  var openAPIVersion: String?
  var title: String?
  var findings: [OpenAPIFinding] = []
  var coverageGaps: [OpenAPICoverageGap] = []
  var checkedOperations: Int = 0
  var usedFamilyUnusedCount: Int = 0

  var failures: [OpenAPIFinding] {
    findings.filter { $0.severity == .failure && !$0.excepted }
  }

  var reviews: [OpenAPIFinding] {
    findings.filter { $0.severity == .review && !$0.excepted }
  }

  var infos: [OpenAPIFinding] {
    findings.filter { $0.severity == .info || $0.excepted }
  }

  var hasBlockingFindings: Bool {
    !failures.isEmpty || !reviews.isEmpty
  }

  var formattedDescription: String {
    var lines: [String] = []
    lines.append("OpenAPI 契约检查")
    if let title {
      lines.append("文档: \(title) \(backendVersion ?? "") (\(openAPIVersion ?? "unknown"))")
    }
    lines.append("已检查 TV 接口 \(checkedOperations) 个；同族未使用接口 \(usedFamilyUnusedCount) 个。")
    func appendSection(_ title: String, _ items: [String]) {
      guard !items.isEmpty else { return }
      lines.append("")
      lines.append(title)
      lines.append(contentsOf: items.map { "- \($0)" })
    }
    appendSection(
      "失败 \(failures.count)",
      failures.map { "[\($0.kind.rawValue)] \($0.operationID) \($0.path): \($0.message)" }
    )
    appendSection(
      "待审查 \(reviews.count)",
      reviews.map { "[\($0.kind.rawValue)] \($0.operationID) \($0.path): \($0.message)" }
    )
    appendSection(
      "覆盖缺口 \(coverageGaps.count)",
      coverageGaps.map { "[\($0.kind.rawValue)] \($0.operationID): \($0.message)" }
    )
    let visibleInfo = infos.prefix(30).map {
      "[\($0.kind.rawValue)] \($0.operationID) \($0.path): \($0.message)"
    }
    appendSection("信息 \(infos.count)", Array(visibleInfo))
    if infos.count > 30 {
      lines.append("- … 其余 \(infos.count - 30) 条信息已省略")
    }
    return lines.joined(separator: "\n")
  }
}

enum OpenAPIContractChecker {
  static func check(
    live: OpenAPIDocument,
    baseline: OpenAPIDocument?,
    catalog: [TVAPIOperation] = TVAPIContractCatalog.operations,
    exceptions: [OpenAPIException] = [],
    sourceGaps: [OpenAPICoverageGap] = []
  ) -> OpenAPIContractReport {
    var report = OpenAPIContractReport(
      backendVersion: live.version,
      openAPIVersion: live.openAPIVersion,
      title: live.title
    )
    report.checkedOperations = catalog.count

    var liveUsedIDs: Set<String> = []
    for operation in catalog {
      liveUsedIDs.insert(operation.operationID)
      checkCatalogOperation(operation, against: live, baseline: baseline, into: &report)
    }

    let related = relatedUnusedOperations(in: live, usedIDs: liveUsedIDs)
    report.usedFamilyUnusedCount = related.count
    let baselineRelated: Set<String>
    if let baseline {
      let baselineUsed = Set(catalog.compactMap { catalogOperation in
        OpenAPIOperationLoader.load(
          method: catalogOperation.method,
          template: catalogOperation.pathTemplate,
          document: baseline
        )?.operationID
      })
      baselineRelated = Set(
        relatedUnusedOperations(in: baseline, usedIDs: baselineUsed).map(\.operationID)
      )
    } else {
      baselineRelated = Set(related.map(\.operationID))
    }

    for unused in related {
      if baselineRelated.contains(unused.operationID) {
        report.findings.append(
          OpenAPIFinding(
            severity: .info,
            kind: .unusedEndpoint,
            operationID: unused.operationID,
            path: unused.normalizedPath,
            message: unused.summary.map { "未使用接口：\($0)" } ?? "后端声明了 TV 未使用的同族接口"
          )
        )
      } else {
        report.findings.append(
          OpenAPIFinding(
            severity: .info,
            kind: .relatedEndpointAdded,
            operationID: unused.operationID,
            path: unused.normalizedPath,
            message: "上游新增同族接口，尚未评估是否需要跟进"
              + (unused.summary.map { "（\($0)）" } ?? "")
          )
        )
        report.coverageGaps.append(
          OpenAPICoverageGap(
            kind: .relatedUnevaluated,
            operationID: unused.operationID,
            message: "上游新增同族接口，尚未评估是否需要跟进"
          )
        )
      }
    }

    addCoverageGaps(catalog: catalog, into: &report)
    report.coverageGaps.append(contentsOf: sourceGaps)
    applyExceptions(exceptions, to: &report)
    return report
  }

  private static func checkCatalogOperation(
    _ catalog: TVAPIOperation,
    against live: OpenAPIDocument,
    baseline: OpenAPIDocument?,
    into report: inout OpenAPIContractReport
  ) {
    guard let match = OpenAPIPathIndex.findPath(catalog.pathTemplate, in: live.paths) else {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .pathMissing,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "TV 使用的路径已从后端 OpenAPI 中消失"
        )
      )
      return
    }

    let methods = OpenAPIPathIndex.httpMethods(in: match.item)
    guard methods[catalog.method.lowercased()] != nil else {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .methodMissing,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "TV 使用的 \(catalog.method) 已不在该路径上声明；现有方法：\(methods.keys.sorted().joined(separator: ", "))"
        )
      )
      return
    }

    guard
      let liveOperation = OpenAPIOperationLoader.load(
        method: catalog.method,
        path: match.path,
        pathItem: match.item,
        document: live
      )
    else {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "无法加载该接口的 OpenAPI operation"
        )
      )
      return
    }

    if let reason = liveOperation.unverifiedReason {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: reason
        )
      )
      return
    }

    checkParameters(catalog: catalog, live: liveOperation, into: &report)
    checkRequestBody(catalog: catalog, live: liveOperation, into: &report)
    checkResponse(catalog: catalog, live: liveOperation, into: &report)
    if liveOperation.deprecated && baseline == nil {
      report.findings.append(
        OpenAPIFinding(
          severity: .review,
          kind: .deprecated,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "接口已被标记为废弃"
        )
      )
    }

    if let baseline {
      compareWithBaseline(
        catalog: catalog,
        live: liveOperation,
        baselineDocument: baseline,
        into: &report
      )
    }
  }

  private static func checkParameters(
    catalog: TVAPIOperation,
    live: OpenAPIOperation,
    into report: inout OpenAPIContractReport
  ) {
    var consumed: Set<String> = []

    for parameter in catalog.parameters {
      if let matched = matchParameter(parameter, in: live.parameters) {
        consumed.insert("\(matched.location):\(matched.name)")
        if !parameterTypesCompatible(tv: parameter.jsonType, schema: matched.schema, location: parameter.location)
        {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .parameterTypeMismatch,
              operationID: catalog.operationID,
              path: "\(parameter.location.rawValue).\(parameter.name)",
              message:
                "TV 发送 \(parameter.jsonType.rawValue)，OpenAPI 声明 \(matched.schema.types.sorted().joined(separator: "|"))"
            )
          )
        }
        if matched.deprecated {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .deprecated,
              operationID: catalog.operationID,
              path: "\(parameter.location.rawValue).\(parameter.name)",
              message: "参数已标记废弃"
            )
          )
        }
      } else {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .undeclaredParameter,
            operationID: catalog.operationID,
            path: "\(parameter.location.rawValue).\(parameter.name)",
            message: "TV 发出的参数不再被 OpenAPI 声明"
          )
        )
      }
    }

    for parameter in live.parameters where parameter.required {
      let key = "\(parameter.location):\(parameter.name)"
      if consumed.contains(key) { continue }
      if catalog.parameters.contains(where: { $0.name == parameter.name }) { continue }
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .missingRequiredParameter,
          operationID: catalog.operationID,
          path: "\(parameter.location).\(parameter.name)",
          message: "后端新增或仍声明必填参数，但 TV 未提供"
        )
      )
    }
  }

  private static func matchParameter(
    _ parameter: TVAPIParameter,
    in live: [OpenAPIParameter]
  ) -> OpenAPIParameter? {
    if let exact = live.first(where: {
      $0.name == parameter.name && $0.location == parameter.location.rawValue
    }) {
      return exact
    }
    if parameter.location == .path {
      return live.first(where: { $0.location == "path" && live.filter { $0.location == "path" }.count == 1 })
        ?? live.first(where: { $0.location == "path" })
    }
    return live.first(where: { $0.name == parameter.name })
  }

  private static func checkRequestBody(
    catalog: TVAPIOperation,
    live: OpenAPIOperation,
    into report: inout OpenAPIContractReport
  ) {
    guard !catalog.bodyFields.isEmpty || live.requestBodySchema != nil else { return }
    guard let schema = live.requestBodySchema else {
      if !catalog.bodyFields.isEmpty {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .undeclaredBodyField,
            operationID: catalog.operationID,
            path: "body",
            message: "TV 发送请求体，但 OpenAPI 未声明 requestBody"
          )
        )
      }
      return
    }
    if schema.isUnsupported {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalog.operationID,
          path: "body",
          message: schema.unsupportedReason ?? "请求体 schema 无法解析"
        )
      )
      return
    }

    let properties = schema.properties
    for field in catalog.bodyFields {
      guard let property = properties[field.name] else {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .undeclaredBodyField,
            operationID: catalog.operationID,
            path: "body.\(field.name)",
            message: "TV 发送的请求字段不再被声明"
          )
        )
        continue
      }
      if !typesCompatible(tv: field.jsonType, schema: property, direction: .request) {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .bodyFieldTypeMismatch,
            operationID: catalog.operationID,
            path: "body.\(field.name)",
            message:
              "请求字段类型不兼容：TV=\(field.jsonType.rawValue) OpenAPI=\(property.types.sorted().joined(separator: "|"))"
          )
        )
      }
    }

    for requiredName in schema.required {
      if catalog.bodyFields.contains(where: { $0.name == requiredName }) { continue }
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .missingRequiredBodyField,
          operationID: catalog.operationID,
          path: "body.\(requiredName)",
          message: "后端请求体新增或仍声明必填字段，但 TV 没有提供"
        )
      )
    }

    if catalog.roundTrip {
      let sent = Set(catalog.bodyFields.map(\.name))
      let omitted = properties.keys.filter { !sent.contains($0) }.sorted()
      if !omitted.isEmpty {
        report.coverageGaps.append(
          OpenAPICoverageGap(
            kind: .roundTripOmission,
            operationID: catalog.operationID,
            message: "往返保存未保留可写字段：\(omitted.joined(separator: ", "))。相对基线的新增字段会作为待审查项"
          )
        )
      }
    }
  }

  private static func checkResponse(
    catalog: TVAPIOperation,
    live: OpenAPIOperation,
    into report: inout OpenAPIContractReport
  ) {
    if catalog.responseKind == .sse {
      if live.successContentType != "text/event-stream" {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .responseStructureChanged,
            operationID: catalog.operationID,
            path: "response",
            message: "TV 按 SSE 消费，OpenAPI 成功响应类型为 \(live.successContentType ?? "missing")"
          )
        )
      }
      report.coverageGaps.append(
        OpenAPICoverageGap(
          kind: .opaqueSchema,
          operationID: catalog.operationID,
          message: "OpenAPI 未描述 SSE 事件字段，仍需真实流式测试"
        )
      )
      return
    }
    if catalog.responseKind == .image {
      return
    }

    let schema: OpenAPISchema?
    switch catalog.responseKind {
    case .moviePilotEnvelope:
      schema = live.innerDataSchema ?? live.successSchema
    case .raw, .opaqueJSON:
      schema = live.successSchema
    case .sse, .image:
      schema = nil
    }
    guard var schema else { return }
    if catalog.responseKind == .moviePilotEnvelope,
      schema.kind == .array || schema.types.contains("array"),
      let items = schema.items?.schema
    {
      schema = items
    } else if schema.kind == .array, let items = schema.items?.schema {
      schema = items
    }

    if schema.kind == .opaque || catalog.responseKind == .opaqueJSON {
      report.coverageGaps.append(
        OpenAPICoverageGap(
          kind: .opaqueSchema,
          operationID: catalog.operationID,
          message: "响应 schema 过于宽松，无法核对具体字段"
        )
      )
      return
    }
    if schema.isUnsupported {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalog.operationID,
          path: "response",
          message: schema.unsupportedReason ?? "响应 schema 无法解析"
        )
      )
      return
    }

    let fields = catalog.requiredResponseFields + catalog.dependedResponseFields
    let canInspectProperties = !schema.properties.isEmpty || schema.kind == .union
    for field in fields {
      guard responseDeclaresField(schema, name: field.name) else {
        if field.required || canInspectProperties {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .responseFieldMissing,
              operationID: catalog.operationID,
              path: "response.\(field.name)",
              message: "TV 依赖的响应字段已不再声明"
            )
          )
        }
        continue
      }
      // MoviePilot 的 Pydantic 模型几乎都是 anyOf T|null，不能把“TV 必填 vs OpenAPI 可空”
      // 直接当成破坏；必填变可缺失只在相对基线比较时失败。
      if !responseTypeCompatible(tv: field.jsonType, schema: schema, fieldName: field.name) {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .responseFieldTypeMismatch,
            operationID: catalog.operationID,
            path: "response.\(field.name)",
            message: "响应字段类型不兼容：TV=\(field.jsonType.rawValue)"
          )
        )
      }
    }
  }

  private static func responseDeclaresField(_ schema: OpenAPISchema, name: String) -> Bool {
    if schema.properties[name] != nil { return true }
    if schema.kind == .union {
      return schema.alternatives.contains { responseDeclaresField($0, name: name) }
    }
    if schema.kind == .array, let items = schema.items?.schema {
      return responseDeclaresField(items, name: name)
    }
    return false
  }

  private static func responseTypeCompatible(
    tv: TVJSONType,
    schema: OpenAPISchema,
    fieldName: String
  ) -> Bool {
    if schema.kind == .array, let items = schema.items?.schema {
      return responseTypeCompatible(tv: tv, schema: items, fieldName: fieldName)
    }
    if schema.kind == .union, !schema.alternatives.isEmpty {
      let declaring = schema.alternatives.filter { responseDeclaresField($0, name: fieldName) }
      guard !declaring.isEmpty else { return true }
      return declaring.contains {
        responseTypeCompatible(tv: tv, schema: $0, fieldName: fieldName)
      }
    }
    guard let property = schema.properties[fieldName] else { return true }
    return typesCompatible(tv: tv, schema: property, direction: .response)
  }

  private static func compareWithBaseline(
    catalog: TVAPIOperation,
    live: OpenAPIOperation,
    baselineDocument: OpenAPIDocument,
    into report: inout OpenAPIContractReport
  ) {
    guard
      let baselineOperation = OpenAPIOperationLoader.load(
        method: catalog.method,
        template: catalog.pathTemplate,
        document: baselineDocument
      )
    else {
      report.findings.append(
        OpenAPIFinding(
          severity: .review,
          kind: .catalogMissing,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "基线中没有该已用接口，审查后应更新基线"
        )
      )
      return
    }

    if live.deprecated && !baselineOperation.deprecated {
      report.findings.append(
        OpenAPIFinding(
          severity: .review,
          kind: .deprecated,
          operationID: catalog.operationID,
          path: catalog.pathTemplate,
          message: "相对基线新增废弃标记"
        )
      )
    }

    compareParameterBaseline(
      catalog: catalog,
      live: live,
      baseline: baselineOperation,
      into: &report
    )
    compareSchemaBaseline(
      catalogID: catalog.operationID,
      location: "body",
      live: live.requestBodySchema,
      baseline: baselineOperation.requestBodySchema,
      roundTrip: catalog.roundTrip,
      direction: .request,
      into: &report
    )
    compareSchemaBaseline(
      catalogID: catalog.operationID,
      location: "response",
      live: live.innerDataSchema ?? live.successSchema,
      baseline: baselineOperation.innerDataSchema ?? baselineOperation.successSchema,
      roundTrip: catalog.roundTrip,
      direction: .response,
      into: &report
    )
  }

  private static func compareParameterBaseline(
    catalog: TVAPIOperation,
    live: OpenAPIOperation,
    baseline: OpenAPIOperation,
    into report: inout OpenAPIContractReport
  ) {
    let liveMap = Dictionary(uniqueKeysWithValues: live.parameters.map { ("\($0.location):\($0.name)", $0) })
    let baselineMap = Dictionary(
      uniqueKeysWithValues: baseline.parameters.map { ("\($0.location):\($0.name)", $0) }
    )
    for (key, liveParameter) in liveMap {
      if let old = baselineMap[key] {
        if liveParameter.required && !old.required {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .missingRequiredParameter,
              operationID: catalog.operationID,
              path: "\(liveParameter.location).\(liveParameter.name)",
              message: "相对基线，该参数变为必填"
            )
          )
        }
        if !old.deprecated && liveParameter.deprecated {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .deprecated,
              operationID: catalog.operationID,
              path: "\(liveParameter.location).\(liveParameter.name)",
              message: "相对基线新增废弃标记"
            )
          )
        }
        if normalizedDefault(old.schema.defaultValue) != normalizedDefault(liveParameter.schema.defaultValue) {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .defaultChanged,
              operationID: catalog.operationID,
              path: "\(liveParameter.location).\(liveParameter.name)",
              message: "参数默认值相对基线发生变化"
            )
          )
        }
      } else if liveParameter.required {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .missingRequiredParameter,
            operationID: catalog.operationID,
            path: "\(liveParameter.location).\(liveParameter.name)",
            message: "相对基线新增必填参数"
          )
        )
      } else {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .newWritableField,
            operationID: catalog.operationID,
            path: "\(liveParameter.location).\(liveParameter.name)",
            message: "相对基线新增可选参数"
          )
        )
      }
    }
  }

  private static func compareSchemaBaseline(
    catalogID: String,
    location: String,
    live: OpenAPISchema?,
    baseline: OpenAPISchema?,
    roundTrip: Bool,
    direction: CompatibilityDirection,
    into report: inout OpenAPIContractReport
  ) {
    guard let live, let baseline else { return }
    let liveProps = live.properties
    let baselineProps = baseline.properties
    for name in Set(liveProps.keys).union(baselineProps.keys).sorted() {
      let liveProperty = liveProps[name]
      let baselineProperty = baselineProps[name]
      if let liveProperty, baselineProperty == nil {
        if direction == .request && (roundTrip || live.required.contains(name)) {
          report.findings.append(
            OpenAPIFinding(
              severity: live.required.contains(name) ? .failure : .review,
              kind: live.required.contains(name) ? .missingRequiredBodyField : .newWritableField,
              operationID: catalogID,
              path: "\(location).\(name)",
              message: live.required.contains(name)
                ? "相对基线新增必填请求字段"
                : "相对基线新增可写字段，往返保存时可能丢失语义"
            )
          )
        } else if direction == .response {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .newWritableField,
              operationID: catalogID,
              path: "\(location).\(name)",
              message: "相对基线新增响应字段"
            )
          )
        }
        continue
      }
      if liveProperty == nil, let baselineProperty {
        if direction == .response {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .responseFieldMissing,
              operationID: catalogID,
              path: "\(location).\(name)",
              message: "相对基线删除了响应字段"
            )
          )
        } else if !baselineProperty.nullable {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .responseStructureChanged,
              operationID: catalogID,
              path: "\(location).\(name)",
              message: "相对基线删除了请求字段"
            )
          )
        }
        continue
      }
      guard let liveProperty, let baselineProperty else { continue }
      if direction == .response {
        if !baselineProperty.nullable && liveProperty.nullable {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .responseFieldNullability,
              operationID: catalogID,
              path: "\(location).\(name)",
              message: "相对基线，响应字段从必填/存在变为可缺失"
            )
          )
        }
      } else if !liveProperty.nullable && baselineProperty.nullable && live.required.contains(name)
        && !baseline.required.contains(name)
      {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .missingRequiredBodyField,
            operationID: catalogID,
            path: "\(location).\(name)",
            message: "相对基线，请求字段变为必填"
          )
        )
      }
      if normalizedDefault(baselineProperty.defaultValue) != normalizedDefault(liveProperty.defaultValue) {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .defaultChanged,
            operationID: catalogID,
            path: "\(location).\(name)",
            message: "相对基线，字段默认值发生变化"
          )
        )
      }
      if !baselineProperty.deprecated && liveProperty.deprecated {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .deprecated,
            operationID: catalogID,
            path: "\(location).\(name)",
            message: "相对基线新增废弃标记"
          )
        )
      }
    }
  }

  private static func relatedUnusedOperations(
    in document: OpenAPIDocument,
    usedIDs: Set<String>
  ) -> [OpenAPIOperation] {
    let families = TVAPIContractCatalog.usedFamilyPrefixes
    var unused: [OpenAPIOperation] = []
    for (path, item) in document.paths {
      let normalized = OpenAPIPathIndex.normalizeAPIPath(path)
      if normalized.hasPrefix("/plugin/") { continue }
      let family = OpenAPIPathIndex.familyPrefix(for: normalized)
      guard families.contains(family) else { continue }
      for method in OpenAPIPathIndex.httpMethods(in: item).keys {
        let id = OpenAPIPathIndex.operationID(method: method, path: normalized)
        if usedIDs.contains(id) { continue }
        if catalogMatches(method: method, path: normalized) { continue }
        if let operation = OpenAPIOperationLoader.load(
          method: method,
          path: path,
          pathItem: item,
          document: document
        ) {
          unused.append(operation)
        }
      }
    }
    return unused.sorted { $0.operationID < $1.operationID }
  }

  private static func catalogMatches(method: String, path: String) -> Bool {
    TVAPIContractCatalog.operations.contains {
      $0.method.lowercased() == method.lowercased()
        && OpenAPIPathIndex.pathsMatch($0.pathTemplate, path)
    }
  }

  private static func addCoverageGaps(
    catalog: [TVAPIOperation],
    into report: inout OpenAPIContractReport
  ) {
    for operation in catalog {
      if operation.coverage.isEmpty {
        report.coverageGaps.append(
          OpenAPICoverageGap(
            kind: .catalogWithoutBehavioralTest,
            operationID: operation.operationID,
            message: "TV 使用了该接口，但没有对应行为测试"
          )
        )
      } else if operation.coverage == .urlProtocol
        && operation.requiredResponseFields.isEmpty
        && operation.dependedResponseFields.isEmpty
      {
        report.coverageGaps.append(
          OpenAPICoverageGap(
            kind: .pathOnly,
            operationID: operation.operationID,
            message: "已有测试主要验证路径/请求编码，没有核对响应字段"
          )
        )
      }
      if operation.responseKind == .opaqueJSON {
        report.coverageGaps.append(
          OpenAPICoverageGap(
            kind: .opaqueSchema,
            operationID: operation.operationID,
            message: "TV 使用了该接口，但 OpenAPI/解码均按宽松 JSON 处理"
          )
        )
      }
    }
  }

  private static func applyExceptions(
    _ exceptions: [OpenAPIException],
    to report: inout OpenAPIContractReport
  ) {
    report.findings = report.findings.map { finding in
      var finding = finding
      if exceptions.contains(where: { matches($0, finding: finding) }) {
        finding.excepted = true
      }
      return finding
    }
    let exceptedIDs = Set(
      report.findings.filter(\.excepted).map { "\($0.kind.rawValue)|\($0.operationID)|\($0.path)" }
    )
    report.coverageGaps.removeAll { gap in
      exceptions.contains {
        $0.kind == .coverageGap
          && ($0.operation == "*" || $0.operation == gap.operationID)
      }
        || exceptedIDs.contains { _ in false }
    }
  }

  private static func matches(_ exception: OpenAPIException, finding: OpenAPIFinding) -> Bool {
    guard exception.kind == finding.kind else { return false }
    if exception.operation != "*" && exception.operation != finding.operationID {
      return false
    }
    if let path = exception.path, !path.isEmpty {
      return finding.path == path || finding.path.hasPrefix(path)
    }
    return true
  }

  private enum CompatibilityDirection {
    case request
    case response
  }

  private static func parameterTypesCompatible(
    tv: TVJSONType,
    schema: OpenAPISchema,
    location: TVAPIParameter.Location
  ) -> Bool {
    if location == .query || location == .path || location == .header {
      let queryCompatible: Set<String> = ["string", "integer", "number", "boolean"]
      if tv == .string || tv == .flexibleString || tv == .integer || tv == .number
        || tv == .boolean || tv == .flexibleBool
      {
        return schema.types.isEmpty
          || !schema.types.subtracting(["null"]).isDisjoint(with: queryCompatible)
          || schema.kind == .union
          || schema.kind == .string
          || schema.kind == .integer
          || schema.kind == .number
          || schema.kind == .boolean
      }
    }
    return typesCompatible(tv: tv, schema: schema, direction: .request)
  }

  private static func typesCompatible(
    tv: TVJSONType,
    schema: OpenAPISchema,
    direction: CompatibilityDirection
  ) -> Bool {
    if schema.kind == .opaque || schema.kind == .recursive || schema.kind == .union {
      if tv == .json || tv == .object { return true }
    }
    let types = schema.types.subtracting(["null"])
    switch tv {
    case .string, .flexibleString:
      return types.isEmpty || types.contains("string")
    case .integer:
      return types.contains("integer") || types.contains("number")
    case .number:
      return types.contains("number") || types.contains("integer")
    case .boolean, .flexibleBool:
      return types.contains("boolean") || types.contains("integer")
    case .array:
      return types.contains("array") || schema.kind == .array
    case .object:
      return types.contains("object") || schema.kind == .object || schema.kind == .opaque
    case .json:
      if direction == .response { return true }
      return types.contains("object") || types.contains("array") || schema.kind == .object
        || schema.kind == .array || schema.kind == .opaque || schema.kind == .union
        || schema.kind == .recursive
    }
  }

  private static func normalizedDefault(_ value: JSONValue?) -> String {
    guard let value, value != .null else { return "" }
    guard let data = try? JSONEncoder().encode(value),
      let text = String(data: data, encoding: .utf8)
    else {
      return String(describing: value)
    }
    return text
  }
}

enum OpenAPIExceptionStore {
  static func load(from data: Data) throws -> [OpenAPIException] {
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    let items = root.objectValue?["exceptions"]?.arrayValue ?? []
    return items.compactMap { item in
      guard let object = item.objectValue,
        let id = object["id"]?.stringValue,
        let operation = object["operation"]?.stringValue,
        let kindRaw = object["kind"]?.stringValue,
        let kind = OpenAPIFindingKind(rawValue: kindRaw),
        let reason = object["reason"]?.stringValue
      else {
        return nil
      }
      return OpenAPIException(
        id: id,
        operation: operation,
        kind: kind,
        path: object["path"]?.stringValue,
        reason: reason
      )
    }
  }
}
