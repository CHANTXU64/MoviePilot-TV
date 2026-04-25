import SwiftUI

struct SystemView: View {

  @StateObject private var viewModel = SystemViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section(header: Text("状态")) {
          LabeledContent("登录状态") {
            Text(viewModel.storageDescription)
              .foregroundStyle(statusColor)
              .animation(.default, value: viewModel.storageMechanism)
          }
        }

        Section(header: Text("搜索过滤"), footer: Text("选择一个自定义过滤规则后，资源搜索结果将自动按此规则过滤")) {
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
            // 使用 Binding 包装 selectedCustomFilterRuleId
            let ruleBinding = Binding<String>(
              get: { viewModel.selectedCustomFilterRuleId ?? "__none__" },
              set: { newValue in
                viewModel.selectedCustomFilterRuleId = (newValue == "__none__") ? nil : newValue
              }
            )

            Picker("过滤规则", selection: ruleBinding) {
              Text("不过滤")
                .tag("__none__")

              ForEach(viewModel.customFilterRules) { rule in
                ruleLabel(rule)
                  .tag(rule.id)
              }
            }
            .pickerStyle(.menu)
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
        // 加载自定义过滤规则
        await viewModel.loadCustomFilterRules()
      }
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
