//
//  NTModulePluginTutorial.h
//  ModulePluginTutorial
//
//  Created by Steve Gehrman on 3/19/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// if XCode warns that it can't find this file, add this to all configurations.
// HEADER_SEARCH_PATHS = "../../CocoatechPluginProtocols"
#import "NTModulePluginProtocol.h"

@interface NTModulePluginTutorial : NSObject <NTModulePluginProtocol> {
	id<NTPathFinderPluginHostProtocol> mHost;
	NSView* mView;
}

@end
