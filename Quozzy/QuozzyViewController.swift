//
//  CodeaProjectViewController.swift
//  Quozzy
//
//  Created by Jesse Wonder Clark on Thursday, February 19, 2026.
//  Copyright © 2019 Jesse Wonder Clark. All rights reserved.
//

import UIKit
import Tools
import RuntimeKit
import CraftKit

class CodeaProjectViewController: CodeaViewController {

    let projectUrl: URL
    
    init(url: URL, addons: [CodeaAddon]) {
        projectUrl = url
        
        let runtime = ThreadedRuntimeViewController(addons: [
            CodeaStandardLibrary(),
            CraftAddon()
        ] + addons)
        
        super.init(runtime: runtime, activityType: "exported-codea-project")
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        initializeRenderer {
            success in
            
            if !success {
                fatalError("Failed to load Codea project")
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        runtime.view.frame = view.bounds
    }

    func initializeRenderer(completion: @escaping (Bool)->()) {
        let project = Project(bundlePath: projectUrl.path)
        
        //AssetManager.sharedInstance().project = project
        
        runtime.project = project
        runtime.start {
            DispatchQueue.main.async {                
                self.runtime.startAnimation()
                
                completion(true)
            }
        }
    }
}
