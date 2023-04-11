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
//  ShaderTypes.h
//  RemoteStream
//
//  Created by Brian Smith on 5/22/21.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, VertexInputIndex) {
    Vertices,
    ViewportSize
};

typedef NS_ENUM(NSInteger, TextureIndex) {
    TextureIndexBaseColor
};

typedef struct {
    simd_float2 position;
    simd_float2 textureCoordinate;
} Vertex;

#endif /* ShaderTypes_h */
