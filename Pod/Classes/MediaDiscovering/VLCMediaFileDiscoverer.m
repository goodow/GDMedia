/*****************************************************************************
* VLCMediaFileDiscoverer.m
* VLC for iOS
*****************************************************************************
* Copyright (c) 2013 VideoLAN. All rights reserved.
* $Id$
*
* Authors: Gleb Pinigin <gpinigin # gmail.com>
*
* Refer to the COPYING file of the official project for license.
*****************************************************************************/

#import "VLCMediaFileDiscoverer.h"
#import "NSString+SupportedMedia.h"
#import "VLCConstants.h"
#import <GDChannel/GDCBusProvider.h>

const float MediaTimerInterval = 2.f;

@interface VLCMediaFileDiscoverer () {
  dispatch_source_t _directorySource;

  NSString *_directoryPath;
  NSArray *_directoryFiles;
  NSMutableDictionary *_addedFilesMapping;
  NSTimer *_addMediaTimer;

  id <GDCBus> _bus;
}

@end

@implementation VLCMediaFileDiscoverer

- (id)init {
  self = [super init];
  if (self) {
    _addedFilesMapping = [NSMutableDictionary dictionary];
    _bus = [GDCBusProvider instance];
  }

  return self;
}

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static VLCMediaFileDiscoverer *instance;
  dispatch_once(&onceToken, ^{
      instance = [VLCMediaFileDiscoverer new];
  });

  return instance;
}

#pragma mark - discovering

- (void)startDiscovering:(NSString *)directoryPath {
  _directoryPath = directoryPath;
  _directoryFiles = [self directoryFiles];

  int const folderDescriptor = open([directoryPath fileSystemRepresentation], O_EVTONLY);
  _directorySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, folderDescriptor,
      DISPATCH_VNODE_WRITE, DISPATCH_TARGET_QUEUE_DEFAULT);

  dispatch_source_set_event_handler(_directorySource, ^() {
      unsigned long const data = dispatch_source_get_data(_directorySource);
      if (data & DISPATCH_VNODE_WRITE) {
        // Do all the work on the main thread,
        // including timer scheduling, notifications delivering
        dispatch_async(dispatch_get_main_queue(), ^{
            [self directoryDidChange];
        });
      }
  });

  dispatch_source_set_cancel_handler(_directorySource, ^() {
      close(folderDescriptor);
  });

  dispatch_resume(_directorySource);
}

- (void)stopDiscovering {
  dispatch_source_cancel(_directorySource);

  [self invalidateTimer];
}

#pragma mark -

- (NSArray *)directoryFiles {
  NSArray *foundFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directoryPath
                                                                            error:nil];
  return foundFiles;
}

- (NSString *)path:(NSString *)relativePath {
  return [[_directoryPath stringByAppendingPathComponent:relativePath] stringByReplacingOccurrencesOfString:[NSHomeDirectory() stringByAppendingString:@"/"] withString:@""];
}

- (NSString *)getType:(NSString *)path {
  return [path isSupportedMediaFormat] ? @"video" : [path isSupportedSubtitleFormat] ? @"text" : [path isSupportedAudioMediaFormat] ? @"audio" : @"unknown";
}

#pragma mark - directory watcher delegate

- (void)directoryDidChange {
  NSArray *foundFiles = [self directoryFiles];

  if (_directoryFiles.count > foundFiles.count) { // File was deleted
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"not (self in %@)", foundFiles];
    NSArray *deletedFiles = [_directoryFiles filteredArrayUsingPredicate:filterPredicate];

    for (NSString *fileName in deletedFiles) {
      [_bus publishLocal:DirectoryWatchTopic payload:@{@"action" : @"delete", @"url" : [self path:fileName], @"type" : [self getType:fileName]}];
    }
  } else if (_directoryFiles.count < foundFiles.count) { // File was added
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"not (self in %@)", _directoryFiles];
    NSMutableArray *addedFiles = [NSMutableArray arrayWithArray:[foundFiles filteredArrayUsingPredicate:filterPredicate]];

    while (addedFiles.count) {
      NSString *relativePath = addedFiles.firstObject;
      NSString *fullPath = [_directoryPath stringByAppendingPathComponent:relativePath];
      [addedFiles removeObject:relativePath];
      BOOL isDirectory = NO;
      BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory];
      if (!exists) {
        continue;
      }
      if (!isDirectory) {
        if ([relativePath isSupportedFormat]) {
          [_addedFilesMapping setObject:@(0) forKey:relativePath];
          [_bus publishLocal:DirectoryWatchTopic payload:@{@"action" : @"discover", @"url" : [self path:relativePath], @"type" : [self getType:relativePath], @"size" : @(0)}];
        }
        continue;
      }

      // add folders
      NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fullPath error:nil];
      for (NSString *file in files) {
        [addedFiles addObject:[relativePath stringByAppendingPathComponent:file]];
      }
    }

    if (![_addMediaTimer isValid]) {
      _addMediaTimer = [NSTimer scheduledTimerWithTimeInterval:MediaTimerInterval
                                                        target:self selector:@selector(addFileTimerFired)
                                                      userInfo:nil repeats:YES];
    }
  }

  _directoryFiles = foundFiles;
}

#pragma mark - media timer

- (void)addFileTimerFired {
  NSArray *allKeys = [_addedFilesMapping allKeys];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  for (NSString *relativePath in allKeys) {
    NSString *fullPath = [_directoryPath stringByAppendingPathComponent:relativePath];
    if (![fileManager fileExistsAtPath:fullPath]) {
      [_addedFilesMapping removeObjectForKey:relativePath];
      continue;
    }

    NSNumber *prevFetchedSize = [_addedFilesMapping objectForKey:relativePath];

    NSDictionary *attribs = [fileManager attributesOfItemAtPath:fullPath error:nil];
    NSNumber *updatedSize = [attribs objectForKey:NSFileSize];
    if (!updatedSize) {
      continue;
    }

    [_bus publishLocal:DirectoryWatchTopic payload:@{@"action" : @"change", @"url" : [self path:relativePath], @"type" : [self getType:relativePath], @"size" : updatedSize}];

    if ([prevFetchedSize compare:updatedSize] == NSOrderedSame) {
      [_addedFilesMapping removeObjectForKey:relativePath];
      [_bus publishLocal:DirectoryWatchTopic payload:@{@"action" : @"add", @"url" : [self path:relativePath], @"type" : [self getType:relativePath], @"size" : updatedSize}];
    } else {
      [_addedFilesMapping setObject:updatedSize forKey:relativePath];
    }
  }

  if (_addedFilesMapping.count == 0) {
    [self invalidateTimer];
  }
}

- (void)invalidateTimer {
  [_addMediaTimer invalidate];
  _addMediaTimer = nil;
}

@end
