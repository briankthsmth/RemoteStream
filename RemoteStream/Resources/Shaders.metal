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
//  Shaders.metal
//  RemoteStream
//
//  Created by Brian Smith on 10/17/20.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct RasterizerData {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex RasterizerData vertexShader(uint vertexID [[ vertex_id ]],
                                   constant Vertex *vertexArray [[ buffer(VertexInputIndex::Vertices) ]],
                                   constant vector_uint2 *viewportSizePointer  [[ buffer(VertexInputIndex::ViewportSize) ]])
{
    RasterizerData outVertex;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);
    
    outVertex.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    outVertex.position.xy = pixelSpacePosition / (viewportSize / 2.0);
    outVertex.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return outVertex;
}

fragment float4 samplingShader(RasterizerData in [[ stage_in ]],
                               texture2d<half> colorTexture [[ texture(TextureIndexBaseColor) ]]) {
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
    
    return float4(colorSample);
}
