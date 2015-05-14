//
// Created by Larry Tin on 15/5/14.
//

#import <MediaLibraryKit/MLMediaLibrary.h>
#import "GDMFileDiscoverer.h"
#import "NSString+SupportedMedia.h"
#import "VLCMediaFileDiscoverer.h"

@interface GDMFileDiscoverer () <VLCMediaFileDiscovererDelegate>
@end

@implementation GDMFileDiscoverer {
  NSMutableArray *observers;
}
- (instancetype)init {
  self = [super init];
  if (self) {
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
    NSString *fileName = foundFiles.firstObject;
    NSString *filePath = [documentPath stringByAppendingPathComponent:fileName];
    [foundFiles removeObject:fileName];

    if ([fileName isSupportedMediaFormat]) {
      [filePaths addObject:[@"Documents" stringByAppendingPathComponent:fileName]];

      /* exclude media files from backup (QA1719) */
      fileURL = [NSURL fileURLWithPath:filePath];
      [fileURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    } else {
      BOOL isDirectory = NO;
      BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];

      // add folders
      if (exists && isDirectory) {
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:filePath error:nil];
        for (NSString *file in files) {
          NSString *fullFilePath = [filePath stringByAppendingPathComponent:file];
          isDirectory = NO;
          exists = [[NSFileManager defaultManager] fileExistsAtPath:fullFilePath isDirectory:&isDirectory];
          //only add folders or files in folders
          if ((exists && isDirectory) || ![filePath.lastPathComponent isEqualToString:@"Documents"]) {
            NSString *folderpath = [filePath stringByReplacingOccurrencesOfString:documentPath withString:@""];
            if (![folderpath isEqualToString:@""]) {
              folderpath = [folderpath stringByAppendingString:@"/"];
            }
            NSString *path = [folderpath stringByAppendingString:file];
            [foundFiles addObject:path];
          }
        }
      }
    }
  }
  [[MLMediaLibrary sharedMediaLibrary] addFilePaths:filePaths];
}

#pragma mark - media discovering

- (void)mediaFileAdded:(NSString *)fileName loading:(BOOL)isLoading {
  if (isLoading) {
    return;
  }
  MLMediaLibrary *sharedLibrary = [MLMediaLibrary sharedMediaLibrary];
  [sharedLibrary addFilePaths:@[[fileName stringByReplacingOccurrencesOfString:[NSHomeDirectory() stringByAppendingString:@"/"] withString:@""]]];

  /* exclude media files from backup (QA1719) */
  NSURL *excludeURL = [NSURL fileURLWithPath:fileName];
  [excludeURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];

  // TODO Should we update media db after adding new files?
  [sharedLibrary updateMediaDatabase];
//    [bus publishLocal:QQPConstant.topicFileView payload:nil];
}

- (void)mediaFileDeleted:(NSString *)name {
  [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
//  [bus publishLocal:QQPConstant.topicFileView payload:nil];
}

- (NSString *)documentPath {
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}
@end