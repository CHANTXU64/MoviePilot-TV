import XCTest

@testable import MoviePilot_TV

@MainActor
final class ExploreViewModelTypeSwitchTests: XCTestCase {
  private func makeViewModel() -> ExploreViewModel {
    ExploreViewModel(apiService: APIService.shared)
  }

  func testTmdbExclusiveSortFallsBackAfterTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .themoviedb
    viewModel.selectedType = .movies
    viewModel.tmdbSortBy = "release_date.desc"

    viewModel.selectedType = .tvs
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.tmdbSortBy, "popularity.desc")

    viewModel.tmdbSortBy = "first_air_date.asc"
    viewModel.selectedType = .movies
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.tmdbSortBy, "popularity.desc")
  }

  func testTmdbSharedSortSurvivesTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .themoviedb
    viewModel.selectedType = .movies
    viewModel.tmdbSortBy = "vote_average.desc"

    viewModel.selectedType = .tvs
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.tmdbSortBy, "vote_average.desc")
  }

  func testTmdbSharedGenreSurvivesTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .themoviedb
    viewModel.selectedType = .movies
    viewModel.tmdbGenre = "16"

    viewModel.selectedType = .tvs
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.tmdbGenre, "16")
  }

  func testTmdbExclusiveGenreClearedAfterTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .themoviedb
    viewModel.selectedType = .tvs
    viewModel.tmdbGenre = "10767"

    viewModel.selectedType = .movies
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.tmdbGenre, "")
  }

  func testPopularGenreNormalizedAfterTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .popular
    viewModel.selectedType = .tvs
    viewModel.popularGenre = "10767"

    viewModel.selectedType = .movies
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.popularGenre, "")

    viewModel.selectedType = .tvs
    viewModel.popularGenre = "16"
    viewModel.selectedType = .movies
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.popularGenre, "16")
  }

  func testDoubanCategorySurvivesTypeSwitch() {
    let viewModel = makeViewModel()
    viewModel.selectedSource = .douban
    viewModel.selectedType = .movies
    viewModel.doubanCategory = "喜剧"

    viewModel.selectedType = .tvs
    viewModel.onTypeChanged()

    XCTAssertEqual(viewModel.doubanCategory, "喜剧")
  }
}
