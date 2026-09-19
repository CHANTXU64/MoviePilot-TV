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
  case responseFieldPresence
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
    for parameter in catalog.parameters {
      if let matched = matchParameter(parameter, in: live.parameters) {
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
      let alwaysSent = catalog.parameters.contains {
        $0.name == parameter.name && $0.alwaysSent
      }
      if alwaysSent { continue }
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .missingRequiredParameter,
          operationID: catalog.operationID,
          path: "\(parameter.location).\(parameter.name)",
          message: "后端声明该参数必填，但 TV 未保证每次都发送"
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
      if let itemType = field.itemType, let items = property.items?.schema,
        !typesCompatible(tv: itemType, schema: items, direction: .request)
      {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .bodyFieldTypeMismatch,
            operationID: catalog.operationID,
            path: "body.\(field.name)[]",
            message: "请求数组元素类型不兼容：TV=\(itemType.rawValue)"
          )
        )
      }
    }

    for requiredName in schema.required {
      let alwaysSent = catalog.bodyFields.contains {
        $0.name == requiredName && $0.alwaysSent
      }
      if alwaysSent { continue }
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .missingRequiredBodyField,
          operationID: catalog.operationID,
          path: "body.\(requiredName)",
          message: "后端请求体声明该字段必填，但 TV 未保证每次都发送该键"
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

    let expectsJSON =
      catalog.responseKind == .moviePilotEnvelope
      || catalog.responseKind == .raw
      || catalog.responseKind == .opaqueJSON
    let schema: OpenAPISchema?
    switch catalog.responseKind {
    case .moviePilotEnvelope:
      schema = live.innerDataSchema ?? live.successSchema
    case .raw, .opaqueJSON:
      schema = live.successSchema
    case .sse, .image:
      schema = nil
    }
    guard var schema else {
      if expectsJSON {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .unverifiedSchema,
            operationID: catalog.operationID,
            path: "response",
            message: "TV 按 JSON 解码，但 OpenAPI 未声明成功响应结构"
          )
        )
      }
      return
    }
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
      let declaredEverywhere = responseDeclaresField(
        schema,
        name: field.name,
        requireAllUnionBranches: field.required
      )
      guard declaredEverywhere else {
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
      if let itemType = field.itemType,
        let items = responseArrayItemSchema(schema, fieldName: field.name),
        !typesCompatible(tv: itemType, schema: items, direction: .response)
      {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .responseFieldTypeMismatch,
            operationID: catalog.operationID,
            path: "response.\(field.name)[]",
            message: "响应数组元素类型不兼容：TV=\(itemType.rawValue)"
          )
        )
      }
    }
  }

  private static func responseArrayItemSchema(_ schema: OpenAPISchema, fieldName: String) -> OpenAPISchema? {
    if schema.kind == .array, let items = schema.items?.schema {
      return responseArrayItemSchema(items, fieldName: fieldName)
    }
    if schema.kind == .union, !schema.alternatives.isEmpty {
      return schema.alternatives.compactMap { responseArrayItemSchema($0, fieldName: fieldName) }.first
    }
    return schema.properties[fieldName]?.items?.schema
  }

  private static func responseDeclaresField(
    _ schema: OpenAPISchema,
    name: String,
    requireAllUnionBranches: Bool = false
  ) -> Bool {
    if schema.kind == .array, let items = schema.items?.schema {
      return responseDeclaresField(
        items,
        name: name,
        requireAllUnionBranches: requireAllUnionBranches
      )
    }
    if schema.kind == .union, !schema.alternatives.isEmpty {
      let checks = schema.alternatives.map {
        responseDeclaresField($0, name: name, requireAllUnionBranches: requireAllUnionBranches)
      }
      return requireAllUnionBranches ? checks.allSatisfy { $0 } : checks.contains(true)
    }
    return schema.properties[name] != nil
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
      let declaring = schema.alternatives.filter {
        responseDeclaresField($0, name: fieldName)
      }
      guard !declaring.isEmpty else { return true }
      return declaring.allSatisfy {
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
    let expectsJSON =
      catalog.responseKind == .moviePilotEnvelope
      || catalog.responseKind == .raw
      || catalog.responseKind == .opaqueJSON
    compareSchemaBaseline(
      catalogID: catalog.operationID,
      location: "body",
      live: live.requestBodySchema,
      baseline: baselineOperation.requestBodySchema,
      roundTrip: catalog.roundTrip,
      direction: .request,
      catalogFields: catalog.bodyFields,
      expectsValue: !catalog.bodyFields.isEmpty || live.requestBodySchema != nil
        || baselineOperation.requestBodySchema != nil,
      into: &report
    )
    compareSchemaBaseline(
      catalogID: catalog.operationID,
      location: "response",
      live: live.innerDataSchema ?? live.successSchema,
      baseline: baselineOperation.innerDataSchema ?? baselineOperation.successSchema,
      roundTrip: catalog.roundTrip,
      direction: .response,
      catalogFields: catalog.requiredResponseFields + catalog.dependedResponseFields,
      expectsValue: expectsJSON,
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

  /// 递归比较的目录、联合与报警规则：
  ///
  /// 目录上下文属于当前层，不是整棵树共用一份根字段名。
  /// 请求根层 `body`（含根联合分支）用已登记字段名限制范围；进入已登记对象、
  /// 数组元素或联合分支后不再用父层字段名过滤，也不得因同名继承父层 TV 类型
  /// 或 `alwaysSent`。没有完整子目录时继续核对该节点相对基线的结构，不能静默跳过。
  /// 新增必填仍在当前层检查。
  ///
  /// 联合分支不能按下标当身份。先按 `$ref`、anyOf/oneOf 与结构指纹匹配未变化分支，
  /// 剩余恰好 1 对 1 时再递归比较真实变化。分支数量对不上、多个剩余分支无法唯一配对、
  /// 或 anyOf 与 oneOf 互换时报告未验证。不丢弃分支，不把合并后的 properties 当合同。
  ///
  /// 必须报警：已使用对象内已有字段类型不兼容、必填变化、已匹配分支内嵌套不兼容、
  /// 成功 JSON 结构消失。不得误报：对象未变、anyOf/oneOf 仅换序、仅 description/键顺序变化、
  /// 根层未使用可选字段变化。
  private static func compareSchemaBaseline(
    catalogID: String,
    location: String,
    live: OpenAPISchema?,
    baseline: OpenAPISchema?,
    roundTrip: Bool,
    direction: CompatibilityDirection,
    catalogFields: [TVAPIField] = [],
    expectsValue: Bool = true,
    depth: Int = 0,
    into report: inout OpenAPIContractReport
  ) {
    if depth > 8 { return }
    if live == nil && baseline == nil {
      if expectsValue && depth == 0 {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .unverifiedSchema,
            operationID: catalogID,
            path: location,
            message: "基线与当前都缺少可比较的 JSON schema"
          )
        )
      }
      return
    }
    if live == nil, baseline != nil {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: direction == .response ? .responseStructureChanged : .responseStructureChanged,
          operationID: catalogID,
          path: location,
          message: direction == .response
            ? "相对基线，成功 JSON 响应结构消失"
            : "相对基线，请求体 schema 消失"
        )
      )
      return
    }
    if live != nil, baseline == nil {
      if expectsValue {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .responseStructureChanged,
            operationID: catalogID,
            path: location,
            message: "相对基线新增 JSON schema"
          )
        )
      }
      return
    }
    guard let live, let baseline else { return }

    compareRequiredSets(
      catalogID: catalogID,
      location: location,
      live: live,
      baseline: baseline,
      direction: direction,
      catalogFields: catalogFields,
      into: &report
    )
    compareCurrentNode(
      catalogID: catalogID,
      location: location,
      live: live,
      baseline: baseline,
      direction: direction,
      catalogFields: catalogFields,
      into: &report
    )

    let liveAlts = live.alternatives
    let baselineAlts = baseline.alternatives
    if liveAlts.count >= 2 || baselineAlts.count >= 2 {
      compareUnionAlternatives(
        catalogID: catalogID,
        location: location,
        live: live,
        baseline: baseline,
        roundTrip: roundTrip,
        direction: direction,
        catalogFields: catalogFields,
        depth: depth,
        into: &report
      )
      return
    }

    if let liveItems = live.items?.schema, let baselineItems = baseline.items?.schema {
      compareSchemaBaseline(
        catalogID: catalogID,
        location: "\(location)[]",
        live: liveItems,
        baseline: baselineItems,
        roundTrip: roundTrip,
        direction: direction,
        catalogFields: catalogFields,
        expectsValue: true,
        depth: depth + 1,
        into: &report
      )
    } else if live.kind == .array || baseline.kind == .array,
      live.items == nil || baseline.items == nil, live.kind != baseline.kind
    {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .responseStructureChanged,
          operationID: catalogID,
          path: location,
          message: "相对基线，数组结构发生变化"
        )
      )
    }

    let liveProps = live.properties
    let baselineProps = baseline.properties
    var propertyNames = Set(liveProps.keys).union(baselineProps.keys)
    if isRequestCatalogLayer(location), !catalogFields.isEmpty {
      let catalogued = Set(catalogFields.map(\.name))
      var names = propertyNames.intersection(catalogued)
      if roundTrip {
        names.formUnion(Set(liveProps.keys).subtracting(baselineProps.keys))
      }
      propertyNames = names
    }
    for name in propertyNames.sorted() {
      let liveProperty = liveProps[name]
      let baselineProperty = baselineProps[name]
      let childPath = "\(location).\(name)"
      if let liveProperty, baselineProperty == nil {
        if direction == .request && (roundTrip || live.required.contains(name)) {
          report.findings.append(
            OpenAPIFinding(
              severity: live.required.contains(name) ? .failure : .review,
              kind: live.required.contains(name) ? .missingRequiredBodyField : .newWritableField,
              operationID: catalogID,
              path: childPath,
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
              path: childPath,
              message: "相对基线新增响应字段"
            )
          )
        }
        continue
      }
      if liveProperty == nil, baselineProperty != nil {
        if direction == .response {
          report.findings.append(
            OpenAPIFinding(
              severity: .failure,
              kind: .responseFieldMissing,
              operationID: catalogID,
              path: childPath,
              message: "相对基线删除了响应字段"
            )
          )
        } else {
          report.findings.append(
            OpenAPIFinding(
              severity: .review,
              kind: .responseStructureChanged,
              operationID: catalogID,
              path: childPath,
              message: "相对基线删除了请求字段"
            )
          )
        }
        continue
      }
      guard let liveProperty, let baselineProperty else { continue }

      if normalizedDefault(baselineProperty.defaultValue) != normalizedDefault(liveProperty.defaultValue) {
        report.findings.append(
          OpenAPIFinding(
            severity: .review,
            kind: .defaultChanged,
            operationID: catalogID,
            path: childPath,
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
            path: childPath,
            message: "相对基线新增废弃标记"
          )
        )
      }

      compareSchemaBaseline(
        catalogID: catalogID,
        location: childPath,
        live: liveProperty,
        baseline: baselineProperty,
        roundTrip: roundTrip,
        direction: direction,
        catalogFields: catalogFields,
        expectsValue: true,
        depth: depth + 1,
        into: &report
      )
    }
  }

  private static func isRequestCatalogLayer(_ location: String) -> Bool {
    if location == "body" { return true }
    return location.hasPrefix("body|alt") && !location.contains(".")
  }

  private static func compareUnionAlternatives(
    catalogID: String,
    location: String,
    live: OpenAPISchema,
    baseline: OpenAPISchema,
    roundTrip: Bool,
    direction: CompatibilityDirection,
    catalogFields: [TVAPIField],
    depth: Int,
    into report: inout OpenAPIContractReport
  ) {
    if live.combinator != baseline.combinator {
      let liveName = live.combinator ?? "missing"
      let baselineName = baseline.combinator ?? "missing"
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalogID,
          path: location,
          message: "联合组合方式从 \(baselineName) 变为 \(liveName)，不能当作同一集合比较"
        )
      )
    }

    let matched = matchUnionAlternatives(live: live.alternatives, baseline: baseline.alternatives)
    for pair in matched.pairs {
      compareSchemaBaseline(
        catalogID: catalogID,
        location: "\(location)|alt\(pair.baselineIndex)",
        live: pair.live,
        baseline: pair.baseline,
        roundTrip: roundTrip,
        direction: direction,
        catalogFields: catalogFields,
        expectsValue: true,
        depth: depth + 1,
        into: &report
      )
    }
    if let reason = matched.unverifiedReason {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .unverifiedSchema,
          operationID: catalogID,
          path: location,
          message: reason
        )
      )
    }
  }

  private struct UnionBranchPair {
    let live: OpenAPISchema
    let baseline: OpenAPISchema
    let baselineIndex: Int
  }

  private struct UnionMatchResult {
    var pairs: [UnionBranchPair]
    var unverifiedReason: String?
  }

  private static func matchUnionAlternatives(
    live: [OpenAPISchema],
    baseline: [OpenAPISchema]
  ) -> UnionMatchResult {
    var liveUnused = Set(live.indices)
    var baselineUnused = Set(baseline.indices)
    var pairs: [UnionBranchPair] = []

    var liveByID: [String: [Int]] = [:]
    var baselineByID: [String: [Int]] = [:]
    for (index, schema) in live.enumerated() {
      liveByID[schemaIdentity(schema), default: []].append(index)
    }
    for (index, schema) in baseline.enumerated() {
      baselineByID[schemaIdentity(schema), default: []].append(index)
    }

    for identity in Set(liveByID.keys).intersection(baselineByID.keys).sorted() {
      var liveIndexes = liveByID[identity] ?? []
      var baselineIndexes = baselineByID[identity] ?? []
      while let liveIndex = liveIndexes.first, let baselineIndex = baselineIndexes.first {
        liveIndexes.removeFirst()
        baselineIndexes.removeFirst()
        liveUnused.remove(liveIndex)
        baselineUnused.remove(baselineIndex)
        pairs.append(
          UnionBranchPair(
            live: live[liveIndex],
            baseline: baseline[baselineIndex],
            baselineIndex: baselineIndex
          )
        )
      }
    }

    if liveUnused.count == 1, baselineUnused.count == 1,
      let liveIndex = liveUnused.first,
      let baselineIndex = baselineUnused.first
    {
      pairs.append(
        UnionBranchPair(
          live: live[liveIndex],
          baseline: baseline[baselineIndex],
          baselineIndex: baselineIndex
        )
      )
      liveUnused.remove(liveIndex)
      baselineUnused.remove(baselineIndex)
    }

    let unverifiedReason: String?
    if !liveUnused.isEmpty || !baselineUnused.isEmpty {
      unverifiedReason =
        "联合类型无法可靠匹配分支：当前剩余 \(liveUnused.count) 个，基线剩余 \(baselineUnused.count) 个"
    } else {
      unverifiedReason = nil
    }
    return UnionMatchResult(pairs: pairs, unverifiedReason: unverifiedReason)
  }

  private static func schemaIdentity(_ schema: OpenAPISchema) -> String {
    var parts: [String] = []
    if let ref = schema.ref {
      parts.append("ref=\(ref)")
    }
    if let combinator = schema.combinator {
      parts.append("comb=\(combinator)")
    }
    parts.append("kind=\(kindIdentity(schema.kind))")
    parts.append("types=\(schema.types.subtracting(["null"]).sorted().joined(separator: ","))")
    parts.append("null=\(schema.nullable)")
    parts.append("req=\(schema.required.sorted().joined(separator: ","))")
    if !schema.enumValues.isEmpty {
      parts.append("enum=\(schema.enumValues.sorted().joined(separator: ","))")
    }
    if let format = schema.format {
      parts.append("fmt=\(format)")
    }
    parts.append("addl=\(schema.additionalPropertiesAllowed)")
    for name in schema.properties.keys.sorted() {
      parts.append("p.\(name)={\(schemaIdentity(schema.properties[name]!))}")
    }
    if let items = schema.items {
      parts.append("items={\(schemaIdentity(items.schema))}")
    }
    if !schema.alternatives.isEmpty {
      parts.append("alts=[\(schema.alternatives.map(schemaIdentity).sorted().joined(separator: "|"))]")
    }
    return parts.joined(separator: ";")
  }

  private static func kindIdentity(_ kind: OpenAPISchema.Kind) -> String {
    switch kind {
    case .null:
      return "null"
    case .boolean:
      return "boolean"
    case .integer:
      return "integer"
    case .number:
      return "number"
    case .string:
      return "string"
    case .array:
      return "array"
    case .object:
      return "object"
    case .union:
      return "union"
    case .opaque:
      return "opaque"
    case .recursive:
      return "recursive"
    case .unsupported(let reason):
      return "unsupported:\(reason)"
    }
  }

  private static func compareCurrentNode(
    catalogID: String,
    location: String,
    live: OpenAPISchema,
    baseline: OpenAPISchema,
    direction: CompatibilityDirection,
    catalogFields: [TVAPIField],
    into report: inout OpenAPIContractReport
  ) {
    if direction == .response {
      if !baseline.nullable && live.nullable {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .responseFieldNullability,
            operationID: catalogID,
            path: location,
            message: "相对基线，该节点值变为可 null"
          )
        )
      }
      if isResponseTypeIncompatible(live: live, baseline: baseline, location: location, catalogFields: catalogFields)
      {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .responseFieldTypeMismatch,
            operationID: catalogID,
            path: location,
            message: "相对基线，该节点可产生的值超出 TV 可解码范围"
          )
        )
      }
    } else if !schemaAcceptedJSONTypes(live).isSuperset(of: responseProducedValueSet(baseline)) {
      report.findings.append(
        OpenAPIFinding(
          severity: .failure,
          kind: .bodyFieldTypeMismatch,
          operationID: catalogID,
          path: location,
          message: "相对基线，该节点可接受类型变窄"
        )
      )
    }
  }

  private static func isResponseTypeIncompatible(
    live: OpenAPISchema,
    baseline: OpenAPISchema,
    location: String,
    catalogFields: [TVAPIField]
  ) -> Bool {
    let liveSet = responseProducedValueSet(live)
    let baselineSet = responseProducedValueSet(baseline)
    if let tvType = tvTypeForLocation(location, fields: catalogFields) {
      let decodable = tvDecodableJSONTypes(tvType)
      return !liveSet.isSubset(of: decodable) && baselineSet.isSubset(of: decodable)
    }
    return !liveSet.isSubset(of: baselineSet)
  }

  private static func tvTypeForLocation(_ location: String, fields: [TVAPIField]) -> TVJSONType? {
    let parts = location.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard let root = parts.first, root == "body" || root == "response", parts.count == 2 else {
      return nil
    }
    var token = parts[1]
    if let altRange = token.range(of: "|alt") {
      token = String(token[..<altRange.lowerBound])
    }
    let isItems = token.hasSuffix("[]")
    let name = token.replacingOccurrences(of: "[]", with: "")
    guard let field = fields.first(where: { $0.name == name }) else { return nil }
    if isItems {
      return field.itemType
    }
    return field.jsonType
  }

  private static func compareRequiredSets(
    catalogID: String,
    location: String,
    live: OpenAPISchema,
    baseline: OpenAPISchema,
    direction: CompatibilityDirection,
    catalogFields: [TVAPIField],
    into report: inout OpenAPIContractReport
  ) {
    let removed = baseline.required.subtracting(live.required)
    let added = live.required.subtracting(baseline.required)
    if direction == .response {
      for name in removed.sorted() {
        report.findings.append(
          OpenAPIFinding(
            severity: .failure,
            kind: .responseFieldPresence,
            operationID: catalogID,
            path: "\(location).\(name)",
            message: "相对基线，响应字段从 required 中移除，键可以缺失"
          )
        )
      }
    } else {
      for name in added.sorted() {
        let alwaysSent =
          isRequestCatalogLayer(location)
          && catalogFields.contains { $0.name == name && $0.alwaysSent }
        report.findings.append(
          OpenAPIFinding(
            severity: alwaysSent ? .review : .failure,
            kind: .missingRequiredBodyField,
            operationID: catalogID,
            path: "\(location).\(name)",
            message: "相对基线，请求字段加入 required，键必须出现"
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
      return finding.path == path
        || finding.path.hasPrefix(path)
        || finding.path.hasSuffix(".\(path)")
        || finding.path.hasSuffix("[].\(path)")
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
      let sent = tvSentJSONTypes(tv)
      let accepted = schemaAcceptedJSONTypes(schema)
      if tv == .string || tv == .flexibleString {
        return accepted.contains("string")
      }
      if tv == .integer {
        return accepted.contains("integer") || accepted.contains("number")
          || accepted.contains("string")
      }
      if tv == .boolean || tv == .flexibleBool {
        return accepted.contains("boolean") || accepted.contains("string")
      }
      return sent.isSubset(of: accepted)
    }
    return typesCompatible(tv: tv, schema: schema, direction: .request)
  }

  private static func typesCompatible(
    tv: TVJSONType,
    schema: OpenAPISchema,
    direction: CompatibilityDirection
  ) -> Bool {
    if schema.kind == .opaque || schema.kind == .recursive {
      return tv == .json || tv == .object
    }
    if direction == .response {
      if schema.kind == .union, !schema.alternatives.isEmpty {
        return schema.alternatives.allSatisfy {
          typesCompatible(tv: tv, schema: $0, direction: .response)
        }
      }
      return schemaProducedJSONTypes(schema).isSubset(of: tvDecodableJSONTypes(tv))
    }
    if schema.kind == .union, !schema.alternatives.isEmpty {
      return schema.alternatives.contains {
        typesCompatible(tv: tv, schema: $0, direction: .request)
      }
    }
    return tvSentJSONTypes(tv).isSubset(of: schemaAcceptedJSONTypes(schema))
  }

  private static func tvSentJSONTypes(_ tv: TVJSONType) -> Set<String> {
    switch tv {
    case .string, .flexibleString:
      return ["string"]
    case .integer:
      return ["integer"]
    case .number:
      return ["number", "integer"]
    case .boolean, .flexibleBool:
      return ["boolean"]
    case .array:
      return ["array"]
    case .object:
      return ["object"]
    case .json:
      return ["object", "array"]
    }
  }

  private static func tvDecodableJSONTypes(_ tv: TVJSONType) -> Set<String> {
    switch tv {
    case .string:
      return ["string"]
    case .flexibleString:
      return ["string", "integer", "number"]
    case .integer:
      return ["integer"]
    case .number:
      return ["integer", "number"]
    case .boolean:
      return ["boolean"]
    case .flexibleBool:
      return ["boolean", "integer", "string"]
    case .array:
      return ["array"]
    case .object:
      return ["object"]
    case .json:
      return ["string", "integer", "number", "boolean", "array", "object"]
    }
  }

  private static func responseProducedValueSet(_ schema: OpenAPISchema) -> Set<String> {
    var types = schemaProducedJSONTypes(schema)
    if types.contains("number") {
      types.insert("integer")
    }
    return types
  }

  private static func schemaProducedJSONTypes(_ schema: OpenAPISchema) -> Set<String> {
    if schema.kind == .union, !schema.alternatives.isEmpty {
      return Set(schema.alternatives.flatMap { schemaProducedJSONTypes($0) })
    }
    if schema.kind == .array { return ["array"] }
    if schema.kind == .object { return ["object"] }
    if schema.kind == .opaque || schema.kind == .recursive { return ["object"] }
    return schema.types.subtracting(["null"])
  }

  private static func schemaAcceptedJSONTypes(_ schema: OpenAPISchema) -> Set<String> {
    if schema.kind == .union, !schema.alternatives.isEmpty {
      return Set(schema.alternatives.flatMap { schemaAcceptedJSONTypes($0) })
    }
    var accepted: Set<String> = []
    for type in schema.types.subtracting(["null"]) {
      switch type {
      case "number":
        accepted.formUnion(["number", "integer"])
      case "integer":
        accepted.insert("integer")
      case "string":
        accepted.insert("string")
      case "boolean":
        accepted.insert("boolean")
      case "array":
        accepted.insert("array")
      case "object":
        accepted.insert("object")
      default:
        break
      }
    }
    if accepted.isEmpty {
      if schema.kind == .string { accepted.insert("string") }
      if schema.kind == .integer { accepted.insert("integer") }
      if schema.kind == .number { accepted.formUnion(["number", "integer"]) }
      if schema.kind == .boolean { accepted.insert("boolean") }
      if schema.kind == .array { accepted.insert("array") }
      if schema.kind == .object || schema.kind == .opaque || schema.kind == .recursive {
        accepted.insert("object")
      }
    }
    return accepted
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
