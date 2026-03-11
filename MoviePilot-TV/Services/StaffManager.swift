import Foundation

struct StaffManager {
  // 职位优先级列表（数字越小优先级越高）
  private static func getPriority(for job: String) -> Int {
    if let priority = jobPriorityMap[job] {
      return priority
    }
    return 999  // 未在列表中的职位，给予最低优先级
  }

  /// 通用辅助方法：将两个由 "/" 分隔的字符串合并去重，防止叠字重复和穿透
  private static func mergeUniqueStrings(existing: String, new: String) -> String {
    var items = existing.components(separatedBy: "/")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    var itemSet = Set(items)

    let newItems = new.components(separatedBy: "/")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    for item in newItems {
      if !itemSet.contains(item) {
        items.append(item)
        itemSet.insert(item)  // 动态更新缓存，完美阻断重复项
      }
    }

    return items.joined(separator: "/")
  }

  // 兼容现有的全量处理逻辑（非 Loadmore 场景）
  static func processCrew(persons: [Person]) -> [Person] {
    return mergeCrew(existing: [], newBatch: persons)
  }

  // 专供 Loadmore 场景的增量合并 API
  // 保证 `existing` 列表中的人员排序位置绝对不变，仅对 `newBatch` 中的新增人员进行合并与尾部排序拼接
  static func mergeCrew(existing: [Person], newBatch: [Person]) -> [Person] {
    var result = existing
    var idToIndex: [String: Int] = [:]

    // 1. 记录已有人员的位置，用于后续合并职位但不移动他们
    for (index, person) in result.enumerated() {
      idToIndex[person.id] = index
    }

    var newlyAdded: [Person] = []
    var newIdToIndex: [String: Int] = [:]
    var idToBestPriority: [String: Int] = [:]

    // 2. 遍历新批次数据
    for person in newBatch {
      let currentJobs = person.job?.components(separatedBy: "/") ?? []
      let currentMinPriority =
        currentJobs.map { getPriority(for: $0.trimmingCharacters(in: .whitespaces)) }.min() ?? 999

      if let index = idToIndex[person.id] {
        // [场景 A] 该人员在【旧数据】中已存在：仅合并他的新职位(job keys)，绝对不改变他在旧列表中的 UI 排序
        if let newJob = person.job, !newJob.isEmpty {
          var existingPerson = result[index]
          let oldJob = existingPerson.job ?? ""

          existingPerson.job = mergeUniqueStrings(existing: oldJob, new: newJob)
          result[index] = existingPerson
        }
      } else if let newIndex = newIdToIndex[person.id] {
        // [场景 B] 该人员在【这一批新数据】中重复出现了：在 newBatch 内部进行合并
        if let newJob = person.job, !newJob.isEmpty {
          var existingNewPerson = newlyAdded[newIndex]
          let oldJob = existingNewPerson.job ?? ""

          existingNewPerson.job = mergeUniqueStrings(existing: oldJob, new: newJob)
          newlyAdded[newIndex] = existingNewPerson
        }
        // 更新这一批次中此人的最高优先级缓存
        if let existingPriority = idToBestPriority[person.id] {
          idToBestPriority[person.id] = min(existingPriority, currentMinPriority)
        } else {
          idToBestPriority[person.id] = currentMinPriority
        }
      } else {
        // [场景 C] 这是一个【全新】的人员
        newIdToIndex[person.id] = newlyAdded.count
        var translatedPerson = person
        if let job = person.job {
          // 对全新人员也进行同源自身去重（防止单次传入的 newJob 在翻译后产生重复）
          // 此时的 job 仍是英文 key
          translatedPerson.job = mergeUniqueStrings(existing: "", new: job)
        }
        newlyAdded.append(translatedPerson)
        idToBestPriority[person.id] = currentMinPriority
      }
    }

    // 3. 仅对新增的人员进行优先级排序，以防 Director 出现在新页面的末尾
    let sortedNewlyAdded = newlyAdded.sorted { p1, p2 in
      let p1Priority = idToBestPriority[p1.id] ?? 999
      let p2Priority = idToBestPriority[p2.id] ?? 999
      if p1Priority != p2Priority {
        return p1Priority < p2Priority
      }
      // 同职位中，没有头像的排后面
      let h1 = hasAvatar(p1)
      let h2 = hasAvatar(p2)
      if h1 != h2 {
        return h1 && !h2
      }
      return false
    }

    // 4. 将排序好的新人员拼接到旧列表末尾，完美解决 UI 跳动
    result.append(contentsOf: sortedNewlyAdded)

    // 5. 在最终返回前，统一将所有人的 job keys 翻译成当前语言的职位名称
    return result.map { person in
      var translatedPerson = person
      if let jobKeys = person.job {
        // job 字段此时存储的是英文 key, e.g., "Director/Writer"
        // 我们需要把它翻译成当前选择的语言
        translatedPerson.job = TranslationHelper.translateJobs(jobString: jobKeys)
      }
      return translatedPerson
    }
  }

  // 兼容现有的全量处理逻辑（非 Loadmore 场景）
  static func processActors(persons: [Person]) -> [Person] {
    return mergeActors(existing: [], newBatch: persons)
  }

  // 专供 Loadmore 场景的增量合并 API（演员）
  static func mergeActors(existing: [Person], newBatch: [Person]) -> [Person] {
    var result = existing
    var idToIndex: [String: Int] = [:]

    for (index, person) in result.enumerated() {
      idToIndex[person.id] = index
    }

    var newlyAdded: [Person] = []
    var newIdToIndex: [String: Int] = [:]

    for person in newBatch {
      if let index = idToIndex[person.id] {
        // 存在于旧列表中，合并角色
        if let newChar = person.character, !newChar.isEmpty {
          var existingPerson = result[index]
          let oldChar = existingPerson.character ?? ""

          existingPerson.character = mergeUniqueStrings(existing: oldChar, new: newChar)
          result[index] = existingPerson
        }
      } else if let newIndex = newIdToIndex[person.id] {
        // 在新列表中重复，合并角色
        if let newChar = person.character, !newChar.isEmpty {
          var existingNewPerson = newlyAdded[newIndex]
          let oldChar = existingNewPerson.character ?? ""

          existingNewPerson.character = mergeUniqueStrings(existing: oldChar, new: newChar)
          newlyAdded[newIndex] = existingNewPerson
        }
      } else {
        // 全新演员
        newIdToIndex[person.id] = newlyAdded.count
        var newPerson = person
        if let char = person.character {
          // 对新角色的字符串也进行去重，防备服务端返回的本身就是 "John / John"
          newPerson.character = mergeUniqueStrings(existing: "", new: char)
        }
        newlyAdded.append(newPerson)
      }
    }

    // 演员本身保持服务器返回的新增顺序，直接拼接在末尾
    result.append(contentsOf: newlyAdded)
    return result
  }

  static func getTopGroupedStaff(from persons: [Person], count: Int) -> [GroupedStaff] {
    var staffGroupedByJob: [String: [String]] = [:]
    var seenNamesPerJob: [String: Set<String>] = [:]  // 用于去重的辅助工具

    // 1. 按英文职位 key 对员工进行分组，并保留顺序
    for staff in persons {
      guard let jobKeys = staff.job, !jobKeys.isEmpty, let name = staff.name, !name.isEmpty else {
        continue
      }

      let individualJobKeys = jobKeys.components(separatedBy: "/")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      for key in individualJobKeys {
        if !(seenNamesPerJob[key, default: []].contains(name)) {
          staffGroupedByJob[key, default: []].append(name)
          seenNamesPerJob[key, default: []].insert(name)
        }
      }
    }

    // 2. 备选方案：如果没有任何带职位的员工（例如数据源仅提供演员或缺失职位），尝试使用角色信息分组
    if staffGroupedByJob.isEmpty {
      for staff in persons {
        guard let name = staff.name, !name.isEmpty else { continue }

        // 优先级：角色名 > 原始职位 > 角色列表 > 兜底 “职员”
        let jobLabel: String
        if let character = staff.character, !character.isEmpty {
          jobLabel = character
        } else if let job = staff.job, !job.isEmpty {
          jobLabel = job
        } else if let rolesStr = staff.roles?.joined(separator: "/"), !rolesStr.isEmpty {
          jobLabel = rolesStr
        } else {
          jobLabel = "职员"
        }

        // 统一进行姓名查重优化，防止同一分类下出现重复姓名，保持逻辑一致
        if !(seenNamesPerJob[jobLabel, default: []].contains(name)) {
          staffGroupedByJob[jobLabel, default: []].append(name)
          seenNamesPerJob[jobLabel, default: []].insert(name)
        }
      }
    }

    // 2. 对职位 key 执行稳定排序
    let sortedJobKeys = staffGroupedByJob.keys.sorted {
      let p1 = getPriority(for: $0)
      let p2 = getPriority(for: $1)
      if p1 != p2 {
        return p1 < p2
      }
      return $0 < $1  // 使用 key 本身进行稳定排序
    }

    // 3. 取前 'count' 个职位
    let topJobKeys = sortedJobKeys.prefix(count)

    // 4. 映射到 GroupedStaff，并翻译职位 key 用于显示
    return topJobKeys.map { key in
      let names = staffGroupedByJob[key] ?? []
      // 将英文 key 翻译成显示语言
      let translatedJob = TranslationHelper.translateJobs(jobString: key)
      return GroupedStaff(id: key, job: translatedJob, names: names)
    }
  }

  /// 判断人员是否有头像
  private static func hasAvatar(_ person: Person) -> Bool {
    if let profilePath = person.profile_path, !profilePath.isEmpty {
      return true
    }
    if person.avatar != nil {
      return true
    }
    if person.images != nil {
      return true
    }
    return false
  }
}
