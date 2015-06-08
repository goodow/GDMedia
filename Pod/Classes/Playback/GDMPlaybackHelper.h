//
// Created by Larry Tin on 15/6/8.
//

#import <Foundation/Foundation.h>


@interface GDMPlaybackHelper : NSObject

+ (GDMPlaybackHelper *)instance;

- (void)enableExternalDisplay:(UIView *)drawable;

@end