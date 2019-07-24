import UIKit
import Shared
import PlaygroundSupport

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
        
    case let (.checkingForAvaliability(url), .checkFailed):
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

class Controller {
    enum Props {
        case idle
        case checkForAvaliability(url: URL, success: (Data) -> (), failure: () -> ())
        case download(url: URL, success: (Data) -> (), failure: () -> ())
        case save(url: URL, data: Data, success: (Data) -> (), failure: () -> ())
    }
    
    private let makeRequest: (URL) -> Request
    private let read: (URL) throws -> Data
    private let write: (URL, Data) throws -> Data
    
    init(
        makeRequest: @escaping (URL) -> Request,
        read: @escaping (URL) throws -> Data,
        write: @escaping (URL, Data) throws -> Data
    ) {
        self.makeRequest = makeRequest
        self.read = read
        self.write = write
    }
    
    func render(props: Props) {
        switch props {
        case .idle:
            break
            
        case .checkForAvaliability(let url, let success, let failure):
            if let data = try? read(url) {
                success(data)
            } else {
                failure()
            }
            
        case .download(let url, let success, let failure):
            makeRequest(url).perform { data in
                if let data = try? data.get() {
                    success(data)
                } else {
                    failure()
                }
            }
            
        case .save(let url, let data, let success, let failure):
            do {
                success(try write(url, data))
            } catch {
                failure()
                print(error)
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
    static func new() -> Controller {
        return Controller(
            makeRequest: Request.download,
            read: { path in
                guard let path = constructLocalPath(from: path) else { throw CannotConstructLocalPath(triedWith: url) }
                return try Data(contentsOf: path)
            },
            write: { path, data in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
                guard let path = constructLocalPath(from: path) else { throw CannotConstructLocalPath(triedWith: url) }
                try data.write(to: path)
                return data
            }
        )
    }
}

// 6 -------------------------------------------------------------------------------------

import XCTest

class DownloaderSpec: XCTestCase {
    var url: URL!
    var data: Data!
    
    override func setUp() {
        super.setUp()
        
        url = URL(string: "www.google.com")!
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

DownloaderSpec.defaultTestSuite.run()

// 7 -------------------------------------------------------------------------------------

let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("downloads")
func constructLocalPath(from url: URL) -> URL? {
    return url.pathComponents.last.map(root.appendingPathComponent)
}
struct CannotConstructLocalPath: Error {
    let triedWith: URL
}

let url = URL(string: "https://images.pexels.com/photos/67636/rose-blue-flower-rose-blooms-67636.jpeg")!

let controller = ControllerFactory.new()

var state = State.idle

func dispatch(event: Event) {
    let newState = reduce(state, with: event)
    print("""
        old state: \(state)
        event: \(event)
        new state: \(newState)
        -
        """)
    state = newState
    adapter.handle(state: newState)
}

let adapter = Presenter(render: controller.render, dispatch: dispatch)

dispatch(event: .download(url))
