import UIKit
import Shared
import XCTest
import PlaygroundSupport

/* Content list:
    1, 2, 3 - State, Event and reduce - representation of logic separated from Service
    4 - Presenter - interpretes state for concrete effect producer interface (controller)
    5 - Controller - effects producer
    6 - Logic tests (XCTest) imeplementation
    7 - Presenter tests (XCTest) imeplementation
    8 - Controller tests (XCTest) imeplementation
    9 - Uncomment this block to execute data download/cache
    10 - Uncomment this block to run tests for logic
    11 - Uncomment this block to run Presenter tests
    12 - Uncomment this block to run Controller tests
    --- alternative ---
    13 - EffectsPrtoducer - interpretes state in terms of effects (direct, without presenter)
    14 - EffectsPrtoducer tests (XCTest) imeplementation
    15 - Uncomment this block to execute data download/cache
    16 - Uncomment this block to run EffectsPrtoducer tests
*/

// 1 -------------------------------------------------------------------------------------

enum State: Equatable {
    case idle
    case checkingForAvaliability(URL)
    case downloading(URL)
    case saving(URL, Data)
    case finished(URL, Data)
    case downloadFailed
    case saveFailed
}

// 2 -------------------------------------------------------------------------------------

enum Event: Equatable {
    case check(URL)
    case checkSucceed(Data)
    case checkFailed
    case download(URL)
    case downloadSucceed(Data)
    case downloadFailed
    case save(URL, Data)
    case saveSucceed(Data)
    case saveFailed
}

// 3 -------------------------------------------------------------------------------------

func reduce(_ state: State, with event: Event) -> State {
    switch (state, event) {
    case (.idle, .download(let url)):
        return .checkingForAvaliability(url)
        
    case let (.checkingForAvaliability(url), .checkSucceed(data)):
        return .finished(url, data)
        
    case (.checkingForAvaliability(let url), .checkFailed):
        return .downloading(url)
        
    case let (.downloading(url), .downloadSucceed(data)):
        return .saving(url, data)
        
    case (.downloading, .downloadFailed):
        return .downloadFailed
        
    case let (.saving(url, data), .saveSucceed):
        return .finished(url, data)
        
    case (.saving, .saveFailed):
        return .saveFailed
        
    default:
        return state
        
    }
}

// 4 -------------------------------------------------------------------------------------

struct Presenter {
    let render: (Controller.Props) -> ()
    let dispatch: (Event) -> ()
    
    func handle(state: State) {
        switch state {
        case .checkingForAvaliability(let url):
            render(
                .checkForAvaliability(
                    url: url,
                    success: { data in self.dispatch(.checkSucceed(data)) },
                    failure: { self.dispatch(.checkFailed) }
                )
            )
            
        case .downloading(let url):
            render(
                .download(
                    url: url,
                    success: { data in self.dispatch(.downloadSucceed(data)) },
                    failure: { self.dispatch(.downloadFailed) }
                )
            )
            
        case .saving(let url, let data):
            render(
                .save(
                    url: url,
                    data: data,
                    success: { data in self.dispatch(.saveSucceed(data)) },
                    failure: { self.dispatch(.saveFailed) }
                )
            )
        
        default:
            render(.idle)
        }
    }
}

// 5 -------------------------------------------------------------------------------------

final class Controller {
    enum Props {
        case idle
        case checkForAvaliability(url: URL, success: (Data) -> (), failure: () -> ())
        case download(url: URL, success: (Data) -> (), failure: () -> ())
        case save(url: URL, data: Data, success: (Data) -> (), failure: () -> ())
    }
    
    private let storage: Storage
    private let downloader: Downloader
    
    init(storage: Storage, downloader: Downloader) {
        self.storage = storage
        self.downloader = downloader
    }
    
    func render(props: Props) {
        switch props {
        case .idle:
            break
            
        case .checkForAvaliability(let url, let success, let failure):
            switch storage.fetch(from: url) {
            case .success(let data):
                success(data)
            case .failure:
                failure()
            }
            
        case .download(let url, let success, let failure):
            downloader.download(from: url) { result in
                switch result {
                case .success(let data):
                    success(data)
                case .failure:
                    failure()
                }
            }
            
        case .save(let url, let data, let success, let failure):
            switch storage.store(data: data, to: url) {
            case .success:
                success(data)
            case .failure:
                failure()
            }
        }
    }
}

extension Controller.Props: Equatable {
    static func == (lhs: Controller.Props, rhs: Controller.Props) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case let (.checkForAvaliability(left, _, _), .checkForAvaliability(right, _, _)):
            return left == right
        case let (.download(left, _, _), .download(right, _, _)):
            return left == right
        case let (.save(lURL, lData, _, _), .save(rURL, rData, _, _)):
            return lURL == rURL && lData == rData
        default:
            return false
        }
    }
}

struct ControllerFactory {
    static func new(
        storage: Storage = StorageFactory.new(),
        downloader: Downloader = DownloaderFactory.new()
    ) -> Controller {
        return Controller(storage: storage, downloader: downloader)
    }
}

// 6 -------------------------------------------------------------------------------------

final class StateSpec: XCTestCase {
    var url: URL!
    var data: Data!
    
    override func setUp() {
        super.setUp()
        
        url = URL(string: "https://betterme.world")!
        data = Data()
    }
    
    func testShouldCheckForAvaliabilityBeforeDownload() {
        XCTAssertEqual(
            reduce(.idle, with: .download(url)),
            .checkingForAvaliability(url)
        )
    }
    
    func testShouldReturnAvaliabileData() {
        XCTAssertEqual(
            reduce(.checkingForAvaliability(url), with: .checkSucceed(data)),
            .finished(url, data)
        )
    }
    
    func testShouldDownloadIfNotAvaliabile() {
        XCTAssertEqual(
            reduce(.checkingForAvaliability(url), with: .checkFailed),
            .downloading(url)
        )
    }
    
    func testShouldFailIfCannotDownload() {
        XCTAssertEqual(
            reduce(.downloading(url), with: .downloadFailed),
            .downloadFailed
        )
    }
    
    func testShouldSaveIfDownloadSucceed() {
        XCTAssertEqual(
            reduce(.downloading(url), with: .downloadSucceed(data)),
            .saving(url, data)
        )
    }
    
    func testShouldFailIfCannotSave() {
        XCTAssertEqual(
            reduce(.saving(url, data), with: .saveFailed),
            .saveFailed
        )
    }
    
    func testShouldReturnSavedData() {
        XCTAssertEqual(
            reduce(.saving(url, data), with: .saveSucceed(data)),
            .finished(url, data)
        )
    }
}

// 7 -------------------------------------------------------------------------------------

final class PresenterSpec: XCTestCase {
    var sut: Presenter!
    var dispatched: Event!
    var rendered: Controller.Props!
    var url: URL!
    var data: Data!

    override func setUp() {
        super.setUp()

        url = URL(string: "https://betterme.world")!
        data = Data()
        sut = Presenter(
            render: { self.rendered = $0 },
            dispatch: { self.dispatched = $0 }
        )
    }

    func test_shouldRenderCorrectProps_forCheckingForAvaliabilityState() {
        sut.handle(state: .checkingForAvaliability(url))

        XCTAssertEqual(rendered, .checkForAvaliability(url: url, success: { _ in () }, failure: {}))

        if case .checkForAvaliability(_, let success, let failure)? = rendered {
            success(data)
            XCTAssertEqual(dispatched, .checkSucceed(data))

            failure()
            XCTAssertEqual(dispatched, .checkFailed)
        } else {
            XCTFail()
        }
    }

    func test_shouldRenderCorrectProps_forDownloadingState() {
        sut.handle(state: .downloading(url))

        XCTAssertEqual(rendered, .download(url: url, success: { _ in () }, failure: {}))

        if case .download(_, let success, let failure)? = rendered {
            success(data)
            XCTAssertEqual(dispatched, .downloadSucceed(data))

            failure()
            XCTAssertEqual(dispatched, .downloadFailed)
        } else {
            XCTFail()
        }
    }

    func test_shouldRenderCorrectProps_forSavingState() {
        sut.handle(state: .saving(url, data))

        XCTAssertEqual(rendered, .save(url: url, data: data, success: { _ in () }, failure: {}))

        if case .save(_, _, let success, let failure)? = rendered {
            success(data)
            XCTAssertEqual(dispatched, .saveSucceed(data))

            failure()
            XCTAssertEqual(dispatched, .saveFailed)
        } else {
            XCTFail()
        }
    }
}

// 8 -------------------------------------------------------------------------------------

final class ControllerSpec: XCTestCase {
    var sut: Controller!
    var storage: MockStorage!
    var downloader: MockDownloader!
    var url: URL!
    var data: Data!
    
    override func setUp() {
        super.setUp()
        
        storage = MockStorage()
        downloader = MockDownloader()
        sut = ControllerFactory.new(storage: storage, downloader: downloader)
        url = URL(string: "https://betterme.world")!
        data = Data()
    }
    
    func test_shouldReadData_forCheckForAvaliabilityProps_andReturnData_ifSucceed() {
        //given
        var receivedData: Data!
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.success(data))
        
        //when
        sut.render(props: .checkForAvaliability(url: url, success: { receivedData = $0 }, failure: {}))
        
        //then
        XCTAssertEqual(receivedData, data)
    }
    
    func test_shouldReadData_forCheckForAvaliabilityProps_andCallFailure_ifFailed() {
        //given
        var failureCalled = false
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        
        //when
        sut.render(props: .checkForAvaliability(url: url, success: { _ in () }, failure: { failureCalled = true }))
        
        //then
        XCTAssertTrue(failureCalled)
    }
    
    func test_shouldDownloadData_forDownloadProps_andReturnData_ifSucceed() {
        //given
        var receivedData: Data!
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.success(self.data))
            }
        
        //when
        sut.render(props: .download(url: url, success: { receivedData = $0 }, failure: {}))
        
        //then
        XCTAssertEqual(receivedData, data)
    }
    
    func test_shouldDownloadData_forDownloadProps_andCallFailure_ifFailed() {
        //given
        var failureCalled = false
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.failure(NSError.dummy))
            }
        
        //when
        sut.render(props: .download(url: url, success: { _ in () }, failure: { failureCalled = true }))
        
        //then
        XCTAssertTrue(failureCalled)
    }
    
    func test_shouldSaveData_forSaveProps_andReturnData_ifSucceed() {
        //given
        var successCalled = false
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.success(()))
        
        //when
        sut.render(props: .save(url: url, data: data, success: { _ in successCalled = true }, failure: {}))
        
        //then
        XCTAssertTrue(successCalled)
    }
    
    func test_shouldSaveData_forSaveProps_andCallFailure_ifFailed() {
        //given
        var failureCalled = false
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.failure(NSError.dummy))
        
        //when
        sut.render(props: .save(url: url, data: data, success: { _ in () }, failure: { failureCalled = true }))
        
        //then
        XCTAssertTrue(failureCalled)
    }
}

// 9 -------------------------------------------------------------------------------------

//let url = URL(string: "https://images.pexels.com/photos/67636/rose-blue-flower-rose-blooms-67636.jpeg")!
//let controller = ControllerFactory.new()
//var state = State.idle
//
//func dispatch(event: Event) {
//    let newState = reduce(state, with: event)
//    print("""
//        old state: \(state)
//        event: \(event)
//        new state: \(newState)
//        -
//        """)
//    state = newState
//    presenter.handle(state: newState)
//}
//
//let presenter = Presenter(render: controller.render, dispatch: dispatch)
//dispatch(event: .download(url))

// 10 -------------------------------------------------------------------------------------

//StateSpec.defaultTestSuite.run()

// 11 -------------------------------------------------------------------------------------

//PresenterSpec.defaultTestSuite.run()

// 12 -------------------------------------------------------------------------------------

//ControllerSpec.defaultTestSuite.run()

// 13 -------------------------------------------------------------------------------------

class EffectsProducer {
    private let storage: Storage
    private let downloader: Downloader
    
    init(storage: Storage, downloader: Downloader) {
        self.storage = storage
        self.downloader = downloader
    }

    func handle(state: State, produce: @escaping (Event?) -> ()) {
        switch state {
        case .checkingForAvaliability(let url):
            switch storage.fetch(from: url) {
            case .success(let data):
                produce(.checkSucceed(data))
            case .failure:
                produce(.checkFailed)
            }
        case .downloading(let url):
            downloader.download(from: url) { result in
                switch result {
                case .success(let data):
                    produce(.downloadSucceed(data))
                case .failure:
                    produce(.downloadFailed)
                }
            }
        case .saving(let url, let data):
            switch storage.store(data: data, to: url) {
            case .success:
                produce(.saveSucceed(data))
            case .failure:
                produce(.saveFailed)
            }
        default:
            break
        }
    }
}

struct EffectsProducerFactory {
    static func new(
        storage: Storage = StorageFactory.new(),
        downloader: Downloader = DownloaderFactory.new()
    ) -> EffectsProducer {
        return EffectsProducer(storage: storage, downloader: downloader)
    }
}

// 14 -------------------------------------------------------------------------------------

final class EffectsProducerSpec: XCTestCase {
    var sut: EffectsProducer!
    var storage: MockStorage!
    var downloader: MockDownloader!
    var url: URL!
    var data: Data!
    var expected: Event?
    
    override func setUp() {
        super.setUp()
        
        expected = nil
        storage = MockStorage()
        downloader = MockDownloader()
        sut = EffectsProducerFactory.new(storage: storage, downloader: downloader)
        url = URL(string: "https://betterme.world")!
        data = Data()
    }
    
    func test_shouldReadData_forCheckForAvaliabilityProps_andReturnData_ifSucceed() {
        //given
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.success(data))
        
        //when
        sut.handle(state: .checkingForAvaliability(url), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .checkSucceed(data))
    }
    
    func test_shouldReadData_forCheckForAvaliabilityProps_andCallFailure_ifFailed() {
        //given
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        
        //when
        sut.handle(state: .checkingForAvaliability(url), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .checkFailed)
    }
    
    func test_shouldDownloadData_forDownloadProps_andReturnData_ifSucceed() {
        //given
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.success(self.data))
        }
        
        //when
        sut.handle(state: .downloading(url), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .downloadSucceed(data))
    }
    
    func test_shouldDownloadData_forDownloadProps_andCallFailure_ifFailed() {
        //given
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.failure(NSError.dummy))
        }
        
        //when
        sut.handle(state: .downloading(url), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .downloadFailed)
    }
    
    func test_shouldSaveData_forSaveProps_andReturnData_ifSucceed() {
        //given
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.success(()))
        
        //when
        sut.handle(state: .saving(url, data), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .saveSucceed(data))
    }
    
    func test_shouldSaveData_forSaveProps_andCallFailure_ifFailed() {
        //given
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.failure(NSError.dummy))
        
        //when
        sut.handle(state: .saving(url, data), produce: { self.expected = $0 })
        
        //then
        XCTAssertEqual(expected, .saveFailed)
    }
}

// 15 -------------------------------------------------------------------------------------

//let url = URL(string: "https://images.pexels.com/photos/67636/rose-blue-flower-rose-blooms-67636.jpeg")!
//let producer = EffectsProducerFactory.new()
//var state = State.idle
//
//func dispatch(event: Event) {
//    let newState = reduce(state, with: event)
//    print("""
//        old state: \(state)
//        event: \(event)
//        new state: \(newState)
//        -
//        """)
//    state = newState
//    producer.handle(state: state) { $0.map(dispatch) }
//}
//dispatch(event: .download(url))

// 16 -------------------------------------------------------------------------------------

// EffectsProducerSpec.defaultTestSuite.run()
