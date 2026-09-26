import XCTest

@testable import MoviePilot_TV

final class OpenAPIContractOfflineTests: XCTestCase {
  func testParsesRefAndNullableAnyOf() throws {
    let document = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ])
            ]),
            "responses": .object([
              "200": .object([
                "content": .object([
                  "application/json": .object([
                    "schema": .object([
                      "$ref": .string("#/components/schemas/Response_Item_")
                    ])
                  ])
                ])
              ])
            ]),
          ])
        ])
      ],
      schemas: [
        "Response_Item_": .object([
          "type": .string("object"),
          "required": .array([.string("success"), .string("message"), .string("data")]),
          "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "message": .object(["type": .string("string")]),
            "data": .object([
              "anyOf": .array([
                .object(["$ref": .string("#/components/schemas/Item")]),
                .object(["type": .string("null")]),
              ])
            ]),
          ]),
        ]),
        "Item": .object([
          "type": .string("object"),
          "required": .array([.string("name")]),
          "properties": .object([
            "name": .object(["type": .string("string")]),
            "count": .object([
              "anyOf": .array([
                .object(["type": .string("integer")]),
                .object(["type": .string("null")]),
              ])
            ]),
          ]),
        ]),
      ]
    )

    let operation = try XCTUnwrap(
      OpenAPIOperationLoader.load(method: "GET", template: "/sample", document: document)
    )
    XCTAssertEqual(operation.parameters.first?.name, "title")
    XCTAssertEqual(operation.innerDataSchema?.properties["name"]?.kind, .string)
    XCTAssertEqual(operation.innerDataSchema?.properties["count"]?.nullable, true)
  }

  func testMatchesPathTemplatesWithDifferentParameterNames() {
    XCTAssertTrue(
      OpenAPIPathIndex.pathsMatch("/subscribe/{id}", "/api/v1/subscribe/{subscribe_id}")
    )
    XCTAssertFalse(
      OpenAPIPathIndex.pathsMatch("/subscribe/", "/api/v1/subscribe/{subscribe_id}")
    )
    XCTAssertTrue(
      OpenAPIPathIndex.pathsMatch("/system/setting/public/Storages", "/system/setting/public/{key}")
    )
  }

  func testMissingPathIsFailure() throws {
    let live = try makeDocument(paths: [:])
    let catalog = [
      TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .pathMissing })
  }

  func testMissingMethodIsFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": simpleGET()
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.mutation("PUT", "/subscribe/", coverage: [.liveReadOnly])
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .methodMissing })
  }

  func testNewRequiredParameterIsFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/media/search": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ]),
              .object([
                "name": .string("auth_code"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ]),
            ]),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [TVAPIParam.query("title", alwaysSent: true)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .missingRequiredParameter })
  }

  func testUndeclaredTVParameterIsFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/media/search": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ])
            ]),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [
          TVAPIParam.query("title", alwaysSent: true),
          TVAPIParam.query("legacy_source"),
        ],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .undeclaredParameter })
  }

  func testResponseRequiredFieldBecomingNullableAgainstBaselineIsFailure() throws {
    let tokenProperties: [String: JSONValue] = [
      "access_token": .object(["type": .string("string")]),
      "token_type": .object(["type": .string("string")]),
      "user_name": .object(["type": .string("string")]),
    ]
    let baseline = try makeDocument(
      paths: [
        "/api/v1/login/access-token": .object([
          "post": tokenLoginOperation(
            tokenProperties: tokenProperties,
            required: ["access_token", "token_type", "user_name"]
          )
        ])
      ]
    )
    var liveProperties = tokenProperties
    liveProperties["access_token"] = .object([
      "anyOf": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("null")]),
      ])
    ])
    let live = try makeDocument(
      paths: [
        "/api/v1/login/access-token": .object([
          "post": tokenLoginOperation(tokenProperties: liveProperties, required: ["token_type", "user_name"])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.mutation(
        "POST",
        "/login/access-token",
        body: [
          TVAPIFields.field("username", .string, required: true),
          TVAPIFields.field("password", .string, required: true),
        ],
        response: .raw,
        requiredResponse: [TVAPIFields.field("access_token", .string, required: true)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .responseFieldNullability })
  }

  func testUnusedNewEndpointIsInfoNotFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object(["get": simpleGET()]),
        "/api/v1/subscribe/check": .object(["post": simpleGET()]),
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: live, catalog: catalog)
    XCTAssertTrue(report.failures.isEmpty)
    XCTAssertTrue(report.infos.contains { $0.kind == .unusedEndpoint })
  }

  func testRelatedEndpointAddedAgainstBaselineIsReported() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object(["get": simpleGET()])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object(["get": simpleGET()]),
        "/api/v1/subscribe/check": .object(["post": simpleGET()]),
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(report.infos.contains { $0.kind == .relatedEndpointAdded })
    XCTAssertTrue(report.coverageGaps.contains { $0.kind == .relatedUnevaluated })
    XCTAssertFalse(report.failures.contains { $0.kind == .relatedEndpointAdded })
  }

  func testRoundTripNewWritableFieldAgainstBaselineIsReview() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "put": bodyOperation(properties: [
            "name": .object(["type": .string("string")]),
            "type": .object(["type": .string("string")]),
          ])
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "put": bodyOperation(properties: [
            "name": .object(["type": .string("string")]),
            "type": .object(["type": .string("string")]),
            "music_type": .object([
              "anyOf": .array([
                .object(["type": .string("string")]),
                .object(["type": .string("null")]),
              ])
            ]),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.mutation(
        "PUT",
        "/subscribe/",
        body: [
          TVAPIFields.field("name", .string, required: true),
          TVAPIFields.field("type", .string, required: true),
        ],
        roundTrip: true,
        coverage: [.liveSideEffect]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(report.reviews.contains { $0.kind == .newWritableField && $0.path.contains("music_type") })
    XCTAssertTrue(report.hasBlockingFindings)
  }

  func testExceptionSuppressesKnownMismatch() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/media/search": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ]),
              .object([
                "name": .string("media_source"),
                "in": .string("query"),
                "required": .bool(false),
                "schema": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                ]),
              ]),
            ]),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [
          TVAPIParam.query("title", alwaysSent: true),
          TVAPIParam.query("media_source"),
        ],
        coverage: [.liveReadOnly]
      )
    ]
    let withoutException = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(withoutException.failures.contains { $0.kind == .parameterTypeMismatch })

    let withException = OpenAPIContractChecker.check(
      live: live,
      baseline: nil,
      catalog: catalog,
      exceptions: [
        OpenAPIException(
          id: "media.search.media_source-query-array",
          operation: "GET /media/search",
          kind: .parameterTypeMismatch,
          path: "query.media_source",
          reason: "test"
        )
      ]
    )
    XCTAssertTrue(withException.failures.filter { $0.kind == .parameterTypeMismatch }.isEmpty)
    XCTAssertTrue(withException.infos.contains { $0.excepted && $0.kind == .parameterTypeMismatch })
  }

  func testHTMLResponseIsDetected() {
    let html = Data("<!DOCTYPE html><html><body>login</body></html>".utf8)
    XCTAssertTrue(OpenAPIContractSupport.isProbablyHTML(data: html, contentType: "text/html"))
    XCTAssertTrue(OpenAPIContractSupport.isProbablyHTML(data: html, contentType: "application/json"))
    XCTAssertFalse(
      OpenAPIContractSupport.isProbablyHTML(
        data: Data("{\"openapi\":\"3.1.0\"}".utf8),
        contentType: "application/json"
      )
    )
  }

  func testUnsupportedSchemaIsFailureNotPass() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": .object([
            "responses": successResponse(
              schema: .object([
                "not": .object(["type": .string("string")])
              ])
            )
          ])
        ])
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .unverifiedSchema })
  }

  func testDescriptionOnlyChangeIsNotFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": .object([
            "summary": .string("old"),
            "description": .string("old docs"),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": .object([
            "summary": .string("new"),
            "description": .string("new docs"),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(report.failures.isEmpty)
    XCTAssertTrue(report.reviews.isEmpty)
  }

  func testCatalogOperationIDsAreUnique() {
    let ids = TVAPIContractCatalog.operations.map(\.operationID)
    XCTAssertEqual(ids.count, Set(ids).count, ids.joined(separator: "\n"))
  }

  func testCommittedExceptionsAndBaselineParse() throws {
    let exceptions = try OpenAPIContractSupport.loadExceptions()
    XCTAssertTrue(exceptions.contains { $0.id == "media.search.media_source-query-array" })
    XCTAssertTrue(exceptions.contains { $0.id == "subscribe.fork.id-int-or-string" })

    let baseline = try OpenAPIContractSupport.loadDocument("openapi-baseline.json")
    XCTAssertEqual(baseline.title, "MoviePilot")
    XCTAssertEqual(baseline.version, "v3.0.8")
    XCTAssertFalse(baseline.paths.isEmpty)

    let fork = try XCTUnwrap(
      OpenAPIOperationLoader.load(
        method: "POST",
        template: "/subscribe/fork",
        document: baseline
      )
    )
    let forkData = try XCTUnwrap(fork.innerDataSchema)
    XCTAssertEqual(forkData.ref, "#/components/schemas/IdData")
    let forkID = try XCTUnwrap(forkData.properties["id"])
    XCTAssertEqual(forkID.kind, .union)
    XCTAssertEqual(forkID.types, ["integer", "string", "null"])
    XCTAssertTrue(forkID.nullable)
  }

  func testSourceScannerMapsInterpolatedSubscribePath() {
    let literals = TVAPIContractSourceScanner.extractPathLiterals(
      from: #"let endpoint = "/subscribe/\(id)""#
    )
    XCTAssertEqual(literals, ["/subscribe/\\(id)"])
    let normalized = TVAPIContractSourceScanner.normalizeSourcePath("/subscribe/\\(id)")
    XCTAssertTrue(OpenAPIPathIndex.pathsMatch(normalized, "/subscribe/{subscribe_id}"))
  }

  func testResponseRequiredRemovedWithoutNullableChangeIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: ["name": .object(["type": .string("string")])],
            required: ["name"]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: ["name": .object(["type": .string("string")])],
            required: []
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/subscribe/",
        requiredResponse: [TVAPIFields.field("name", .string, required: true)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldPresence && $0.path.contains("name")
      },
      report.formattedDescription
    )
  }

  func testRequestFieldBecomingRequiredWhileStillNullableIsFailureIfNotAlwaysSent() throws {
    let optionalNote: [String: JSONValue] = [
      "name": .object(["type": .string("string")]),
      "note": .object([
        "anyOf": .array([
          .object(["type": .string("string")]),
          .object(["type": .string("null")]),
        ])
      ]),
    ]
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "put": bodyOperation(properties: optionalNote, required: [])
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "put": bodyOperation(properties: optionalNote, required: ["note"])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.mutation(
        "PUT",
        "/subscribe/",
        body: [
          TVAPIFields.field("name", .string, required: true),
          TVAPIFields.field("note", .string, alwaysSent: false),
        ],
        coverage: [.liveSideEffect]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains { finding in
        finding.kind == OpenAPIFindingKind.missingRequiredBodyField
          && finding.path.contains("note")
      },
      report.formattedDescription
    )
  }

  func testArrayItemNullabilityChangeIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: ["name": .object(["type": .string("string")])],
            required: ["name"]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: [
              "name": .object([
                "anyOf": .array([
                  .object(["type": .string("string")]),
                  .object(["type": .string("null")]),
                ])
              ])
            ],
            required: ["name"]
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/subscribe/",
        requiredResponse: [TVAPIFields.field("name", .string, required: true)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldNullability && $0.path.contains("name")
      },
      report.formattedDescription
    )
  }

  func testPagedListItemTypeChangeIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/history/transfer": .object([
          "get": objectGET(
            properties: [
              "total": .object(["type": .string("integer")]),
              "list": .object([
                "type": .string("array"),
                "items": .object([
                  "type": .string("object"),
                  "properties": .object([
                    "id": .object(["type": .string("integer")]),
                    "title": .object(["type": .string("string")]),
                  ]),
                  "required": .array([.string("id")]),
                ]),
              ]),
            ],
            required: ["list", "total"]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/history/transfer": .object([
          "get": objectGET(
            properties: [
              "total": .object(["type": .string("integer")]),
              "list": .object([
                "type": .string("array"),
                "items": .object([
                  "type": .string("object"),
                  "properties": .object([
                    "id": .object(["type": .string("string")]),
                    "title": .object(["type": .string("string")]),
                  ]),
                  "required": .array([.string("id")]),
                ]),
              ]),
            ],
            required: ["list", "total"]
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/history/transfer",
        dependedResponse: [
          TVAPIFields.field("list", .array),
          TVAPIFields.field("total", .integer),
        ],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("list") && $0.path.contains("id")
      },
      report.formattedDescription
    )
  }

  func testPrimitiveArrayItemTypeChangeIsFailure() throws {
    func subscribeWithSiteItems(_ itemType: String) -> JSONValue {
      arrayGET(
        itemProperties: [
          "sites": .object([
            "type": .string("array"),
            "items": .object(["type": .string(itemType)]),
          ])
        ],
        required: []
      )
    }
    let baseline = try makeDocument(
      paths: ["/api/v1/subscribe/": .object(["get": subscribeWithSiteItems("integer")])]
    )
    let live = try makeDocument(
      paths: ["/api/v1/subscribe/": .object(["get": subscribeWithSiteItems("string")])]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/subscribe/",
        dependedResponse: [TVAPIFields.field("sites", .array, itemType: .integer)],
        coverage: [.liveReadOnly]
      )
    ]
    let withBaseline = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      withBaseline.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("sites")
      },
      withBaseline.formattedDescription
    )
    let liveOnly = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(
      liveOnly.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("sites")
      },
      liveOnly.formattedDescription
    )
  }

  func testPrimitiveArrayItemBecomingNullableIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: [
              "sites": .object([
                "type": .string("array"),
                "items": .object(["type": .string("integer")]),
              ])
            ],
            required: []
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": arrayGET(
            itemProperties: [
              "sites": .object([
                "type": .string("array"),
                "items": .object([
                  "anyOf": .array([
                    .object(["type": .string("integer")]),
                    .object(["type": .string("null")]),
                  ])
                ]),
              ])
            ],
            required: []
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/subscribe/",
        dependedResponse: [TVAPIFields.field("sites", .array, itemType: .integer)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldNullability && $0.path.contains("sites")
      },
      report.formattedDescription
    )
  }

  func testUnionNonFirstBranchNestedChangeIsFailure() throws {
    func profileUnion(secondIDType: String) -> JSONValue {
      objectGET(
        properties: [
          "result": .object([
            "anyOf": .array([
              .object([
                "type": .string("object"),
                "properties": .object([
                  "profile": .object([
                    "type": .string("object"),
                    "properties": .object([
                      "id": .object(["type": .string("integer")])
                    ]),
                  ])
                ]),
              ]),
              .object([
                "type": .string("object"),
                "properties": .object([
                  "profile": .object([
                    "type": .string("object"),
                    "properties": .object([
                      "id": .object(["type": .string(secondIDType)])
                    ]),
                  ])
                ]),
              ]),
            ])
          ])
        ],
        required: []
      )
    }
    let baseline = try makeDocument(
      paths: ["/api/v1/sample": .object(["get": profileUnion(secondIDType: "integer")])]
    )
    let live = try makeDocument(
      paths: ["/api/v1/sample": .object(["get": profileUnion(secondIDType: "string")])]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/sample",
        dependedResponse: [TVAPIFields.field("result", .object)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("id")
      },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.failures.contains { $0.kind == .unverifiedSchema },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.reviews.contains { $0.kind == .unverifiedSchema },
      report.formattedDescription
    )
  }

  func testQueryStringBecomingIntegerIsFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/media/search": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("integer")]),
              ])
            ]),
            "responses": successResponse(schema: .object(["type": .string("object")])),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [TVAPIParam.query("title", alwaysSent: true)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .parameterTypeMismatch })
  }

  func testIntegerResponseBecomingNumberIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/history/transfer": .object([
          "get": objectGET(
            properties: ["total": .object(["type": .string("integer")])],
            required: ["total"]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/history/transfer": .object([
          "get": objectGET(
            properties: ["total": .object(["type": .string("number")])],
            required: ["total"]
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/history/transfer",
        dependedResponse: [TVAPIFields.field("total", .integer)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("total")
      },
      report.formattedDescription
    )
  }

  func testNumberNarrowingToIntegerIsCompatibleForDouble() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/dashboard/storage": .object([
          "get": objectGET(
            properties: ["used_storage": .object(["type": .string("number")])],
            required: ["used_storage"]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/dashboard/storage": .object([
          "get": objectGET(
            properties: ["used_storage": .object(["type": .string("integer")])],
            required: ["used_storage"]
          )
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/dashboard/storage",
        dependedResponse: [TVAPIFields.field("used_storage", .number)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertFalse(
      report.failures.contains { $0.path.contains("used_storage") },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.reviews.contains { $0.path.contains("used_storage") },
      report.formattedDescription
    )
  }

  func testUnionResponseRequiresEveryBranch() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/media/search": .object([
          "get": .object([
            "parameters": .array([
              .object([
                "name": .string("title"),
                "in": .string("query"),
                "required": .bool(true),
                "schema": .object(["type": .string("string")]),
              ])
            ]),
            "responses": successResponse(
              schema: .object([
                "type": .string("array"),
                "items": .object([
                  "oneOf": .array([
                    .object([
                      "type": .string("object"),
                      "properties": .object([
                        "year": .object(["type": .string("string")])
                      ]),
                    ]),
                    .object([
                      "type": .string("object"),
                      "properties": .object([
                        "year": .object(["type": .string("integer")])
                      ]),
                    ]),
                  ])
                ]),
              ])
            ),
          ])
        ])
      ]
    )
    let catalog = [
      TVAPIOperationBuilder.get(
        "/media/search",
        query: [TVAPIParam.query("title", alwaysSent: true)],
        dependedResponse: [TVAPIFields.field("year", .string)],
        coverage: [.liveReadOnly]
      )
    ]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("year")
      },
      report.formattedDescription
    )
  }

  func testJSONSuccessResponseMissingIsFailure() throws {
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": .object([
            "responses": .object([
              "204": .object(["description": .string("No Content")])
            ])
          ])
        ])
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: nil, catalog: catalog)
    XCTAssertTrue(report.failures.contains { $0.kind == .unverifiedSchema })
  }

  func testJSONSuccessResponseDisappearingAgainstBaselineIsFailure() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object(["get": simpleGET()])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/subscribe/": .object([
          "get": .object([
            "responses": .object([
              "204": .object(["description": .string("No Content")])
            ])
          ])
        ])
      ]
    )
    let catalog = [TVAPIOperationBuilder.get("/subscribe/", coverage: [.liveReadOnly])]
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: catalog)
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .unverifiedSchema || $0.kind == .responseStructureChanged
      },
      report.formattedDescription
    )
  }

  func testDownloadAddNestedOptionalFieldTypeChangeIsFailure() throws {
    let catalog = try downloadAddCatalog()
    let baseline = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(torrentProperties: torrentInProperties(titleType: "string"))
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(torrentProperties: torrentInProperties(titleType: "integer"))
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: [catalog])
    XCTAssertTrue(
      report.failures.contains {
        $0.operationID == "POST /download/add"
          && $0.kind == .bodyFieldTypeMismatch
          && $0.path.contains("torrent_in")
          && $0.path.contains("title")
      },
      report.formattedDescription
    )
  }

  func testDownloadAddUnchangedNestedObjectHasNoBlockingFindings() throws {
    let catalog = try downloadAddCatalog()
    let document = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(torrentProperties: torrentInProperties(titleType: "string"))
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(live: document, baseline: document, catalog: [catalog])
    XCTAssertTrue(
      report.failures.filter { $0.operationID == "POST /download/add" }.isEmpty,
      report.formattedDescription
    )
    XCTAssertTrue(
      report.reviews.filter { $0.operationID == "POST /download/add" }.isEmpty,
      report.formattedDescription
    )
  }

  func testDownloadAddNestedSameNameFieldDoesNotInheritRootType() throws {
    let catalog = try downloadAddCatalog()
    let nestedDownloader = nullableSchema(type: "integer")
    let baseline = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(
            torrentProperties: torrentInProperties(titleType: "string", extra: [
              "downloader": nestedDownloader
            ])
          )
        ])
      ]
    )
    let unchanged = OpenAPIContractChecker.check(live: baseline, baseline: baseline, catalog: [catalog])
    XCTAssertFalse(
      unchanged.failures.contains { $0.path.contains("torrent_in") && $0.path.contains("downloader") },
      unchanged.formattedDescription
    )
    XCTAssertFalse(
      unchanged.reviews.contains { $0.path.contains("torrent_in") && $0.path.contains("downloader") },
      unchanged.formattedDescription
    )

    let live = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(
            torrentProperties: torrentInProperties(titleType: "string", extra: [
              "downloader": nullableSchema(type: "string")
            ])
          )
        ])
      ]
    )
    let changed = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: [catalog])
    XCTAssertTrue(
      changed.failures.contains {
        $0.operationID == "POST /download/add"
          && $0.kind == .bodyFieldTypeMismatch
          && $0.path.contains("torrent_in")
          && $0.path.contains("downloader")
      },
      changed.formattedDescription
    )
    XCTAssertFalse(
      changed.failures.contains {
        $0.path == "body.downloader" || $0.path.hasSuffix(".downloader") && !$0.path.contains("torrent_in")
      },
      changed.formattedDescription
    )
  }

  func testDownloadAddUncataloguedRootOptionalFieldChangeIsNotFailure() throws {
    let catalog = try downloadAddCatalog()
    XCTAssertFalse(catalog.bodyFields.contains { $0.name == "music_type" })
    let baseline = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(
            torrentProperties: torrentInProperties(titleType: "string"),
            extraRoot: ["music_type": nullableSchema(type: "string")]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(
            torrentProperties: torrentInProperties(titleType: "string"),
            extraRoot: ["music_type": nullableSchema(type: "integer")]
          )
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: [catalog])
    XCTAssertFalse(
      report.failures.contains { $0.path.contains("music_type") },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.reviews.contains { $0.path.contains("music_type") },
      report.formattedDescription
    )
  }

  func testDownloadAddNestedNewRequiredFieldIsFailure() throws {
    let catalog = try downloadAddCatalog()
    let properties = torrentInProperties(titleType: "string")
    let baseline = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(torrentProperties: properties, torrentRequired: [])
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/download/add": .object([
          "post": downloadAddOperation(torrentProperties: properties, torrentRequired: ["title"])
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(live: live, baseline: baseline, catalog: [catalog])
    XCTAssertTrue(
      report.failures.contains {
        $0.operationID == "POST /download/add"
          && $0.kind == .missingRequiredBodyField
          && $0.path.contains("torrent_in")
          && $0.path.contains("title")
      },
      report.formattedDescription
    )
  }

  func testAnyOfBranchReorderIsNotBlocking() throws {
    try assertUnionReorderIsNotBlocking(combinator: "anyOf")
  }

  func testOneOfBranchReorderIsNotBlocking() throws {
    try assertUnionReorderIsNotBlocking(combinator: "oneOf")
  }

  func testUnionReorderDoesNotHideNestedChange() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "anyOf",
            branches: [
              profileBranch(idType: "integer"),
              profileBranch(idType: "string"),
            ]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "anyOf",
            branches: [
              profileBranch(idType: "boolean"),
              profileBranch(idType: "integer"),
            ]
          )
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(
      live: live,
      baseline: baseline,
      catalog: [sampleResultCatalog()]
    )
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .responseFieldTypeMismatch && $0.path.contains("id")
      },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.failures.contains { $0.kind == .unverifiedSchema },
      report.formattedDescription
    )
  }

  func testUnionBranchCountChangeIsUnverified() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "anyOf",
            branches: [
              profileBranch(idType: "integer"),
              profileBranch(idType: "string"),
            ]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "anyOf",
            branches: [
              profileBranch(idType: "integer"),
              profileBranch(idType: "string"),
              profileBranch(idType: "boolean"),
            ]
          )
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(
      live: live,
      baseline: baseline,
      catalog: [sampleResultCatalog()]
    )
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .unverifiedSchema
          && $0.operationID == "GET /sample"
          && $0.path.contains("result")
      },
      report.formattedDescription
    )
  }

  func testUnionDescriptionAndKeyOrderDoNotAffectBranchIdentity() throws {
    let baseline = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "oneOf",
            branches: [
              profileBranch(idType: "integer", description: "int profile", extraFirst: false),
              profileBranch(idType: "string", description: "string profile", extraFirst: false),
            ]
          )
        ])
      ]
    )
    let live = try makeDocument(
      paths: [
        "/api/v1/sample": .object([
          "get": unionResultGET(
            combinator: "oneOf",
            branches: [
              profileBranch(idType: "string", description: "renamed string", extraFirst: true),
              profileBranch(idType: "integer", description: "renamed int", extraFirst: true),
            ]
          )
        ])
      ]
    )
    let report = OpenAPIContractChecker.check(
      live: live,
      baseline: baseline,
      catalog: [sampleResultCatalog()]
    )
    XCTAssertTrue(
      report.failures.filter { $0.operationID == "GET /sample" }.isEmpty,
      report.formattedDescription
    )
    XCTAssertTrue(
      report.reviews.filter { $0.operationID == "GET /sample" }.isEmpty,
      report.formattedDescription
    )
  }

  func testAnyOfVersusOneOfSameBranchesIsUnverified() throws {
    let branches = [
      profileBranch(idType: "integer"),
      profileBranch(idType: "string"),
    ]
    let baseline = try makeDocument(
      paths: ["/api/v1/sample": .object(["get": unionResultGET(combinator: "anyOf", branches: branches)])]
    )
    let live = try makeDocument(
      paths: ["/api/v1/sample": .object(["get": unionResultGET(combinator: "oneOf", branches: branches)])]
    )
    let report = OpenAPIContractChecker.check(
      live: live,
      baseline: baseline,
      catalog: [sampleResultCatalog()]
    )
    XCTAssertTrue(
      report.failures.contains {
        $0.kind == .unverifiedSchema && $0.path.contains("result")
      },
      report.formattedDescription
    )
  }

  func testRecursiveRequestArrayItemAgainstItselfIsNotNarrowing() throws {
    let fileItem = JSONValue.object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")]),
        "children": .object([
          "anyOf": .array([
            .object([
              "type": .string("array"),
              "items": .object(["$ref": .string("#/components/schemas/FileItem")]),
            ]),
            .object(["type": .string("null")]),
          ])
        ]),
      ]),
    ])
    let document = try makeDocument(
      paths: [
        "/api/v1/transfer/manual": .object([
          "post": bodyOperation(
            properties: [
              "fileitem": .object(["$ref": .string("#/components/schemas/FileItem")]),
              "transfer_type": .object(["type": .string("string")]),
            ]
          )
        ])
      ],
      schemas: ["FileItem": fileItem]
    )
    let catalog = [
      TVAPIOperationBuilder.mutation(
        "POST",
        "/transfer/manual",
        body: [
          TVAPIFields.field("fileitem", .object),
          TVAPIFields.field("transfer_type", .string, alwaysSent: true),
        ],
        coverage: [.urlProtocol]
      )
    ]
    let report = OpenAPIContractChecker.check(live: document, baseline: document, catalog: catalog)
    XCTAssertFalse(
      report.failures.contains { $0.path.contains("children") || $0.kind == .bodyFieldTypeMismatch },
      report.formattedDescription
    )
    XCTAssertFalse(
      report.reviews.contains { $0.path.contains("children") || $0.kind == .bodyFieldTypeMismatch },
      report.formattedDescription
    )
  }

  func testUnchangedCommittedBaselineHasNoBlockingFindings() throws {
    let baseline = try OpenAPIContractSupport.loadDocument("openapi-baseline.json")
    let exceptions = try OpenAPIContractSupport.loadExceptions()
    let report = OpenAPIContractChecker.check(
      live: baseline,
      baseline: baseline,
      catalog: TVAPIContractCatalog.operations,
      exceptions: exceptions
    )
    XCTAssertTrue(
      report.failures.isEmpty,
      report.formattedDescription
    )
    XCTAssertTrue(
      report.reviews.isEmpty,
      report.formattedDescription
    )
  }
}

@MainActor
final class OpenAPIContractCatalogIntegrityTests: XCTestCase {
  func testProductionAPIPathsAreRegisteredInCatalog() {
    let gaps = TVAPIContractSourceScanner.coverageGaps()
    XCTAssertTrue(
      gaps.filter { $0.kind == .sourceUnregistered }.isEmpty,
      gaps.map { "\($0.operationID): \($0.message)" }.joined(separator: "\n")
    )
  }

  @MainActor
  func testManualTransferCatalogIncludesEncodedTransferType() throws {
    let form = ReorganizeForm(
      fileitem: FileItem(name: "movie.mkv", path: "/downloads/movie.mkv", type: "file", size: 1),
      fileitems: nil,
      logid: 7,
      target_storage: "local",
      transfer_type: "copy",
      target_path: "/media",
      min_filesize: 0,
      scrape: false,
      from_history: false
    )
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(form))
    let encoded = try XCTUnwrap(object as? [String: Any])
    let catalog = try XCTUnwrap(
      TVAPIContractCatalog.operations.first { $0.operationID == "POST /transfer/manual" }
    )
    let names = Set(catalog.bodyFields.map(\.name))
    XCTAssertTrue(names.contains("transfer_type"))
    let missing = encoded.keys.filter { !names.contains($0) }.sorted()
    XCTAssertTrue(missing.isEmpty, "实际编码的请求字段未登记：\(missing.joined(separator: ", "))")
    XCTAssertEqual(encoded["transfer_type"] as? String, "copy")
  }
}

private func makeDocument(
  paths: [String: JSONValue],
  schemas: [String: JSONValue] = [:]
) throws -> OpenAPIDocument {
  try OpenAPIDocument.parse(
    root: .object([
      "openapi": .string("3.1.0"),
      "info": .object([
        "title": .string("MoviePilot"),
        "version": .string("v3.0.4"),
      ]),
      "paths": .object(paths),
      "components": .object(["schemas": .object(schemas)]),
    ])
  )
}

private func simpleGET() -> JSONValue {
  .object([
    "responses": successResponse(schema: .object(["type": .string("object")]))
  ])
}

private func bodyOperation(
  properties: [String: JSONValue],
  required: [String] = []
) -> JSONValue {
  .object([
    "requestBody": .object([
      "required": .bool(true),
      "content": .object([
        "application/json": .object([
          "schema": .object([
            "type": .string("object"),
            "required": .array(required.map { .string($0) }),
            "properties": .object(properties),
          ])
        ])
      ]),
    ]),
    "responses": successResponse(schema: .object(["type": .string("object")])),
  ])
}

private func arrayGET(
  itemProperties: [String: JSONValue],
  required: [String]
) -> JSONValue {
  .object([
    "responses": successResponse(
      schema: .object([
        "type": .string("array"),
        "items": .object([
          "type": .string("object"),
          "required": .array(required.map { .string($0) }),
          "properties": .object(itemProperties),
        ]),
      ])
    )
  ])
}

private func objectGET(
  properties: [String: JSONValue],
  required: [String]
) -> JSONValue {
  .object([
    "responses": successResponse(
      schema: .object([
        "type": .string("object"),
        "required": .array(required.map { .string($0) }),
        "properties": .object(properties),
      ])
    )
  ])
}

private func tokenLoginOperation(
  tokenProperties: [String: JSONValue],
  required: [String]
) -> JSONValue {
  .object([
    "requestBody": .object([
      "required": .bool(true),
      "content": .object([
        "application/x-www-form-urlencoded": .object([
          "schema": .object([
            "type": .string("object"),
            "required": .array([.string("username"), .string("password")]),
            "properties": .object([
              "username": .object(["type": .string("string")]),
              "password": .object(["type": .string("string")]),
            ]),
          ])
        ])
      ]),
    ]),
    "responses": successResponse(
      schema: .object([
        "type": .string("object"),
        "required": .array(required.map { .string($0) }),
        "properties": .object(tokenProperties),
      ])
    ),
  ])
}

private func successResponse(schema: JSONValue) -> JSONValue {
  .object([
    "200": .object([
      "content": .object([
        "application/json": .object([
          "schema": schema
        ])
      ])
    ])
  ])
}

private func downloadAddCatalog() throws -> TVAPIOperation {
  try XCTUnwrap(
    TVAPIContractCatalog.operations.first { $0.operationID == "POST /download/add" }
  )
}

private func sampleResultCatalog() -> TVAPIOperation {
  TVAPIOperationBuilder.get(
    "/sample",
    dependedResponse: [TVAPIFields.field("result", .object)],
    coverage: [.liveReadOnly]
  )
}

private func nullableSchema(type: String) -> JSONValue {
  .object([
    "anyOf": .array([
      .object(["type": .string(type)]),
      .object(["type": .string("null")]),
    ])
  ])
}

private func torrentInProperties(
  titleType: String,
  extra: [String: JSONValue] = [:]
) -> [String: JSONValue] {
  var properties: [String: JSONValue] = [
    "site": nullableSchema(type: "string"),
    "title": nullableSchema(type: titleType),
    "enclosure": nullableSchema(type: "string"),
  ]
  for (name, schema) in extra {
    properties[name] = schema
  }
  return properties
}

private func downloadAddOperation(
  torrentProperties: [String: JSONValue],
  extraRoot: [String: JSONValue] = [:],
  torrentRequired: [String] = [],
  rootRequired: [String] = ["torrent_in"]
) -> JSONValue {
  var properties: [String: JSONValue] = [
    "torrent_in": .object([
      "type": .string("object"),
      "required": .array(torrentRequired.map { .string($0) }),
      "properties": .object(torrentProperties),
    ]),
    "downloader": nullableSchema(type: "string"),
    "save_path": nullableSchema(type: "string"),
  ]
  for (name, schema) in extraRoot {
    properties[name] = schema
  }
  return bodyOperation(properties: properties, required: rootRequired)
}

private func unionResultGET(combinator: String, branches: [JSONValue]) -> JSONValue {
  objectGET(
    properties: [
      "result": .object([
        combinator: .array(branches)
      ])
    ],
    required: []
  )
}

private func profileBranch(
  idType: String,
  description: String? = nil,
  extraFirst: Bool = false
) -> JSONValue {
  let idSchema: JSONValue = .object(["type": .string(idType)])
  let nameSchema: JSONValue = .object(["type": .string("string")])
  let profileProperties: [String: JSONValue]
  if extraFirst {
    profileProperties = ["name": nameSchema, "id": idSchema]
  } else {
    profileProperties = ["id": idSchema, "name": nameSchema]
  }
  var object: [String: JSONValue] = [
    "type": .string("object"),
    "properties": .object([
      "profile": .object([
        "type": .string("object"),
        "properties": .object(profileProperties),
      ])
    ]),
  ]
  if let description {
    object["description"] = .string(description)
  }
  return .object(object)
}

private func assertUnionReorderIsNotBlocking(
  combinator: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let baseline = try makeDocument(
    paths: [
      "/api/v1/sample": .object([
        "get": unionResultGET(
          combinator: combinator,
          branches: [
            profileBranch(idType: "integer"),
            profileBranch(idType: "string"),
          ]
        )
      ])
    ]
  )
  let live = try makeDocument(
    paths: [
      "/api/v1/sample": .object([
        "get": unionResultGET(
          combinator: combinator,
          branches: [
            profileBranch(idType: "string"),
            profileBranch(idType: "integer"),
          ]
        )
      ])
    ]
  )
  let report = OpenAPIContractChecker.check(
    live: live,
    baseline: baseline,
    catalog: [sampleResultCatalog()]
  )
  XCTAssertTrue(
    report.failures.filter { $0.operationID == "GET /sample" }.isEmpty,
    report.formattedDescription,
    file: file,
    line: line
  )
  XCTAssertTrue(
    report.reviews.filter { $0.operationID == "GET /sample" }.isEmpty,
    report.formattedDescription,
    file: file,
    line: line
  )
}
