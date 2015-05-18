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

const float MediaTimerInterval = 2.f;

@interface VLCMediaFileDiscoverer () {
  NSMutableArray *_observers;
  dispatch_source_t _directorySource;

  NSString *_directoryPath;
  NSArray *_directoryFiles;
  NSMutableDictionary *_addedFilesMapping;
  NSTimer *_addMediaTimer;
}

@end

@implementation VLCMediaFileDiscoverer

- (id)init {
  self = [super init];
  if (self) {
    _observers = [NSMutableArray array];
    _addedFilesMapping = [NSMutableDictionary dictionary];
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

#pragma mark - observation

- (void)addObserver:(id <VLCMediaFileDiscovererDelegate>)delegate {
  [_observers addObject:delegate];
}

- (void)removeObserver:(id <VLCMediaFileDiscovererDelegate>)delegate {
  [_observers removeObject:delegate];
}

- (void)notifyFileDeleted:(NSString *)relativePath {
  for (id <VLCMediaFileDiscovererDelegate> delegate in _observers) {
    if ([delegate respondsToSelector:@selector(mediaFileDeleted:)]) {
      [delegate mediaFileDeleted:[self fullPath:relativePath]];
    }
  }
}

- (void)notifyFileAdded:(NSString *)relativePath loading:(BOOL)isLoading {
  for (id <VLCMediaFileDiscovererDelegate> delegate in _observers) {
    if ([delegate respondsToSelector:@selector(mediaFileAdded:loading:)]) {
      [delegate mediaFileAdded:[self fullPath:relativePath] loading:isLoading];
    }
  }
}

- (void)notifySizeChanged:(NSString *)relativePath size:(unsigned long long)size {
  for (id <VLCMediaFileDiscovererDelegate> delegate in _observers) {
    if ([delegate respondsToSelector:@selector(mediaFileChanged:size:)]) {
      [delegate mediaFileChanged:[self fullPath:relativePath] size:size];
    }
  }
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

- (NSString *)fullPath:(NSString *)relativePath {
  return [_directoryPath stringByAppendingPathComponent:relativePath];
}

#pragma mark - directory watcher delegate

- (void)directoryDidChange {
  NSArray *foundFiles = [self directoryFiles];

  if (_directoryFiles.count > foundFiles.count) { // File was deleted
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"not (self in %@)", foundFiles];
    NSArray *deletedFiles = [_directoryFiles filteredArrayUsingPredicate:filterPredicate];

    for (NSString *fileName in deletedFiles) {
      [self notifyFileDeleted:fileName];
    }
  } else if (_directoryFiles.count < foundFiles.count) { // File was added
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"not (self in %@)", _directoryFiles];
    NSMutableArray *addedFiles = [NSMutableArray arrayWithArray:[foundFiles filteredArrayUsingPredicate:filterPredicate]];

    while (addedFiles.count) {
      NSString *relativePath = addedFiles.firstObject;
      NSString *fullPath = [self fullPath:relativePath];
      [addedFiles removeObject:relativePath];
      BOOL isDirectory = NO;
      BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory];
      if (!exists) {
        continue;
      }
      if (!isDirectory) {
        if ([relativePath isSupportedMediaFormat]) {
          [_addedFilesMapping setObject:@(0) forKey:relativePath];
          [self notifyFileAdded:relativePath loading:YES];
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
    NSString *fullPath = [self fullPath:relativePath];
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

    [self notifySizeChanged:relativePath size:[updatedSize unsignedLongLongValue]];

    if ([prevFetchedSize compare:updatedSize] == NSOrderedSame) {
      [_addedFilesMapping removeObjectForKey:relativePath];
      [self notifyFileAdded:relativePath loading:NO];
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
