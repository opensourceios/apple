//
//  RefreshLibrary.swift
//  Kiwix
//
//  Created by Chris Li on 11/8/16.
//  Copyright © 2016 Chris Li. All rights reserved.
//

import ProcedureKit
import CoreData

class RefreshLibraryOperation: GroupProcedure {
    private(set) var hasUpdate = false
    private(set) var firstTime = Preference.libraryLastRefreshTime == nil
    
    init() {
        let retrieve = Retrieve()
        let process = Process()
        process.injectResult(from: retrieve)
        super.init(operations: [retrieve, process])
        
        process.add(observer: DidFinishObserver { [unowned self] (operation, error) in
            guard let process = operation as? Process else {return}
            self.hasUpdate = process.hasUpdate
        })
    }
}

fileprivate class Retrieve: NetworkDataProcedure<URLSession> {
    init() {
        let session = URLSession.shared
        let url = URL(string: "https://download.kiwix.org/library/library.xml")!
        let request = URLRequest(url: url)
        super.init(session: session, request: request)
        add(observer: NetworkObserver())
    }
}

fileprivate class Process: Procedure, ResultInjection, XMLParserDelegate {
    var requirement: PendingValue<HTTPResult<Data>> = .pending
    fileprivate(set) var result: PendingValue<Void> = .void
    private let context: NSManagedObjectContext
    
    private var storeBookIDs = Set<String>()
    private var memoryBookIDs = Set<String>()
    
    private(set) var hasUpdate = false
    
    override init() {
        self.context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = AppDelegate.persistentContainer.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        super.init()
    }
    
    override func execute() {
        guard let data = requirement.value?.payload else {
            finish(withError: ProcedureKitError.requirementNotSatisfied())
            return
        }
        
        storeBookIDs = Set(Book.fetchAll(in: context).map({ $0.id }))
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        
        let toBeDeleted = storeBookIDs.subtracting(memoryBookIDs)
        hasUpdate = toBeDeleted.count > 0
        context.performAndWait {
            toBeDeleted.forEach({ (id) in
                
            })
        }
        
        if context.hasChanges { try? context.save() }
        Preference.libraryLastRefreshTime = Date()
        finish()
    }
    
    fileprivate func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard elementName == "book", let id = attributeDict["id"] else {return}
        if !storeBookIDs.contains(id) {
            hasUpdate = true
            context.performAndWait({ 
                _ = Book.add(meta: attributeDict, in: self.context)
            })
        }
        memoryBookIDs.insert(id)
    }
    
    fileprivate func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        finish(withError: parseError)
    }
}
