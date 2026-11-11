#if DEBUG
import SwiftUI

/// UI 预览目录中的一个场景。
///
/// 场景通过闭包直接构建真实页面；构建前由场景自己调用
/// `UIPreviewBackend.shared.activate(...)` 安装会话身份与逐接口行为。
struct UIPreviewScene: Identifiable {
  let id: String
  let title: String
  let note: String?
  let content: @MainActor () -> AnyView

  init(
    id: String,
    title: String,
    note: String? = nil,
    content: @escaping @MainActor () -> AnyView
  ) {
    self.id = id
    self.title = title
    self.note = note
    self.content = content
  }
}

/// 目录分组。
struct UIPreviewSection: Identifiable {
  let id: String
  let title: String
  let scenes: [UIPreviewScene]
}

/// 预览目录注册表。各业务域在 `Scenes/` 下提供自己的 section，按需在此汇总。
enum UIPreviewCatalog {
  static var sections: [UIPreviewSection] {
    [
      UIPreviewScenesApp.section,
      UIPreviewScenesTabs.section,
      UIPreviewScenesDetail.section,
      UIPreviewScenesSearch.section,
      UIPreviewScenesSettings.section,
      UIPreviewScenesPlayer.section,
      UIPreviewScenesComponents.section,
    ]
  }

  static var firstSectionID: String {
    sections.first?.id ?? ""
  }

  static func scene(id: String?) -> UIPreviewScene? {
    guard let id, !id.isEmpty else { return nil }
    for section in sections {
      if let scene = section.scenes.first(where: { $0.id == id }) {
        return scene
      }
    }
    return nil
  }
}

/// 预览目录首页：按分组折叠展示全部场景。
struct PreviewCatalogView: View {
  @State private var selectedScene: UIPreviewScene?

  init(initialSceneID: String? = nil) {
    UIPreviewFixtures.resetPreviewState()
    UIPreviewBackend.shared.reset()
    _selectedScene = State(initialValue: UIPreviewCatalog.scene(id: initialSceneID))
  }

  var body: some View {
    ZStack {
      NavigationStack {
        PreviewCatalogHomeView(isActive: selectedScene == nil) { scene in
          selectedScene = scene
        }
        .navigationTitle("UI 预览")
      }
      .opacity(selectedScene == nil ? 1 : 0)
      .disabled(selectedScene != nil)

      if let selectedScene {
        PreviewSceneDestination(scene: selectedScene) {
          self.selectedScene = nil
          UIPreviewFixtures.resetPreviewState()
          UIPreviewBackend.shared.reset()
        }
        .id(selectedScene.id)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.1).ignoresSafeArea())
    .withNotification()
  }
}

private struct PreviewCatalogHomeView: View {
  let isActive: Bool
  let selectScene: (UIPreviewScene) -> Void
  @State private var expandedSectionIDs: Set<String> = []
  @State private var lastFocusedControlID: String?
  @FocusState private var focusedControlID: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 34) {
        ForEach(UIPreviewCatalog.sections) { section in
          VStack(alignment: .leading, spacing: 14) {
            Button {
              toggleSection(section.id)
            } label: {
              Label(
                section.title,
                systemImage: expandedSectionIDs.contains(section.id)
                  ? "chevron.down" : "chevron.right"
              )
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focusedControlID, equals: section.id)

            if expandedSectionIDs.contains(section.id) {
              VStack(spacing: 10) {
                ForEach(section.scenes) { scene in
                  Button {
                    lastFocusedControlID = scene.id
                    selectScene(scene)
                  } label: {
                    VStack(alignment: .leading) {
                      Text(scene.title)
                      if let note = scene.note {
                        Text(note)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .focused($focusedControlID, equals: scene.id)
                }
              }
            }
          }
        }
      }
      .frame(width: 760, alignment: .leading)
      .padding(.vertical, 60)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .onAppear {
      focusedControlID = focusedControlID ?? UIPreviewCatalog.firstSectionID
      lastFocusedControlID = lastFocusedControlID ?? focusedControlID
    }
    .onChange(of: focusedControlID) { _, newValue in
      lastFocusedControlID = newValue ?? lastFocusedControlID
    }
    .onChange(of: isActive) { _, isActive in
      guard isActive else { return }
      focusedControlID =
        lastFocusedControlID ?? focusedControlID ?? UIPreviewCatalog.firstSectionID
    }
  }

  private func toggleSection(_ sectionID: String) {
    if expandedSectionIDs.contains(sectionID) {
      expandedSectionIDs.remove(sectionID)
    } else {
      expandedSectionIDs.insert(sectionID)
    }
  }
}

private struct PreviewSceneDestination: View {
  let scene: UIPreviewScene
  let onExit: () -> Void

  var body: some View {
    scene.content()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(white: 0.1).ignoresSafeArea())
      .onExitCommand(perform: onExit)
  }
}
#endif
