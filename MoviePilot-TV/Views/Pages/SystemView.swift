import SwiftUI

struct SystemView: View {

  @StateObject private var viewModel = SystemViewModel()
  @State private var showSiteSelection = false

  var body: some View {
    NavigationStack {
      List {
        Section(header: Text("状态")) {
          LabeledContent("登录状态") {
            Text(viewModel.storageDescription)
              .foregroundStyle(statusColor)
              .animation(.default, value: viewModel.storageMechanism)
          }

          if !viewModel.serverURL.isEmpty {
            LabeledContent("连接信息") {
              VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.serverURL)

                HStack(spacing: 4) {
                  if !viewModel.username.isEmpty {
                    Image(systemName: "person.fill")
                    Text(viewModel.username)
                  }
                  if let version = viewModel.backendVersion {
                    if !viewModel.username.isEmpty {
                      Text("·")
                    }
                    Text("\(version)")
                  }
                }
                .font(.caption)
              }
              .foregroundColor(.secondary)
            }
          }
        }

        Section(header: Text("资源搜索")) {
          Button(action: {
            showSiteSelection = true
          }) {
            LabeledContent("默认搜索站点") {
              if viewModel.isLoadingSites {
                ProgressView()
                  .controlSize(.small)
              } else {
                Text(siteButtonLabel)
              }
            }
          }
          .foregroundColor(.primary)
        }

        Section(header: Text("详情加载页")) {
          Toggle(
            isOn: Binding(
              get: { viewModel.waitMediaDetailBackgroundImage },
              set: { viewModel.waitMediaDetailBackgroundImage = $0 }
            )
          ) {
            Text("等待背景海报加载")
          }
        }

        Section(header: Text("搜索过滤"), footer: Text("搜索结果将先经过硬过滤去除不符合条件的资源，再经过软过滤将剩余不符合条件的资源灰置于末尾。"))
        {
          if viewModel.isLoadingRules {
            HStack {
              ProgressView()
                .controlSize(.small)
                .padding(.trailing, 8)
              Text("正在加载规则...")
                .foregroundColor(.secondary)
            }
          } else if viewModel.customFilterRules.isEmpty {
            Text("暂无自定义过滤规则")
              .foregroundColor(.secondary)
          } else {
            // 硬过滤规则
            let hardRuleBinding = Binding<String>(
              get: { viewModel.selectedHardFilterRuleId ?? "__none__" },
              set: { newValue in
                viewModel.selectedHardFilterRuleId = (newValue == "__none__") ? nil : newValue
              }
            )

            Picker(selection: hardRuleBinding) {
              Text("不过滤")
                .tag("__none__")

              ForEach(viewModel.customFilterRules) { rule in
                ruleLabel(rule)
                  .tag(rule.id)
              }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("硬过滤")
                Text("完全排除不符合条件的资源")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 4)
            }
            .pickerStyle(.navigationLink)

            // 软过滤规则
            let softRuleBinding = Binding<String>(
              get: { viewModel.selectedSoftFilterRuleId ?? "__none__" },
              set: { newValue in
                viewModel.selectedSoftFilterRuleId = (newValue == "__none__") ? nil : newValue
              }
            )

            Picker(selection: softRuleBinding) {
              Text("不过滤")
                .tag("__none__")

              ForEach(viewModel.customFilterRules) { rule in
                ruleLabel(rule)
                  .tag(rule.id)
              }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("软过滤")
                Text("将不符合条件的资源灰置于列表末尾")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 4)
            }
            .pickerStyle(.navigationLink)
          }

          Button(action: {
            Task {
              await viewModel.loadCustomFilterRules()
            }
          }) {
            HStack {
              if viewModel.isLoadingRules {
                ProgressView()
                  .controlSize(.small)
                  .padding(.trailing, 8)
              }
              Text("刷新规则列表")
              Spacer()
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(viewModel.isLoadingRules)
        }

        Section(header: Text("账户"), footer: Text(viewModel.refreshMessage ?? "")) {
          Button(action: {
            Task {
              await viewModel.relogin()
            }
          }) {
            HStack {
              if viewModel.isRefreshing {
                ProgressView()
                  .controlSize(.small)
                  .padding(.trailing, 8)
              }
              Text("重新登录凭据")
              Spacer()
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(viewModel.isRefreshing)

          Button(action: {
            APIService.shared.logout()
            // 登出后立即刷新状态
            viewModel.checkKeychainStatus()
          }) {
            HStack {
              Text("退出登录")
                .foregroundColor(.red)
              Spacer()
              Image(systemName: "rectangle.portrait.and.arrow.right")
                .foregroundColor(.red)
            }
          }
        }
      }
      .onAppear {
        // 视图每次出现时都刷新状态，确保与实际情况同步
        viewModel.checkKeychainStatus()
      }
      .task {
        // 加载系统环境信息
        await viewModel.loadSystemInfo()
        // 加载自定义过滤规则
        await viewModel.loadCustomFilterRules()
        // 加载站点列表
        await viewModel.loadSites()
      }
      .sheet(isPresented: $showSiteSelection) {
        MultiSelectionSheet(
          options: viewModel.availableSites,
          id: \.id,
          selected: Binding(
            get: { viewModel.defaultSearchSites },
            set: { viewModel.defaultSearchSites = $0 }
          ),
          label: { $0.name }
        )
      }
    }
  }

  private var siteButtonLabel: String {
    if viewModel.defaultSearchSites.isEmpty {
      return "全部站点"
    } else if viewModel.defaultSearchSites.count == 1 {
      if let site = viewModel.availableSites.first(where: {
        viewModel.defaultSearchSites.contains($0.id)
      }) {
        return site.name
      }
      return "1 个站点"
    } else {
      return "\(viewModel.defaultSearchSites.count) 个站点"
    }
  }

  private var statusColor: Color {
    switch viewModel.storageMechanism {
    case .keychain:
      return .green
    case .userDefaults:
      return .orange
    case .none:
      return .secondary
    }
  }

  /// 规则标签：显示规则名称和包含的条件摘要
  @ViewBuilder
  private func ruleLabel(_ rule: CustomRule) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(rule.name)
      let details = ruleDetailParts(rule)
      if !details.isEmpty {
        Text(details.joined(separator: " · "))
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
  }

  /// 生成规则条件摘要
  private func ruleDetailParts(_ rule: CustomRule) -> [String] {
    var parts: [String] = []
    if let include = rule.include, !include.isEmpty {
      parts.append("包含: \(include)")
    }
    if let exclude = rule.exclude, !exclude.isEmpty {
      parts.append("排除: \(exclude)")
    }
    if let sizeRange = rule.size_range, !sizeRange.isEmpty {
      parts.append("大小: \(sizeRange) MB")
    }
    if let seeders = rule.seeders, !seeders.isEmpty {
      parts.append("做种≥\(seeders)")
    }
    if let pubTime = rule.publish_time, !pubTime.isEmpty {
      parts.append("发布: \(pubTime)分钟")
    }
    return parts
  }
}
