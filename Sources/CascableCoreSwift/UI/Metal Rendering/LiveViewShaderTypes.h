#ifndef LiveViewShaderTypes_h
#define LiveViewShaderTypes_h

#include <simd/simd.h>

#pragma mark Base Rendering

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum LiveViewVertexInputIndex
{
    LiveViewVertexInputIndexVertices     = 0,
    LiveViewVertexInputIndexViewportSize = 1,
} LiveViewVertexInputIndex;

// Texture index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API texture set calls
typedef enum LiveViewTextureIndex
{
    LiveViewTextureIndexBaseColor = 0,
} LiveViewTextureIndex;

//  This structure defines the layout of each vertex in the array of vertices set as an input to the
//    Metal vertex shader.  Since this header is shared between the .metal shader and C code,
//    you can be sure that the layout of the vertex array in the code matches the layout that
//    the vertex shader expects

typedef struct
{
    // Positions in pixel space. A value of 100 indicates 100 pixels from the origin/center.
    vector_float2 position;

    // 2D texture coordinate
    vector_float2 textureCoordinate;
} LiveViewVertex;

#endif /* LiveViewShaderTypes_h */
