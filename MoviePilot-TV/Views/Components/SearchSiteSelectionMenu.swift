import SwiftUI

/// 搜索站点选择：系统菜单，在原位弹出。
///
/// 「默认」跟随系统设置里的默认站点，「全部站点」显式选择全部，也可以逐个勾选；
/// 选择立即写回 `SiteFilterViewModel`，点一项不收起菜单，选好按 Menu 键关闭；
/// 只在下一次点搜索时生效，不触发重新搜索。
struct SearchSiteSelectionMenu<Label: View>: View {
  @ObservedObject var viewModel: SiteFilterViewModel
  @ViewBuilder let label: () -> Label

  var body: some View {
    Menu {
      SearchSiteSelectionMenuItems(viewModel: viewModel)
    } label: {
      label()
    }
    // 多选：点一项不收起菜单。
    .menuActionDismissBehavior(.disabled)
    // 站点由所在页面负责加载（遵守页面的请求时机）；加载失败可在菜单里重试。
    .menuStyle(.button)
  }
}

/// 搜索站点菜单的选项，放在 `Menu { }` 里用：独立按钮（`SearchSiteSelectionMenu`），
/// 或详情页搜索菜单里「搜索资源」「搜索字幕」的二级菜单。要配 `.menuActionDismissBehavior(.disabled)` 让点一项不收起：
/// 加在外层菜单上，或只加在本视图上（同一菜单里的「开始搜索」照常收起）。
struct SearchSiteSelectionMenuItems: View {
  @ObservedObject var viewModel: SiteFilterViewModel

  var body: some View {
    Section {
      Toggle("默认", isOn: Binding(
        get: { viewModel.selectedSites == nil },
        set: { if $0 { viewModel.selectedSites = nil } }
      ))
      Toggle("全部站点", isOn: Binding(
        get: { viewModel.selectedSites?.isEmpty == true },
        set: { if $0 { viewModel.selectedSites = [] } }
      ))
    }

    // 「默认」时没有显式选择，没有可清除的失效站点。
    MultiSelectionMenuContent(
      options: viewModel.availableSites, id: \.id,
      selected: Binding(
        get: { viewModel.selectedSites ?? [] },
        set: { viewModel.selectedSites = $0 }
      ),
      label: { $0.name },
      sectionTitle: "指定站点"
    ) {
      if viewModel.isLoadingSites {
        Text("正在加载站点…")
      } else if let error = viewModel.siteLoadError {
        Button("\(error) 重新加载") {
          Task { await viewModel.loadSites() }
        }
      } else if viewModel.availableSites.isEmpty {
        Text("暂无可选站点")
      }
    }
  }
}
