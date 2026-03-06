import SwiftUI

/// 支持多选的站点选择表单视图
struct SiteSelectionView: View {
  let availableSites: [Site]
  @Binding var selectedSites: Set<Int>

  var body: some View {
    MultiSelectionSheet(
      options: availableSites,
      id: \.id,
      selected: $selectedSites,
      label: { $0.name }
    )
  }
}

