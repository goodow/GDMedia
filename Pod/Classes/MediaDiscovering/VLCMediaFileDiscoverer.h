/*****************************************************************************
 * VLCMediaFileDiscoverer.h
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Gleb Pinigin <gpinigin # gmail.com>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import <Foundation/Foundation.h>

@interface VLCMediaFileDiscoverer : NSObject

- (void)startDiscovering:(NSString *)directoryPath;
- (void)stopDiscovering;

+ (instancetype)sharedInstance;

@end
