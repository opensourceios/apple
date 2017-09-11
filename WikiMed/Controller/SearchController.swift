//
//  SearchController.swift
//  WikiMed
//
//  Created by Chris Li on 9/7/17.
//  Copyright © 2017 Chris Li. All rights reserved.
//

import UIKit
import ProcedureKit

class SearchController: UIViewController, UITableViewDelegate, UITableViewDataSource, ProcedureQueueDelegate {
    let containerView = SearchResultContainerView()
    let searchResultView = SearchResultView()
    
    let queue = ProcedureQueue()
    private(set) var results: [SearchResult] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        queue.delegate = self
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else {return}
        if traitCollection.horizontalSizeClass == .regular {
            configureForHorizontalRegular()
        } else if traitCollection.horizontalSizeClass == .compact {
            configureForHorizontalCompact()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(notification:)), name: .UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: .UIKeyboardWillHide, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardDidShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillHide, object: nil)
    }
    
    @objc func keyboardWillShow(notification: Notification)  {
        searchResultView.isHidden = true
    }
    
    @objc func keyboardDidShow(notification: Notification) {
        
        guard let userInfo = notification.userInfo as? [String: NSValue],
            let origin = userInfo[UIKeyboardFrameEndUserInfoKey]?.cgRectValue.origin else {return}
        let point = searchResultView.convert(origin, from: nil)
        searchResultView.bottomInset = searchResultView.frame.height - point.y
        searchResultView.isHidden = false
    }
    
    @objc func keyboardWillHide(notification: Notification) {
        searchResultView.bottomInset = 0
    }
    
    // MARK: - view manipulation
    
    private func configureViews() {
        view.backgroundColor = UIColor.clear
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(backgroundViewTapped))
        recognizer.delegate = containerView
        containerView.addGestureRecognizer(recognizer)
        
        searchResultView.tableView.register(SearchResultTitleCell.self, forCellReuseIdentifier: "TitleCell")
        searchResultView.tableView.register(SearchResultTitleSnippetCell.self, forCellReuseIdentifier: "TitleSnippetCell")
        searchResultView.tableView.dataSource = self
        searchResultView.tableView.delegate = self
    }
    
    private func configureForHorizontalCompact() {
        guard searchResultView.superview != view else {return}
        containerView.removeFromSuperview()
        searchResultView.removeFromSuperview()
        view.addSubview(searchResultView)
        view.addConstraints([
            searchResultView.topAnchor.constraint(equalTo: view.topAnchor),
            searchResultView.leftAnchor.constraint(equalTo: view.leftAnchor),
            searchResultView.rightAnchor.constraint(equalTo: view.rightAnchor),
            searchResultView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        searchResultView.tableView.backgroundColor = .white
    }
    
    private func configureForHorizontalRegular() {
        guard containerView.superview != view else {return}
        containerView.removeFromSuperview()
        searchResultView.removeFromSuperview()
        
        searchResultView.tableView.backgroundColor = .clear
        containerView.add(searchResultView: searchResultView)
        
        view.addSubview(containerView)
        view.addConstraints([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])
    }
    
    @objc func backgroundViewTapped() {
        guard let main = parent as? MainController else {return}
        main.searchBar.resignFirstResponder()
    }
    
    // MARK: - Search
    
    func startSearch(text: String) {
        let procedure = SearchProcedure(term: text)
        procedure.add(condition: MutuallyExclusive<SearchController>())
        procedure.add(observer: DidFinishObserver(didFinish: { [unowned self] (procedure, errors) in
            guard let procedure = procedure as? SearchProcedure else {return}
            OperationQueue.main.addOperation({
                self.results = procedure.results
            })
        }))
        queue.add(operation: procedure)
    }
    
    // MARK: - UITableView
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let result = results[indexPath.row]
        let identifier = result.hasSnippet ? "TitleSnippetCell" : "TitleCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        
        if let cell = cell as? SearchResultTitleCell {
            cell.titleLabel.text = result.title
        } else if let cell = cell as? SearchResultTitleSnippetCell {
            cell.titleLabel.text = result.title
            if let snippet = result.snippet {
                cell.snippetLabel.text = snippet
            } else if let snippet = result.attributedSnippet {
                cell.snippetLabel.attributedText = snippet
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let main = parent as? MainController else {return}
        main.searchBar.resignFirstResponder()
        main.tab.load(url: results[indexPath.row].url)
    }
    
    // MARK: - ProcedureQueueDelegate
    
    func procedureQueue(_ queue: ProcedureQueue, willAddProcedure procedure: Procedure, context: Any?) -> ProcedureFuture? {
        if queue.operationCount == 0 {
            DispatchQueue.main.async {
                self.searchResultView.tableView.isHidden = true
                self.searchResultView.emptyResult.isHidden = true
                self.searchResultView.searching.isHidden = false
                self.searchResultView.searching.activityIndicator.startAnimating()
            }
        } else {
            queue.operations.forEach({$0.cancel()})
        }
        return nil
    }
    
    func procedureQueue(_ queue: ProcedureQueue, didFinishProcedure procedure: Procedure, withErrors errors: [Error]) {
        guard queue.operationCount == 0 else {return}
        DispatchQueue.main.async {
            self.searchResultView.searching.activityIndicator.stopAnimating()
            self.searchResultView.searching.isHidden = true
            self.searchResultView.emptyResult.isHidden = self.results.count != 0
            self.searchResultView.tableView.isHidden = self.results.count == 0
            self.searchResultView.tableView.reloadData()
        }
    }
}
