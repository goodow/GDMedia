//
// Created by Larry Tin on 15/5/14.
//

#import <MediaLibraryKit/MLMediaLibrary.h>
#import <GDChannel/GDCBusProvider.h>
#import "GDMFileDiscoverer.h"
#import "NSString+SupportedMedia.h"
#import "VLCMediaFileDiscoverer.h"

@interface GDMFileDiscoverer () <VLCMediaFileDiscovererDelegate>
@end

@implementation GDMFileDiscoverer {
  NSMutableArray *observers;
  id <GDCBus> bus;
}
- (instancetype)init {
  self = [super init];
  if (self) {
    bus = [GDCBusProvider instance];
    __weak GDMFileDiscoverer *weak = self;
    observers = [NSMutableArray array];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    UIApplication *application = [UIApplication sharedApplication];
    [observers addObject:[notificationCenter addObserverForName:UIApplicationWillEnterForegroundNotification object:application queue:nil usingBlock:^(NSNotification *note) {
        [[MLMediaLibrary sharedMediaLibrary] applicationWillStart];
    }]];
    [observers addObject:[notificationCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:application queue:nil usingBlock:^(NSNotification *note) {
        [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
        [weak updateMediaList];
    }]];

    [observers addObject:[notificationCenter addObserverForName:UIApplicationWillResignActiveNotification object:application queue:nil usingBlock:^(NSNotification *note) {
        [[MLMediaLibrary sharedMediaLibrary] applicationWillExit];
    }]];
    [observers addObject:[notificationCenter addObserverForName:UIApplicationWillTerminateNotification object:application queue:nil usingBlock:^(NSNotification *note) {
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];

    [[MLMediaLibrary sharedMediaLibrary] applicationWillStart];

    VLCMediaFileDiscoverer *discoverer = [VLCMediaFileDiscoverer sharedInstance];
    [discoverer addObserver:self];
    [discoverer startDiscovering:[self documentPath]];
  }

  return self;
}

- (void)dealloc {
  for (id observer in observers) {
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
  }
}

- (void)updateMediaList {
  NSString *documentPath = [self documentPath];
  NSMutableArray *foundFiles = [NSMutableArray arrayWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentPath error:nil]];
  NSMutableArray *filePaths = [NSMutableArray array];
  NSURL *fileURL;
  while (foundFiles.count) {
    NSString *relativePath = foundFiles.firstObject;
    NSString *fullPath = [documentPath stringByAppendingPathComponent:relativePath];
    [foundFiles removeObject:relativePath];
    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory];
    if (!exists) {
      continue;
    }
    if (!isDirectory) {
      if ([relativePath isSupportedMediaFormat]) {
        [filePaths addObject:[@"Documents" stringByAppendingPathComponent:relativePath]];

        /* exclude media files from backup (QA1719) */
        fileURL = [NSURL fileURLWithPath:fullPath];
        [fileURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
      }
      continue;
    }

    // add folders
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fullPath error:nil];
    for (NSString *file in files) {
      [foundFiles addObject:[relativePath stringByAppendingPathComponent:file]];
    }
  }
  [[MLMediaLibrary sharedMediaLibrary] addFilePaths:filePaths];
  [self updateViewContents];
}

#pragma mark - media discovering

- (void)mediaFileAdded:(NSString *)filePath loading:(BOOL)isLoading {
  if (isLoading) {
    return;
  }
  MLMediaLibrary *sharedLibrary = [MLMediaLibrary sharedMediaLibrary];
  [sharedLibrary addFilePaths:@[[filePath stringByReplacingOccurrencesOfString:[NSHomeDirectory() stringByAppendingString:@"/"] withString:@""]]];

  /* exclude media files from backup (QA1719) */
  NSURL *excludeURL = [NSURL fileURLWithPath:filePath];
  [excludeURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];

  // TODO Should we update media db after adding new files?
//  [sharedLibrary updateMediaDatabase];
  [self updateViewContents];
}

- (void)mediaFileDeleted:(NSString *)filePath {
  [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
  [self updateViewContents];
}

- (NSString *)documentPath {
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}

- (void)updateViewContents {
  [bus publishLocal:[[GDCBusProvider clientId:nil] stringByAppendingString:@"/file/view"] payload:@{@"_redirect" : @NO}];
}
@end