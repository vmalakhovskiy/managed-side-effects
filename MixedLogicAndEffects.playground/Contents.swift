import UIKit
import Quick
import Nimble
import SwiftyMock
import Shared

/* Content list:
    1 - Service (composes storage & downloader functions, provides interface for further integration)
    2 - Service BDD spec imeplementation
    3 - Service tests (XCTest) imeplementation
    4 - Uncomment this block to execute Service `provide` function. This is main input for our service
    5 - Uncomment this block to run BDD tests
    6 - Uncomment this block to run plain tests
*/

// 1 -------------------------------------------------------------------------------------

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

// 2 -------------------------------------------------------------------------------------

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

// 3 -------------------------------------------------------------------------------------

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
                completion(.failure(NSError.dummy))
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
        storage.storeCall
            .on { _, passed in passed == self.url }
            .returns(.failure(NSError.dummy))
        
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

// 4 -------------------------------------------------------------------------------------

//let url = URL(string: "https://images.pexels.com/photos/67636/rose-blue-flower-rose-blooms-67636.jpeg")!
//let service = ServiceFactory.new()
//service.provide(for: url) { print($0) }

// 5 -------------------------------------------------------------------------------------

//ServiceSpec.defaultTestSuite.run()

// 6 -------------------------------------------------------------------------------------

//ServiceAlternativeSpec.defaultTestSuite.run()
