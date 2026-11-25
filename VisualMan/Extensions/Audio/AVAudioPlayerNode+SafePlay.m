//
//  AVAudioPlayerNode+SafePlay.m
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

#import "AVAudioPlayerNode+SafePlay.h"

static NSErrorDomain const VMPlayerNodeErrorDomain = @"com.VisualMan.AVAudioPlayerNode";

@implementation AVAudioPlayerNode (SafePlay)

- (BOOL)vm_playAndReturnError:(NSError * _Nullable * _Nullable)error {
  @try {
    if (@available(iOS 27.0, *)) {
      return [self playAndReturnError:error];
    }
    [self play];
    return YES;
  } @catch (NSException *exception) {
    if (error) {
      NSString *reason = exception.reason ?: exception.name;
      *error = [NSError errorWithDomain:VMPlayerNodeErrorDomain
                                   code:0
                               userInfo:@{NSLocalizedDescriptionKey: reason}];
    }
    return NO;
  }
}

@end
