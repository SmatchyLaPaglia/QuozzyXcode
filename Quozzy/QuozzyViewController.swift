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
    
    // Tag Lua uses to find (and remove) the boot cover — see removeBootCover() in Main.lua.
    static let bootCoverTag = 9731
    private var bootCover: UIImageView?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Same cream + art as LaunchScreen.storyboard, so the hand-off from the launch screen to the
        // Codea runtime (which is a black Metal view until Lua's setup() finishes and the first frame
        // draws) is seamless instead of a black screen. Lua removes it on the first menu frame;
        // the timer is a safety net in case that never happens.
        view.backgroundColor = UIColor(red: 0.93725, green: 0.93333, blue: 0.90196, alpha: 1)
        let cover = UIImageView(image: UIImage(named: "Loading_QuozzySeasons"))
        cover.tag = CodeaProjectViewController.bootCoverTag
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.frame = view.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = view.backgroundColor
        view.addSubview(cover)
        bootCover = cover
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.bootCover?.removeFromSuperview()
            self?.bootCover = nil
        }

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
        if let cover = bootCover, cover.superview != nil { view.bringSubviewToFront(cover) }
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
