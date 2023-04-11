//
//  Copyright 2020-2023 Brian Keith Smith
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//  RemoteStreamAdapter.h
//  RemoteStream
//
//  Created by Brian Smith on 10/3/20.
//

#ifndef RemoteStream_h
#define RemoteStream_h
#import <Foundation/Foundation.h>

@interface RemoteStreamAdapter : NSObject
- (instancetype _Nonnull)initWithLocation:(NSString *_Nonnull)location sampleHandler:(void (^_Nonnull)(void *_Nonnull, NSUInteger, NSInteger, NSInteger))handler;
- (void)connect;
- (void)disconnect;
- (void)play;
- (void)pause;

@end

#endif /* RemoteStream_h */
