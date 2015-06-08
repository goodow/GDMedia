//
// Created by Larry Tin on 15/6/8.
//

#import <UIKit/UIKit.h>
#import "GDMPlaybackHelper.h"
#import "VLCExternalDisplayController.h"

@implementation GDMPlaybackHelper {
  UIView *_drawable;
  UIView *_previousParentView;
  UIWindow *_externalWindow;
}

+ (GDMPlaybackHelper *)instance {
  static GDMPlaybackHelper *_instance = nil;

  @synchronized (self) {
    if (_instance == nil) {
      _instance = [[self alloc] init];
    }
  }

  return _instance;
}

#pragma mark - External Display

- (void)enableExternalDisplay:(UIView *)drawable {
  _drawable = drawable;
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(showOnExternalDisplay)
                 name:UIScreenDidConnectNotification object:nil];
  [center addObserver:self selector:@selector(hideFromExternalDisplay)
                 name:UIScreenDidDisconnectNotification object:nil];

  if ([self hasExternalDisplay]) {
    [self showOnExternalDisplay];
  }
}

- (void)showOnExternalDisplay {
  UIScreen *screen = [UIScreen screens][1];
  screen.overscanCompensation = UIScreenOverscanCompensationInsetApplicationFrame;

  _externalWindow = [[UIWindow alloc] initWithFrame:screen.bounds];

  UIViewController *controller = [[VLCExternalDisplayController alloc] init];
  _externalWindow.rootViewController = controller;
  _previousParentView = _drawable.superview;
  [controller.view addSubview:_drawable];
  controller.view.frame = screen.bounds;
  _drawable.frame = screen.bounds;

  _externalWindow.screen = screen;
  _externalWindow.hidden = NO;
}

- (void)hideFromExternalDisplay {
  [_previousParentView addSubview:_drawable];
  [_previousParentView sendSubviewToBack:_drawable];
  _drawable.frame = _previousParentView.frame;

  _previousParentView = nil;
  _externalWindow.hidden = YES;
  _externalWindow = nil;
}


- (BOOL)hasExternalDisplay {
  return ([[UIScreen screens] count] > 1);
}

@end