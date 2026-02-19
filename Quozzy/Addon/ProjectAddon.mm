//
//  ProjectAddon.m
//  CodeaProject
//
//  Created by Simeon Saint-Saens on 17/3/19.
//  Copyright © 2019 Two Lives Left. All rights reserved.
//

#import "ProjectAddon.h"
#import <UIKit/UIKit.h>

#include "ModuleIncludes.h"

#import "ProjectModule.h"

@interface ProjectAddon ()

@property (nullable, nonatomic, assign) lua_State* L;
@property (nullable, nonatomic, weak) ThreadedRuntimeViewController* controller;

@end

@implementation ProjectAddon

+ (NSArray*) defaultModules
{
    return @[
             [ProjectModule new],
            ];
}
    
- (void)codea:(nonnull ThreadedRuntimeViewController *)controller didCreateLuaState:(nonnull struct lua_State *)L isValidating:(BOOL)validating {
    self.L = L;
    self.controller = controller;
    
    for(id<Module> mod in [ProjectAddon defaultModules]) {
        [mod registerForAddon:self];
    }
}
    
- (void)codeaWillDrawFrame:(ThreadedRuntimeViewController *)controller withDelta:(CGFloat)deltaTime {
    static NSUInteger frameCount = 0;
    frameCount += 1;
    
    if (frameCount == 1 || frameCount % 120 == 0) {
        CGRect bounds = controller.view.bounds;
        CGRect frame = controller.view.frame;
        UIScreen* screen = UIScreen.mainScreen;
        NSLog(@"[Quozzy] Native frame heartbeat: %lu (dt=%f) view.bounds=%@ view.frame=%@ screen.bounds=%@",
              (unsigned long)frameCount,
              deltaTime,
              NSStringFromCGRect(bounds),
              NSStringFromCGRect(frame),
              NSStringFromCGRect(screen.bounds));
    }
}
    
- (void)codeaDidFinishSetup:(CodeaViewController *)controller {
    NSLog(@"[Quozzy] codeaDidFinishSetup fired");
    if( self.ready ) {
        self.ready(self);
    }
}
    
@end
