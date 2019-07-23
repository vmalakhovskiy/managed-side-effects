import UIKit
import Quick
import Nimble
import SwiftyMock
import Shared

/* Content list:
    1 - Storage (used for storing/fetching data - wrapper over file system calls)
    2 - Downloader (used for downloading data - wrapper for url session)
    3 - Service (composes storage & downloader functions, provides interface for further integration)
    4 - Storage & Downloader mocks for tests
    5 - Service BDD spec imeplementation
    6 - Service plain XCTest spec imeplementation
    7 - Uncomment this block to execute Service `provide` function. This is main input for our service
    8 - Uncomment this block to run BDD tests
    9 - Uncomment this block to run plain tests
*/

// 1 -------------------------------------------------------------------------------------

protocol Storage {
    func fetch(from url: URL) -> Result<Data, Error>
    func store(data: Data, to url: URL) -> Result<Void, Error>
}

final private class StorageImpl: Storage {
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("downloads")
    
    struct CannotConstructLocalPath: Error {
        let triedWith: URL
    }

    private func constructLocalPath(from url: URL) -> URL? {
        return url.pathComponents.last.map(root.appendingPathComponent)
    }
    
    func fetch(from url: URL) -> Result<Data, Error> {
        guard let path = constructLocalPath(from: url) else { return .failure(CannotConstructLocalPath(triedWith: url)) }
        return Result { try Data(contentsOf: path) }
    }
    
    func store(data: Data, to url: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
            guard let path = constructLocalPath(from: url) else { return .failure(CannotConstructLocalPath(triedWith: url)) }
            try data.write(to: path)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

struct StorageFactory {
    static func new() -> Storage {
        return StorageImpl()
    }
}

// 2 -------------------------------------------------------------------------------------

protocol Downloader {
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ())
}

final class DownloaderImpl: Downloader {
    let session = URLSession(configuration: .default)
    
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ()) {
        let task = session.dataTask(with: url) { (data, _, error) in
            switch (data, error) {
            case (.none, let error?):
                completion(.failure(error))
                
            case (let data?, .none):
                completion(.success(data))
                
            default:
                struct UndefinedResponse: Error {}
                completion(.failure(UndefinedResponse()))
            }
        }
        task.resume()
    }
}

struct DownloaderFactory {
    static func new() -> Downloader {
        return DownloaderImpl()
    }
}

// 3 -------------------------------------------------------------------------------------

protocol Service {
    func provide(for url: URL, completion: @escaping (Result<Data, Error>) -> ())
}

final class ServiceImpl: Service {
    private let storage: Storage
    private let downloader: Downloader

    init(storage: Storage, downloader: Downloader) {
        self.storage = storage
        self.downloader = downloader
    }

    func provide(for url: URL, completion: @escaping (Result<Data, Error>) -> ()) {
        switch storage.fetch(from: url) {
        case .success(let data):
            completion(.success(data))

        case .failure:
            downloader.download(from: url) { [weak self] result in
                switch result {
                case .success(let data):
                    switch self?.storage.store(data: data, to: url) {
                    case .success?:
                        completion(.success(data))

                    case .failure(let error)?:
                        completion(.failure(error))

                    default:
                        struct ServiceDeallocated: Error {}
                        completion(.failure(ServiceDeallocated()))
                    }

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

struct ServiceFactory {
    static func new(
        storage: Storage = StorageFactory.new(),
        downloader: Downloader = DownloaderFactory.new()
    ) -> Service {
        return ServiceImpl(storage: storage, downloader: downloader)
    }
}

// 4 -------------------------------------------------------------------------------------

final class MockStorage: Storage {
    let fetchCall = FunctionCall<URL, Result<Data, Error>>()
    func fetch(from url: URL) -> Result<Data, Error> {
        return stubCall(fetchCall, argument: url, defaultValue: .failure(NSError.dummy))
    }
    
    let storeCall = FunctionCall<(Data, URL), Result<Void, Error>>()
    func store(data: Data, to url: URL) -> Result<Void, Error> {
        return stubCall(storeCall, argument: (data, url), defaultValue: .failure(NSError.dummy))
    }
}
  
final class MockDownloader: Downloader {
    let downloadCall = FunctionCall<(URL, (Result<Data, Error>) -> ()), Void>()
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ()) {
        return stubCall(downloadCall, argument: (url, completion), defaultValue: ())
    }
}

// 5 -------------------------------------------------------------------------------------

class ServiceSpec: QuickSpec {
    override func spec() {
        describe("Service") {
            var sut: Service!
            var storage: MockStorage!
            var downloader: MockDownloader!
            var url: URL!

            beforeEach {
                storage = MockStorage()
                downloader = MockDownloader()
                sut = ServiceFactory.new(storage: storage, downloader: downloader)
                url = URL(string: "https://betterme.world")!
            }

            describe("when asking to provide image") {
                it("should ask storage for data") {
                    sut.provide(for: url) { _ in () }

                    expect(storage.fetchCall.called).to(beTruthy())
                }
                
                context("and there is data stored") {
                    var data: Data!

                    beforeEach {
                        data = Data()
                        storage.fetchCall
                            .on { $0 == url }
                            .returns(.success(data))
                    }

                    it("should return correct data") {
                        var received: Result<Data, Error>!
                        sut.provide(for: url) { received = $0 }

                        expect { try received.get() }.to(equal(data))
                    }
                }

                context("and nothing stored") {
                    beforeEach {
                        storage.fetchCall.returns(.failure(NSError.dummy))
                    }

                    it("should start download") {
                        sut.provide(for: url) { _ in () }

                        expect(downloader.downloadCall.called).to(beTruthy())
                    }
                    
                    context("but download fails") {
                        struct DownloadError: Error {}

                        beforeEach {
                            downloader.downloadCall
                                .on { passed, _ in passed == url }
                                .performs { _, completion in
                                    completion(.failure(DownloadError()))
                                }
                        }

                        it("should return downloader error") {
                            var received: Result<Data, Error>!
                            sut.provide(for: url) { received = $0 }
                            
                            expect { try received?.get() }.to(throwError(DownloadError()))
                        }
                    }
                    
                    context("and download succeeds") {
                        var data: Data!
                        
                        beforeEach {
                            data = Data()
                            downloader.downloadCall
                                .on { passed, _ in passed == url }
                                .performs { _, completion in
                                    completion(.success(data))
                                }
                        }
                        
                        it("should store received data") {
                            sut.provide(for: url) { _ in () }

                            expect(storage.storeCall.called).to(beTruthy())
                        }
                        
                        context("but store fails") {
                            struct StoreError: Error {}
                            
                            beforeEach {
                                storage.storeCall
                                    .on { _, passed in passed == url }
                                    .returns(.failure(StoreError()))
                            }
                            
                            it("should return store error") {
                                var received: Result<Data, Error>!
                                sut.provide(for: url) { received = $0 }
                                
                                expect { try received?.get() }.to(throwError(StoreError()))
                            }
                        }
                        
                        context("and store succeeds") {
                            beforeEach {
                                storage.storeCall
                                    .on { _, passed in passed == url }
                                    .returns(.success(()))
                            }
                            
                            it("should return correct data") {
                                var received: Result<Data, Error>!
                                sut.provide(for: url) { received = $0 }
                                
                                expect { try received?.get() }.to(equal(data))
                            }
                        }
                    }
                }
            }
        }
    }
}

// 6 -------------------------------------------------------------------------------------

class ServiceAlternativeSpec: XCTestCase {
    var sut: Service!
    var storage: MockStorage!
    var downloader: MockDownloader!
    var url: URL!
    
    override func setUp() {
        super.setUp()
        
        storage = MockStorage()
        downloader = MockDownloader()
        sut = ServiceFactory.new(storage: storage, downloader: downloader)
        url = URL(string: "https://betterme.world")!
    }
    
    func test_whenAskingToProvideImage_it_shouldAskStorageForData() {
        //given
        
        //when
        sut.provide(for: url) { _ in () }
        
        //then
        XCTAssertTrue(storage.fetchCall.called)
    }
    
    func test_whenAskingToProvideImage_andThereIsDataStored_it_shouldReturnCorrectData() {
        //given
        let data = Data()
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.success(data))
        
        //when
        var received: Result<Data, Error>!
        sut.provide(for: url) { received = $0 }
        
        //then
        XCTAssertEqual(try received.get(), data)
    }
    
    func test_whenAskingToProvideImage_andNothingStored_it_shouldStartDownload() {
        //given
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))

        //when
        sut.provide(for: url) { _ in () }

        //then
        XCTAssertTrue(downloader.downloadCall.called)
    }
    
    func test_whenAskingToProvideImage_andNothingStored_butDownloadFails_it_shouldReturnDownloaderError() {
        //given
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                struct DownloadError: Error {}
                completion(.failure(DownloadError()))
            }
        
        //when
        var received: Result<Data, Error>!
        sut.provide(for: url) { received = $0 }
        
        //then
        XCTAssertThrowsError(try received.get())
    }
    
    func test_whenAskingToProvideImage_andNothingStored_andDownloadSucceeds_it_shouldStoreReceivedData() {
        //given
        let data = Data()
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.success(data))
            }
        
        //when
        sut.provide(for: url) { _ in () }
        
        //then
        XCTAssertTrue(storage.storeCall.called)
    }
    
    func test_whenAskingToProvideImage_andNothingStored_andDownloadSucceeds_butStoreFails_it_shouldReturnStoreError() {
        //given
        let data = Data()
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.success(data))
            }
        struct StoreError: Error {}
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.failure(StoreError()))
        
        //when
        var received: Result<Data, Error>!
        sut.provide(for: url) { received = $0 }
        
        //then
        XCTAssertThrowsError(try received.get())
    }
    
    func test_whenAskingToProvideImage_andNothingStored_andDownloadSucceeds_andStoreSucceeds_it_shouldReturnCorrectData() {
        //given
        let data = Data()
        storage.fetchCall
            .on { $0 == self.url }
            .returns(.failure(NSError.dummy))
        downloader.downloadCall
            .on { passed, _ in passed == self.url }
            .performs { _, completion in
                completion(.success(data))
            }
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.success(()))
        
        //when
        var received: Result<Data, Error>!
        sut.provide(for: url) { received = $0 }
        
        //then
        XCTAssertEqual(try received.get(), data)
    }
}

// 7 -------------------------------------------------------------------------------------

//let url = URL(string: "https://images.pexels.com/photos/67636/rose-blue-flower-rose-blooms-67636.jpeg")!
//let service = ServiceFactory.new()
//service.provide(for: url) { print($0) }

// 8 -------------------------------------------------------------------------------------

//ServiceSpec.defaultTestSuite.run()

// 9 -------------------------------------------------------------------------------------

//ServiceAlternativeSpec.defaultTestSuite.run()
