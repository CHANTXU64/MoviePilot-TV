import Kingfisher
import SwiftUI
import UIKit

enum PageImageRole {
  case content
  case activePage
}

/// 卡片共用的可释放图片 surface。
///
/// `PageImageLifecycle` 会直接调用底层 UIImageView 清图，因此被 NavigationStack 隐藏的页面
/// 不需要先重新求值 SwiftUI body，也能同步释放解码图片和渲染层。
struct PageManagedImage: View {
  @Environment(\.pageImageLifecycle) private var pageImageLifecycle
  @Environment(\.gridImageDemandContext) private var gridImageDemandContext
  @State private var demandLease = PageImageDemandLease()

  let url: URL?
  let processor: any ImageProcessor
  let isEnabled: Bool
  var role: PageImageRole = .content
  let participatesInPageLifecycle: Bool
  let skipsMemoryCache: Bool
  var loadsDiskFileSynchronously = false
  var fadeDuration: TimeInterval = 0.25
  var onSuccess: (() -> Void)?
  var onFailure: (() -> Void)?

  var body: some View {
    PageManagedImageSurface(
      url: url,
      processor: processor,
      isEnabled: isEnabled,
      role: role,
      participatesInPageLifecycle: participatesInPageLifecycle,
      skipsMemoryCache: skipsMemoryCache,
      loadsDiskFileSynchronously: loadsDiskFileSynchronously,
      fadeDuration: fadeDuration,
      onSuccess: onSuccess,
      onFailure: onFailure,
      lifecycle: pageImageLifecycle,
      gridImageDemandContext: gridImageDemandContext,
      demandLease: demandLease
    )
  }
}

private struct PageManagedImageSurface: UIViewRepresentable {
  typealias UIViewType = UIView

  let url: URL?
  let processor: any ImageProcessor
  let isEnabled: Bool
  let role: PageImageRole
  let participatesInPageLifecycle: Bool
  let skipsMemoryCache: Bool
  let loadsDiskFileSynchronously: Bool
  let fadeDuration: TimeInterval
  let onSuccess: (() -> Void)?
  let onFailure: (() -> Void)?
  let lifecycle: PageImageLifecycle?
  let gridImageDemandContext: GridImageDemandContext?
  let demandLease: PageImageDemandLease

  func makeUIView(context _: UIViewRepresentableContext<PageManagedImageSurface>) -> UIView {
    let imageView = PageManagedImageView()
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    return imageView
  }

  func updateUIView(
    _ uiView: UIView,
    context _: UIViewRepresentableContext<PageManagedImageSurface>
  ) {
    guard let imageView = uiView as? PageManagedImageView else { return }
    imageView.configure(
      url: url,
      processor: processor,
      isEnabled: isEnabled,
      role: role,
      participatesInPageLifecycle: participatesInPageLifecycle,
      skipsMemoryCache: skipsMemoryCache,
      loadsDiskFileSynchronously: loadsDiskFileSynchronously,
      fadeDuration: fadeDuration,
      onSuccess: onSuccess,
      onFailure: onFailure,
      lifecycle: lifecycle,
      gridImageDemandContext: gridImageDemandContext,
      demandLease: demandLease
    )
  }

  static func dismantleUIView(_ uiView: UIView, coordinator _: Void) {
    (uiView as? PageManagedImageView)?.detach()
  }
}

/// 逻辑图片需求的稳定身份。它属于 SwiftUI 图片节点，而不属于可能被 Lazy 容器销毁的 UIView。
/// 因此页面被导航隐藏后仍能保留预热清单，数据项真正删除时又会随节点销毁而撤销需求。
@MainActor
final class PageImageDemandLease {
  let id = UUID()

  private weak var slot: PageImageSlot?

  func bind(to newSlot: PageImageSlot?, isEnabled: Bool) {
    if slot !== newSlot {
      slot?.removeDemand(id: id)
      slot = newSlot
    }
    newSlot?.setDemand(id: id, isEnabled: isEnabled)
  }

  func cancel() {
    slot?.removeDemand(id: id)
    slot = nil
  }

  isolated deinit {
    slot?.removeDemand(id: id)
  }
}

@MainActor
final class PageImageSlot: PageImageResource, GridImageDemandResource {
  let key: String

  private let url: URL
  private let processor: any ImageProcessor
  private let role: PageImageRole
  private let skipsMemoryCache: Bool
  private let loadsDiskFileSynchronously: Bool
  private let fadeDuration: TimeInterval
  private let performsImageRetrieval: Bool
  private weak var lifecycle: PageImageLifecycle?
  private weak var gridImageController: GridImageLifecycleController?
  private var gridImageListIdentity: GridListIdentity?
  private var gridImageItemIndex: Int?
  private var requiresGridImagePermission = false
  private var surfaces: [ObjectIdentifier: WeakPageManagedImageView] = [:]
  private var surfaceDemandIDs: [ObjectIdentifier: UUID] = [:]
  private var demands: [UUID: Bool] = [:]
  private var contentImagesAllowed = true
  private var activePageImagesAllowed = true
  private var decodedImage: UIImage?
  private var downloadTask: DownloadTask?
  private var isRetrieving = false
  private var generation: UInt = 0
  private var didFail = false
  private(set) var retrievalStartCount = 0

  init(
    key: String,
    url: URL,
    processor: any ImageProcessor,
    role: PageImageRole,
    skipsMemoryCache: Bool,
    loadsDiskFileSynchronously: Bool,
    fadeDuration: TimeInterval,
    performsImageRetrieval: Bool = true,
    lifecycle: PageImageLifecycle? = nil
  ) {
    self.key = key
    self.url = url
    self.processor = processor
    self.role = role
    self.skipsMemoryCache = skipsMemoryCache
    self.loadsDiskFileSynchronously = loadsDiskFileSynchronously
    self.fadeDuration = fadeDuration
    self.performsImageRetrieval = performsImageRetrieval
    self.lifecycle = lifecycle
  }

  var hasLoadedPageImage: Bool {
    decodedImage != nil
  }

  func attach(_ surface: PageManagedImageView, demandID: UUID) {
    let id = ObjectIdentifier(surface)
    surfaces[id] = WeakPageManagedImageView(surface)
    surfaceDemandIDs[id] = demandID
    if demands[demandID] == true, pageAllowsImage {
      if let decodedImage {
        surface.install(decodedImage, fadeDuration: 0)
      }
    } else {
      surface.clearRenderedImage()
    }
    updateLoading()
  }

  func setDemand(id: UUID, isEnabled: Bool) {
    let wasEnabled = demands[id] == true
    demands[id] = isEnabled
    if isEnabled {
      if !wasEnabled {
        if didFail {
          didFail = false
        }
        restoreDecodedImage(for: id)
      }
    } else {
      clearSurfaces(for: id)
    }
    updateLoading()
  }

  func removeDemand(id: UUID) {
    demands.removeValue(forKey: id)
    clearSurfaces(for: id)
    updateLoading()
    discardIfUnused()
  }

  func detach(_ surface: PageManagedImageView) {
    let id = ObjectIdentifier(surface)
    surfaces.removeValue(forKey: id)
    surfaceDemandIDs.removeValue(forKey: id)
    surface.clearRenderedImage()
    updateLoading()
    discardIfUnused()
  }

  func setPageImagePermissions(contentAllowed: Bool, activePageAllowed: Bool) {
    contentImagesAllowed = contentAllowed
    activePageImagesAllowed = activePageAllowed
    updateLoading()
  }

  func setGridImageDemandContext(_ context: GridImageDemandContext?) {
    if let context,
      gridImageController === context.controller,
      gridImageListIdentity == context.listIdentity,
      gridImageItemIndex == context.itemIndex
    {
      return
    }
    if context == nil, !requiresGridImagePermission {
      return
    }

    gridImageController?.unregister(self)
    gridImageController = context?.controller
    gridImageListIdentity = context?.listIdentity
    gridImageItemIndex = context?.itemIndex
    requiresGridImagePermission = context != nil

    if let context {
      if let itemIDs = context.itemIDs {
        context.controller.reconcileEventSnapshot(
          listIdentity: context.listIdentity,
          itemIDs: itemIDs
        )
      }
      context.controller.register(
        self,
        listIdentity: context.listIdentity,
        itemIndex: context.itemIndex
      )
    } else {
      updateLoading()
    }
  }

  func gridImageDemandPermissionDidChange() {
    updateLoading()
  }

  private var isRequested: Bool {
    demands.values.contains(true)
  }

  private var pageAllowsImage: Bool {
    let roleAllowed = switch role {
    case .content: contentImagesAllowed
    case .activePage: activePageImagesAllowed
    }
    guard roleAllowed else { return false }
    guard requiresGridImagePermission else { return true }
    guard let gridImageController, let gridImageListIdentity, let gridImageItemIndex else {
      return false
    }
    return gridImageController.allowsImages(
      listIdentity: gridImageListIdentity,
      itemIndex: gridImageItemIndex
    )
  }

  private func updateLoading() {
    removeDeadSurfaces()
    guard isRequested, pageAllowsImage else {
      releaseDecodedImage()
      return
    }
    guard decodedImage == nil, !isRetrieving, !didFail else { return }

    generation &+= 1
    let requestGeneration = generation
    isRetrieving = true
    retrievalStartCount += 1
    // 单元测试只验证 slot 状态机，不应因此发起外部图片请求。
    guard performsImageRetrieval else { return }
    let service = APIService.shared
    var options = service.imageOptions(for: url)
    options.append(.processor(processor))
    if skipsMemoryCache {
      options.append(TransientDecodedImage.skipMemoryCache)
    }
    if loadsDiskFileSynchronously {
      options.append(.loadDiskFileSynchronously)
    }

    downloadTask = KingfisherManager.shared.retrieveImage(
      with: service.imageSource(for: url),
      options: options
    ) { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self, requestGeneration == self.generation else { return }
        switch result {
        case .success(let value):
          self.acceptRetrievedImage(value.image)
        case .failure:
          self.downloadTask = nil
          self.isRetrieving = false
          self.didFail = true
          self.notifyFailureOnSurfaces()
        }
      }
    }
  }

  /// 接收一次有效解码结果。下载回调与状态机测试共用同一生产转换入口。
  func acceptRetrievedImage(_ image: UIImage) {
    downloadTask = nil
    isRetrieving = false
    didFail = false
    guard isRequested, pageAllowsImage else { return }
    decodedImage = image
    renderImageOnSurfaces(image)
  }

  private func renderImageOnSurfaces(_ image: UIImage) {
    for surface in liveDemandingSurfaces {
      surface.install(image, fadeDuration: fadeDuration)
      surface.notifySuccess(for: key)
    }
  }

  private func notifyFailureOnSurfaces() {
    for surface in liveDemandingSurfaces {
      surface.notifyFailure(for: key)
    }
  }

  private func releaseDecodedImage() {
    generation &+= 1
    downloadTask?.cancel()
    downloadTask = nil
    isRetrieving = false
    decodedImage = nil
    didFail = false
    for surface in liveSurfaces {
      surface.clearRenderedImage()
    }
  }

  private var liveSurfaces: [PageManagedImageView] {
    surfaces.values.compactMap(\.value)
  }

  private var liveDemandingSurfaces: [PageManagedImageView] {
    surfaces.compactMap { id, surface in
      guard let demandID = surfaceDemandIDs[id], demands[demandID] == true else { return nil }
      return surface.value
    }
  }

  private func clearSurfaces(for demandID: UUID) {
    for (surfaceID, surface) in surfaces where surfaceDemandIDs[surfaceID] == demandID {
      surface.value?.clearRenderedImage()
    }
  }

  private func restoreDecodedImage(for demandID: UUID) {
    guard pageAllowsImage, let decodedImage else { return }
    for (surfaceID, surface) in surfaces where surfaceDemandIDs[surfaceID] == demandID {
      surface.value?.install(decodedImage, fadeDuration: 0)
    }
  }

  private func removeDeadSurfaces() {
    let deadIDs = surfaces.compactMap { id, surface in
      surface.value == nil ? id : nil
    }
    for id in deadIDs {
      surfaces.removeValue(forKey: id)
      surfaceDemandIDs.removeValue(forKey: id)
    }
  }

  private func discardIfUnused() {
    guard surfaces.isEmpty, demands.isEmpty else { return }
    gridImageController?.unregister(self)
    gridImageController = nil
    lifecycle?.discardRetainedImageResource(for: key, matching: self)
  }
}

private final class WeakPageManagedImageView {
  weak var value: PageManagedImageView?

  init(_ value: PageManagedImageView) {
    self.value = value
  }
}

@MainActor
final class PageManagedImageView: UIImageView {
  private weak var lifecycle: PageImageLifecycle?
  private var slot: PageImageSlot?
  private weak var demandLease: PageImageDemandLease?
  private var successHandler: (() -> Void)?
  private var failureHandler: (() -> Void)?

  func configure(
    url: URL?,
    processor: any ImageProcessor,
    isEnabled: Bool,
    role: PageImageRole,
    participatesInPageLifecycle: Bool,
    skipsMemoryCache: Bool,
    loadsDiskFileSynchronously: Bool,
    fadeDuration: TimeInterval,
    onSuccess: (() -> Void)?,
    onFailure: (() -> Void)?,
    lifecycle: PageImageLifecycle?,
    gridImageDemandContext: GridImageDemandContext?,
    demandLease: PageImageDemandLease
  ) {
    successHandler = onSuccess
    failureHandler = onFailure
    let managedLifecycle = participatesInPageLifecycle ? lifecycle : nil
    let managedGridContext = participatesInPageLifecycle ? gridImageDemandContext : nil
    guard let url else {
      replaceSlot(
        with: nil,
        lifecycle: managedLifecycle,
        demandLease: demandLease,
        isEnabled: false
      )
      return
    }

    let service = APIService.shared
    let source = service.imageSource(for: url)
    let roleKey = role == .content ? "content" : "active"
    let gridKey = managedGridContext.map {
      "grid:\($0.listIdentity.id.uuidString):\($0.listIdentity.generation):\($0.itemID):\($0.itemIndex)"
    } ?? "grid:none"
    let key = "\(service.imageConfigurationIdentity)|\(source.cacheKey)|\(processor.identifier)|\(roleKey)|\(gridKey)|disk:\(loadsDiskFileSynchronously)|skip:\(skipsMemoryCache)|fade:\(fadeDuration)"

    if slot?.key == key, self.lifecycle === managedLifecycle, self.demandLease === demandLease {
      slot?.setGridImageDemandContext(managedGridContext)
      demandLease.bind(to: slot, isEnabled: isEnabled)
      return
    }

    let newSlot: PageImageSlot
    if let managedLifecycle {
      newSlot = managedLifecycle.retainedImageResource(for: key) {
        PageImageSlot(
          key: key,
          url: url,
          processor: processor,
          role: role,
          skipsMemoryCache: skipsMemoryCache,
          loadsDiskFileSynchronously: loadsDiskFileSynchronously,
          fadeDuration: fadeDuration,
          lifecycle: managedLifecycle
        )
      }
    } else {
      newSlot = PageImageSlot(
        key: key,
        url: url,
        processor: processor,
        role: role,
        skipsMemoryCache: skipsMemoryCache,
        loadsDiskFileSynchronously: loadsDiskFileSynchronously,
        fadeDuration: fadeDuration
      )
    }
    newSlot.setGridImageDemandContext(managedGridContext)
    replaceSlot(
      with: newSlot,
      lifecycle: managedLifecycle,
      demandLease: demandLease,
      isEnabled: isEnabled
    )
  }

  func detach() {
    slot?.detach(self)
    slot = nil
    lifecycle = nil
    demandLease = nil
    successHandler = nil
    failureHandler = nil
    clearRenderedImage()
  }

  fileprivate func install(_ image: UIImage, fadeDuration: TimeInterval) {
    layer.removeAllAnimations()
    guard fadeDuration > 0, self.image == nil else {
      self.image = image
      return
    }
    UIView.transition(
      with: self,
      duration: fadeDuration,
      options: .transitionCrossDissolve,
      animations: { self.image = image }
    )
  }

  fileprivate func clearRenderedImage() {
    layer.removeAllAnimations()
    image = nil
    layer.contents = nil
  }

  fileprivate func notifySuccess(for key: String) {
    guard slot?.key == key else { return }
    successHandler?()
  }

  fileprivate func notifyFailure(for key: String) {
    guard slot?.key == key else { return }
    failureHandler?()
  }

  private func replaceSlot(
    with newSlot: PageImageSlot?,
    lifecycle newLifecycle: PageImageLifecycle?,
    demandLease newDemandLease: PageImageDemandLease,
    isEnabled: Bool
  ) {
    if demandLease !== newDemandLease {
      demandLease?.cancel()
    }
    slot?.detach(self)
    lifecycle = newLifecycle
    slot = newSlot
    demandLease = newDemandLease
    newDemandLease.bind(to: newSlot, isEnabled: isEnabled)
    newSlot?.attach(self, demandID: newDemandLease.id)
    if newSlot == nil {
      clearRenderedImage()
    }
  }
}
