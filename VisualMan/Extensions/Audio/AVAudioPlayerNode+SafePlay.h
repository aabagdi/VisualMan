//
//  AVAudioPlayerNode+SafePlay.h
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVAudioPlayerNode (SafePlay)

- (BOOL)vm_playAndReturnError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(playCatchingExceptions());

@end

NS_ASSUME_NONNULL_END
